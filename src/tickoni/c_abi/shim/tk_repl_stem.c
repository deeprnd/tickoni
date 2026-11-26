/* tk_repl_stem.c — tkrepl, the replay tile, on Firedancer's fd_stem loop.

     tkcase --(TkEvent ... TkEvent, TkCaseCapsuleMsg)--> tkrepl --(TkReplAuditMsg)--> tkaudt

   The replay side-channel of the investment workflow (unified-flow-diagram.md,
   plans/v2.NN-sXX-tkrepl-fd-stem-migration.md Phase 1).  tkrepl is not in the
   event spine.  tkcase streams it the run's case capsule as it builds it: each
   event it attaches, exactly as forwarded, and after the event that closes the
   case one summary of what the capsule holds (tkrepl_frag.h).

   - Replay with external effects disabled.  tkrepl has no model, adapter,
     ledger or execution path: it reads its one input and writes its one
     output.  It folds every capsule event into its own observation (count,
     the first event's case id and every later event checked against it, first
     and last source offset, and the capsule hash of tk_capsule_hash.h).
   - Verdict.  On the summary it asks the Zig verifier (TkReplHooks.verify,
     src/tickoni/tiles/replay/decision.zig) whether the observation matches
     what tkcase recorded.  The stem decides no divergence itself.
   - Report.  The verdict goes to tkaudt as one RECORD_REPLAY_RESULT record
     (case id, capsule hash as capsule_id, divergences, first divergent
     position; reliable: tkrepl waits for tkaudt, never drops), and to CNC
     slots 1 (replay_match) and then 0 (replay_checked), which tkdiag and the
     supervisor read.  Then the tile stops: one case per run.

   A topology without tkcase (the payment pipeline) gives tkrepl no link at
   all: it observes nothing and stops on CNC HALT.

   Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG stages a
   copy, AFTER_FRAG commits (the fold, the verdict, the publish, the counters).
   STEM_BURST is 1: the audit link gets one publish per run. */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_capsule_hash.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_repl_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

/* What DURING_FRAG staged. */
enum { TKREPL_STAGE_NONE = 0, TKREPL_STAGE_EVENT = 1, TKREPL_STAGE_SUMMARY = 2, TKREPL_STAGE_REJECT = 3 };

typedef struct {
    TkReplHooks    hooks;

    /* The observation: the fold of the capsule events received, in order. */
    uint64_t       observed_count;
    uint64_t       observed_case_id;
    uint64_t       observed_first_source_offset;
    uint64_t       observed_last_source_offset;
    uint64_t       observed_hash;
    uint64_t       case_id_mismatches;
    uint64_t       first_case_id_mismatch_seq;

    uint64_t       rejected;          /* fragments refused: wrong sig, size or framing, or after the verdict */

    /* The verdict, once the summary is in. */
    int            replay_checked;
    int            replay_match;
    TkCaseCapsuleMsg      summary;
    TkReplVerifyDirective verdict;

    int            stage_kind;
    union {
        TkEvent          ev;
        TkCaseCapsuleMsg summary;
    } stage;

    void *         cnc;
    int            has_input;         /* the topology feeds a capsule */
    stk_link_in_t  in;
    stk_link_out_t out;
} tkrepl_ctx_t;

#define TKREPL_CTX_ALIGN alignof(tkrepl_ctx_t)

static void tkrepl_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkrepl_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkrepl_during_frag( tkrepl_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkrepl_after_frag( tkrepl_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkrepl_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Stop after the one verdict, or on the supervisor's HALT. */
static inline int
tkrepl_should_shutdown( tkrepl_ctx_t const * ctx ) {
    return ctx->replay_checked ||
           ( ctx->cnc && fd_cnc_signal_query( (fd_cnc_t const *)ctx->cnc )==FD_CNC_SIGNAL_HALT );
}

#define STEM_NAME                         tkrepl
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkrepl_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKREPL_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tkrepl_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkrepl_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) tkrepl_should_shutdown( ctx )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── The verdict hook: an explicit run parameter ─── */

static TkReplHooks tkrepl_hooks_param;
static int         tkrepl_hooks_set;

int
tkrepl_set_hooks( TkReplHooks const * hooks ) {
    if( !hooks || !hooks->verify ) return 1;
    tkrepl_hooks_param = *hooks;
    tkrepl_hooks_set   = 1;
    return 0;
}

/* ─── Scratch footprint and alignment ─── */

static ulong
tkrepl_scratch_align_tile( void ) {
    return TKREPL_CTX_ALIGN;
}

static ulong
tkrepl_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkrepl_ctx_t), TKREPL_CTX_ALIGN );
}

/* ─── Init ─── */

static void
tkrepl_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkrepl_ctx_t * ctx = STK_GET_CTX(tkrepl_ctx_t, scratch, TKREPL_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );

    ctx->observed_hash = TK_CAPSULE_HASH_INIT;
    /* The tile never decides a divergence itself: with a capsule to replay it
       refuses to start without the Zig verdict. */
    if( tile->in_cnt && FD_UNLIKELY( !tkrepl_hooks_set ) )
        FD_LOG_ERR(( "tkrepl: no verdict hook installed" ));
    ctx->hooks = tkrepl_hooks_param;

    FD_LOG_NOTICE(( "tkrepl: privileged init ctx=%p in_cnt=%lu", (void *)ctx, tile->in_cnt ));
}

/* The name of the tile that produces `link_id`, or of the one that consumes
   it; NULL when there is none. */
static char const *
tkrepl_producer_of( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong o=0UL; o<other->out_cnt; o++ ) if( other->out_link_id[o]==link_id ) return other->name;
    }
    return NULL;
}

static char const *
tkrepl_consumer_of( fd_topo_t const * topo, ulong link_id ) {
    for( ulong t=0UL; t<topo->tile_cnt; t++ ) {
        fd_topo_tile_t const * other = &topo->tiles[t];
        for( ulong i=0UL; i<other->in_cnt; i++ ) if( other->in_link_id[i]==link_id ) return other->name;
    }
    return NULL;
}

static void
tkrepl_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkrepl_ctx_t * ctx = STK_GET_CTX(tkrepl_ctx_t, scratch, TKREPL_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkrepl: CNC object not found for tile %lu", tile->id ));

    /* Either the replay side-channel (the capsule from tkcase in, the verdict
       to tkaudt out) or no link at all. */
    if( FD_UNLIKELY( tile->in_cnt>1UL || tile->out_cnt!=tile->in_cnt ) )
        FD_LOG_ERR(( "tkrepl: expected one input and one output link, or none, found %lu and %lu",
                     tile->in_cnt, tile->out_cnt ));
    ctx->has_input = tile->in_cnt==1UL;
    if( ctx->has_input ) {
        char const * producer = tkrepl_producer_of( topo, tile->in_link_id[0] );
        char const * consumer = tkrepl_consumer_of( topo, tile->out_link_id[0] );
        if( FD_UNLIKELY( !producer || strcmp( producer, TILE_ID_TKCASE ) ) )
            FD_LOG_ERR(( "tkrepl: the input must come from %s, found %s", TILE_ID_TKCASE, producer ? producer : "no producer" ));
        if( FD_UNLIKELY( !consumer || strcmp( consumer, TILE_ID_TKAUDT ) ) )
            FD_LOG_ERR(( "tkrepl: the output must feed %s, found %s", TILE_ID_TKAUDT, consumer ? consumer : "no consumer" ));
        stk_link_in_init ( &ctx->in,  topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
        stk_link_out_init( &ctx->out, topo, tile, 0UL, sizeof(TkReplAuditMsg) );
    }

    FD_LOG_NOTICE(( "tkrepl: unprivileged init tile_id=%lu cnc=%p has_input=%d",
                    tile->id, ctx->cnc, ctx->has_input ));
}

/* ─── DURING_FRAG: stage only ─── */

static void
tkrepl_during_frag( tkrepl_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq;

    /* Clear first: fd_stem skips AFTER_FRAG for an overrun fragment, and a
       stale stage would let the next AFTER_FRAG fold an abandoned one. */
    ctx->stage_kind = TKREPL_STAGE_NONE;
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) ) return;
    ctx->stage_kind = TKREPL_STAGE_REJECT;
    if( FD_UNLIKELY( !fd_frag_meta_ctl_som( ctl ) || !fd_frag_meta_ctl_eom( ctl ) ) ) return;

    if( sig==TK_LINK_SIG_EVENT ) {
        if( !stk_validate_frag( sz, (ulong)TK_EVENT_SIZE, ctx->in.wksp ) ) return;
        memcpy( &ctx->stage.ev, stk_link_in_laddr( &ctx->in, chunk ), sizeof(TkEvent) );
        ctx->stage_kind = TKREPL_STAGE_EVENT;
    } else if( sig==TK_LINK_SIG_CASE_CAPSULE ) {
        if( !stk_validate_frag( sz, sizeof(TkCaseCapsuleMsg), ctx->in.wksp ) ) return;
        memcpy( &ctx->stage.summary, stk_link_in_laddr( &ctx->in, chunk ), sizeof(TkCaseCapsuleMsg) );
        ctx->stage_kind = TKREPL_STAGE_SUMMARY;
    }
}

/* ─── The fold and the verdict ─── */

static void
tkrepl_fold( tkrepl_ctx_t * ctx, TkEvent const * ev ) {
    ctx->observed_count += 1UL;
    if( ctx->observed_count==1UL ) {
        ctx->observed_case_id             = ev->case_id;
        ctx->observed_first_source_offset = ev->source_offset;
    } else if( ev->case_id!=ctx->observed_case_id ) {
        if( !ctx->case_id_mismatches ) ctx->first_case_id_mismatch_seq = ctx->observed_count;
        ctx->case_id_mismatches += 1UL;
    }
    ctx->observed_last_source_offset = ev->source_offset;
    ctx->observed_hash = tk_capsule_hash_append( ctx->observed_hash, ev );
}

static void
tkrepl_replay( tkrepl_ctx_t * ctx, fd_stem_context_t * stem ) {
    ctx->summary = ctx->stage.summary;

    TkReplVerifyQuery q;
    memset( &q, 0, sizeof(q) );
    q.summary                      = ctx->summary;
    q.observed_count               = ctx->observed_count;
    q.observed_case_id             = ctx->observed_case_id;
    q.observed_first_source_offset = ctx->observed_first_source_offset;
    q.observed_last_source_offset  = ctx->observed_last_source_offset;
    q.observed_hash                = ctx->observed_hash;
    q.case_id_mismatches           = ctx->case_id_mismatches;
    q.first_case_id_mismatch_seq   = ctx->first_case_id_mismatch_seq;
    ctx->verdict      = ctx->hooks.verify( &q );
    ctx->replay_match = ctx->verdict.divergences==0UL;

    TkReplAuditMsg * m = (TkReplAuditMsg *)stk_link_out_laddr( &ctx->out );
    memset( m, 0, sizeof(*m) );
    m->version                     = TK_REPL_WIRE_VERSION;
    m->record_type                 = RECORD_REPLAY_RESULT;
    m->case_id                     = ctx->summary.case_id;
    m->source_offset               = ctx->summary.last_source_offset;
    memcpy( m->trace_id, ctx->summary.trace_id, sizeof(m->trace_id) );
    m->payload.capsule_id          = ctx->summary.capsule_hash;
    m->payload.divergences         = ctx->verdict.divergences;
    m->payload.first_divergent_seq = ctx->verdict.first_divergent_seq;
    stk_link_out_commit( &ctx->out, stem, 0UL, TK_LINK_SIG_REPLAY_AUDIT, sizeof(*m), fd_frag_meta_ctl( 0UL, 1, 1, 0 ) );

    /* The result before the flag: a reader that sees replay_checked sees the
       final replay_match. */
    stk_publish_counter( ctx->cnc, 1UL, (ulong)ctx->replay_match );
    __atomic_thread_fence( __ATOMIC_RELEASE );
    stk_publish_counter( ctx->cnc, 0UL, 1UL );
    ctx->replay_checked = 1;
}

/* ─── AFTER_FRAG: commit ─── */

static void
tkrepl_after_frag( tkrepl_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub;

    int kind = ctx->stage_kind;
    ctx->stage_kind = TKREPL_STAGE_NONE;
    if( kind==TKREPL_STAGE_NONE ) return;
    /* One case per run: nothing is folded after the verdict. */
    if( kind==TKREPL_STAGE_REJECT || ctx->replay_checked ) { ctx->rejected += 1UL; return; }

    if( kind==TKREPL_STAGE_EVENT ) tkrepl_fold( ctx, &ctx->stage.ev );
    else                           tkrepl_replay( ctx, stem );
}

/* ─── Run entry ─── */

static void
tkrepl_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkrepl_ctx_t * ctx = STK_GET_CTX(tkrepl_ctx_t, scratch, TKREPL_CTX_ALIGN);

    FD_LOG_DEBUG(( "tkrepl: run entry ctx=%p tile=%s:%lu", (void *)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id==ULONG_MAX ) )
        FD_LOG_ERR(( "tkrepl: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkrepl_run( topo, tile );

    tile->allow_shutdown = 1;
    FD_LOG_DEBUG(( "tkrepl: run exit observed=%lu checked=%d match=%d divergences=%lu",
                   (ulong)ctx->observed_count, ctx->replay_checked, ctx->replay_match,
                   (ulong)ctx->verdict.divergences ));
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_REPL_RUN = {
    .name                     = TILE_ID_TKREPL,
    .keep_host_networking     = 0,
    .allow_connect            = 0,
    .allow_renameat           = 0,
    .rlimit_file_cnt          = 0,
    .rlimit_address_space     = 0,
    .rlimit_data              = 0,
    .rlimit_nproc             = 0,
    .for_tpool                = 0,
    .max_event_sz             = NULL,
    .populate_allowed_seccomp = NULL,
    .populate_allowed_fds     = NULL,
    .scratch_align            = tkrepl_scratch_align_tile,
    .scratch_footprint        = tkrepl_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkrepl_privileged_init,
    .unprivileged_init        = tkrepl_unprivileged_init,
    .run                      = tkrepl_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_replay,
    TK_REPL_RUN,
    tkrepl_tile_scratch_align,
    tkrepl_tile_scratch_footprint
)

/* ─── Scratch accessors (supervisor and tests; from the tile object's base) ─── */

#define TKREPL_CTX(scratch) STK_GET_CTX(tkrepl_ctx_t, scratch, TKREPL_CTX_ALIGN)

ulong tkrepl_replay_checked( void * scratch ) { return (ulong)TKREPL_CTX(scratch)->replay_checked; }
ulong tkrepl_replay_match( void * scratch )   { return (ulong)TKREPL_CTX(scratch)->replay_match; }
ulong tkrepl_observed_count( void * scratch ) { return TKREPL_CTX(scratch)->observed_count; }
ulong tkrepl_observed_hash( void * scratch )  { return TKREPL_CTX(scratch)->observed_hash; }
ulong tkrepl_rejected( void * scratch )       { return TKREPL_CTX(scratch)->rejected; }

void
tkrepl_verdict_copy( void * scratch, void * dst, ulong dst_sz ) {
    if( FD_UNLIKELY( dst_sz!=sizeof(TkReplVerifyDirective) ) )
        FD_LOG_ERR(( "tkrepl: verdict copy of %lu bytes, expected %lu", dst_sz, sizeof(TkReplVerifyDirective) ));
    memcpy( dst, &TKREPL_CTX(scratch)->verdict, sizeof(TkReplVerifyDirective) );
}
