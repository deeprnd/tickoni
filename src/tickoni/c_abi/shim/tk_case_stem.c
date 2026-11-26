/* tk_case_stem.c — tkcase, the case router, on Firedancer's fd_stem loop.

     tkdedu --(TkEvent)--> tkcase --(TkEvent)----------> tkpoly
                                  --(TkEvent)----------> tkdisp
                                  --(TkCaseAuditMsg)---> tkaudt
                                  --(diag fragment)----> tkdiag   (optional, last)

   V1 runs one case per run (plans/v2.NN-s03-tkcase-fd-stem-migration.md):

   - Case scope.  The first committed event opens the case: tkcase draws its
     case_id, a random nonzero u64 (the way tkgate fills in a missing trace id:
     a case is a generic identifier, not derived from what it touches), and
     records the scope the event names: workflow, actor and account of an
     agent request's scope, or a payment's account.  The case is then active.
   - Event attachment.  Every event is stamped with the case_id and forwarded,
     otherwise unchanged except pipeline_hops, to tkpoly and to tkdisp.
     Malformed and duplicate events are attached and forwarded too: tkpoly
     owns their decision.
   - Capsule.  Every event, as forwarded, is appended in order to the case
     capsule in this tile's scratch, sized by the run's event count (a layout
     parameter, like tkdedu's dedupe table).  It is the case's input record for
     replay and forensic reads; a full capsule is a fatal fault, never a
     silently dropped event.
   - Lifecycle audit.  Opening the case publishes a RECORD_CASE_CREATION
     record to tkaudt, and the event that exhausts the run's event count closes
     it with a RECORD_CASE_COMPLETION record.  Both carry the
     WireCaseCreationPayload shape with basket_id = case_id and zero counts.
     The audit link is reliable: tkcase waits for tkaudt, never drops.
     tkaudt commits the creation record before any record of the case and the
     completion record after the case's last one.

   The case-id generator is seeded from the tile's tick counter, unless the run
   sets a seed (tkcase_set_rng_seed, from TopologySpec.case_rng_seed): then the
   same inputs open the case under the same id, and commit the same audit
   chain, on every run.

   Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG stages a
   copy of the event, AFTER_FRAG commits (case open, capsule, counters, all
   publishes).  The case_id draw is in AFTER_FRAG because it advances the RNG.
   STEM_BURST is 2: the audit link gets two publishes in one iteration when a
   one-event run opens and closes its case on the same event; each event link
   gets one. */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_case_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/rng/fd_rng.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

/* Pipeline outputs, in topology order.  The diagnostic link, when wired, is
   the next one and is not counted here. */
enum { TKCASE_OUT_POLY = 0, TKCASE_OUT_DISP = 1, TKCASE_OUT_AUDIT = 2, TKCASE_OUT_CNT = 3 };

typedef struct {
    fd_rng_t       rng[1];             /* case ids */
    TkCaseScope    scope;              /* the run's one case; TK_CASE_STATE_NONE until the first event */

    uint64_t       consumed;           /* events committed from the input */
    uint64_t       forwarded;          /* event fragments published, summed over tkpoly and tkdisp */
    uint64_t       case_audit_emitted; /* lifecycle records published to tkaudt */

    /* The capsule: capsule_cap TkEvents in scratch, after the context. */
    uint64_t       capsule_cap;
    uint64_t       capsule_count;
    TkEvent *      capsule;

    int            stage_valid;
    TkEvent        stage;

    void *         cnc;
    stk_link_in_t  in;
    stk_link_out_t out[TKCASE_OUT_CNT];
    stk_diag_out_t diag;

    uint64_t       event_count;        /* shutdown gate and case close; 0 = no gate */
    int            input_exhausted;
} tkcase_ctx_t;

#define TKCASE_CTX_ALIGN alignof(tkcase_ctx_t)

static void tkcase_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkcase_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkcase_during_frag( tkcase_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkcase_after_frag( tkcase_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkcase_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkcase
#define STEM_BURST                        (2UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkcase_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKCASE_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tkcase_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkcase_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Capsule size: explicit runtime layout parameter ───

   The capsule holds every event of the run, so its size is the run's event
   count.  That count participates in workspace layout, so it reaches both the
   footprint query and privileged_init through tkcase_set_event_count(), which
   topo_build.build() calls before any footprint query with the value carried in
   TopologySpec: the supervisor and every child derive the same layout (the
   tkdedu pattern; never an environment variable).  A run without an event gate
   reserves the default. */
#define TKCASE_DEFAULT_CAPSULE_CAP 10000UL

static ulong tkcase_event_count_param = 0UL;

void
tkcase_set_event_count( ulong event_count ) {
    tkcase_event_count_param = event_count;
}

/* ─── Case-id seed: explicit run parameter (0 = the tick counter) ─── */

static ulong tkcase_rng_seed_param = 0UL;

void
tkcase_set_rng_seed( ulong seed ) {
    tkcase_rng_seed_param = seed;
}

static ulong
tkcase_layout_capsule_cap( void ) {
    return tkcase_event_count_param ? tkcase_event_count_param : TKCASE_DEFAULT_CAPSULE_CAP;
}

/* ─── Scratch footprint and alignment ─── */

static ulong
tkcase_scratch_align_tile( void ) {
    return fd_ulong_max( TKCASE_CTX_ALIGN, alignof(TkEvent) );
}

/* The capsule follows the context.  The single definition of that offset:
   privileged_init sets ctx->capsule from it, and the cross-process accessors
   below recompute it from their own scratch base (a tile-process pointer means
   nothing in the supervisor). */
static inline TkEvent *
tkcase_capsule_of( tkcase_ctx_t * ctx ) {
    return (TkEvent *)fd_ulong_align_up( (ulong)ctx + sizeof(tkcase_ctx_t), alignof(TkEvent) );
}

static ulong
tkcase_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tkcase_ctx_t), TKCASE_CTX_ALIGN );
    footprint = fd_ulong_align_up( footprint, alignof(TkEvent) );
    footprint += sizeof(TkEvent) * tkcase_layout_capsule_cap();
    return fd_ulong_align_up( footprint, tkcase_scratch_align_tile() );
}

/* ─── Init ─── */

static void
tkcase_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkcase_ctx_t * ctx = STK_GET_CTX(tkcase_ctx_t, scratch, TKCASE_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );

    ctx->event_count = tkcase_event_count_param;
    ctx->capsule_cap = tkcase_layout_capsule_cap();
    ctx->capsule     = tkcase_capsule_of( ctx );
    ulong seed = tkcase_rng_seed_param;
    uint  seq  = seed ? (uint)seed : (uint)fd_tickcount();
    ulong idx  = seed ? seed>>32   : 0UL;
    if( FD_UNLIKELY( !fd_rng_join( fd_rng_new( ctx->rng, seq, idx ) ) ) )
        FD_LOG_ERR(( "tkcase: rng init failed" ));

    FD_LOG_NOTICE(( "tkcase: privileged init ctx=%p event_count=%lu capsule_cap=%lu seeded=%d",
                    (void *)ctx, (ulong)ctx->event_count, (ulong)ctx->capsule_cap, seed!=0UL ));
}

static void
tkcase_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkcase_ctx_t * ctx = STK_GET_CTX(tkcase_ctx_t, scratch, TKCASE_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkcase: CNC object not found for tile %lu", tile->id ));
    if( FD_UNLIKELY( tile->in_cnt!=1UL ) )
        FD_LOG_ERR(( "tkcase: expected exactly one input link, found %lu", tile->in_cnt ));

    /* Exactly the three pipeline outputs, plus the optional diagnostic link
       last (stk_diag_out_init fails closed on anything else). */
    stk_diag_out_init( &ctx->diag, topo, tile, (ulong)TKCASE_OUT_CNT );
    stk_link_in_init ( &ctx->in, topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
    stk_link_out_init( &ctx->out[TKCASE_OUT_POLY],  topo, tile, (ulong)TKCASE_OUT_POLY,  (ulong)TK_EVENT_SIZE );
    stk_link_out_init( &ctx->out[TKCASE_OUT_DISP],  topo, tile, (ulong)TKCASE_OUT_DISP,  (ulong)TK_EVENT_SIZE );
    stk_link_out_init( &ctx->out[TKCASE_OUT_AUDIT], topo, tile, (ulong)TKCASE_OUT_AUDIT, sizeof(TkCaseAuditMsg) );

    /* Each output must go where its index says: a swapped link would send the
       audit record to tkpoly or an event to tkaudt. */
    static char const * const want[ TKCASE_OUT_CNT ] = { TILE_ID_TKPOLY, TILE_ID_TKDISP, TILE_ID_TKAUDT };
    for( ulong o=0UL; o<(ulong)TKCASE_OUT_CNT; o++ ) {
        char const * consumer = NULL;
        for( ulong t=0UL; t<topo->tile_cnt && !consumer; t++ ) {
            fd_topo_tile_t const * other = &topo->tiles[t];
            for( ulong i=0UL; i<other->in_cnt; i++ )
                if( other->in_link_id[i]==tile->out_link_id[o] ) { consumer = other->name; break; }
        }
        if( FD_UNLIKELY( !consumer || strcmp( consumer, want[o] ) ) )
            FD_LOG_ERR(( "tkcase: output %lu must feed %s, found %s", o, want[o], consumer ? consumer : "no consumer" ));
    }

    FD_LOG_NOTICE(( "tkcase: unprivileged init tile_id=%lu cnc=%p diag=%d",
                    tile->id, ctx->cnc, ctx->diag.present ));
}

/* ─── DURING_FRAG: stage only ─── */

static void
tkcase_during_frag( tkcase_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)ctl;

    /* Clear first: fd_stem skips AFTER_FRAG for an overrun fragment, and a
       stale flag would let the next AFTER_FRAG attach an abandoned event. */
    ctx->stage_valid = 0;
    if( FD_UNLIKELY( sig!=TK_LINK_SIG_EVENT ) ) return;
    if( !stk_validate_frag( sz, (ulong)TK_EVENT_SIZE, ctx->in.wksp ) ) return;
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) ) return;

    memcpy( &ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), sizeof(TkEvent) );
    ctx->stage.pipeline_hops += 1;
    ctx->stage_valid = 1;
}

/* ─── Case lifecycle ─── */

/* A random nonzero case id. */
static uint64_t
tkcase_case_id_generate( fd_rng_t * rng ) {
    uint64_t id;
    do { id = fd_rng_ulong( rng ); } while( FD_UNLIKELY( !id ) );
    return id;
}

/* The scope the opening event names.  An agent request carries its workflow,
   actor and account in its model-request scope; a payment names only its
   account.  An event of another kind names none. */
static void
tkcase_scope_from_event( TkCaseScope * scope, TkEvent const * ev ) {
    memset( scope->workflow, 0, sizeof(scope->workflow) );
    scope->actor_id   = 0UL;
    scope->account_id = 0UL;
    if( ev->kind==TK_EVENT_KIND_AGENT_REQUEST ) {
        ModelRequestMsg const * s = &ev->body.agent_request.scope;
        memcpy( scope->workflow, s->workflow, sizeof(scope->workflow) );
        scope->actor_id   = s->actor_id;
        scope->account_id = s->account_id;
    } else if( ev->kind==TK_EVENT_KIND_PAYMENT ) {
        scope->account_id = ev->body.payment.account_id;
    }
}

/* One lifecycle record to tkaudt, triggered by event `ev`. */
static void
tkcase_publish_lifecycle( tkcase_ctx_t *       ctx,
                          fd_stem_context_t *  stem,
                          uint8_t              record_type,
                          TkEvent const *      ev ) {
    TkCaseAuditMsg * m = (TkCaseAuditMsg *)stk_link_out_laddr( &ctx->out[TKCASE_OUT_AUDIT] );
    memset( m, 0, sizeof(*m) );
    m->version       = TK_CASE_WIRE_VERSION;
    m->record_type   = record_type;
    m->case_id       = ctx->scope.case_id;
    m->source_offset = ev->source_offset;
    m->event_count   = ctx->scope.event_count;
    memcpy( m->trace_id, ev->trace_id, sizeof(m->trace_id) );
    m->payload.basket_id = ctx->scope.case_id;
    stk_link_out_commit( &ctx->out[TKCASE_OUT_AUDIT], stem, (ulong)TKCASE_OUT_AUDIT,
                         TK_LINK_SIG_CASE_AUDIT, sizeof(*m), fd_frag_meta_ctl( 0UL, 1, 1, 0 ) );
    ctx->case_audit_emitted += 1UL;
}

/* ─── AFTER_FRAG: commit ─── */

static void
tkcase_after_frag( tkcase_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)sig; (void)sz; (void)tsorig; (void)tspub;

    if( !ctx->stage_valid ) return;
    ctx->stage_valid = 0;
    TkEvent * ev = &ctx->stage;

    /* The capsule must hold every event: fail closed before attaching one it
       cannot hold.  A fault the tile detects itself, so it tells tkdiag first. */
    if( FD_UNLIKELY( ctx->capsule_count>=ctx->capsule_cap ) ) {
        stk_diag_fault( &ctx->diag );
        stk_diag_publish( &ctx->diag, stem, in_idx, seq, ctx->consumed, 0UL, ctx->case_audit_emitted );
        FD_LOG_ERR(( "tkcase: capsule full at %lu events", (ulong)ctx->capsule_cap ));
    }

    /* Open the case on its first event. */
    int opened = 0;
    if( ctx->scope.state==TK_CASE_STATE_NONE ) {
        ctx->scope.case_id             = tkcase_case_id_generate( ctx->rng );
        ctx->scope.state               = TK_CASE_STATE_ACTIVE;
        ctx->scope.first_source_offset = ev->source_offset;
        tkcase_scope_from_event( &ctx->scope, ev );
        opened = 1;
    }

    /* Attach and record. */
    ev->case_id = ctx->scope.case_id;
    ctx->capsule[ ctx->capsule_count++ ] = *ev;
    ctx->scope.event_count        += 1UL;
    ctx->scope.last_source_offset  = ev->source_offset;
    ctx->consumed                 += 1UL;

    /* The creation record goes out before the case's first event. */
    if( opened ) tkcase_publish_lifecycle( ctx, stem, RECORD_CASE_CREATION, ev );

    stk_link_out_publish( &ctx->out[TKCASE_OUT_POLY], stem, (ulong)TKCASE_OUT_POLY, TK_LINK_SIG_EVENT, ev, sizeof(*ev) );
    stk_link_out_publish( &ctx->out[TKCASE_OUT_DISP], stem, (ulong)TKCASE_OUT_DISP, TK_LINK_SIG_EVENT, ev, sizeof(*ev) );
    ctx->forwarded += 2UL;

    /* The event that exhausts the run's count closes the case.  Checked on the
       post-increment count so the gate fires on the Nth event. */
    if( ctx->event_count && ctx->consumed>=ctx->event_count && ctx->scope.state==TK_CASE_STATE_ACTIVE ) {
        ctx->scope.state = TK_CASE_STATE_COMPLETED;
        tkcase_publish_lifecycle( ctx, stem, RECORD_CASE_COMPLETION, ev );
    }

    stk_publish_counter( ctx->cnc, 0UL, ctx->forwarded );
    /* Unreliable diagnostic link: draws no credit, so STEM_BURST is unchanged. */
    stk_diag_publish( &ctx->diag, stem, in_idx, seq, ctx->consumed, 0UL, ctx->case_audit_emitted );
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->consumed );
}

/* ─── Run entry ─── */

static void
tkcase_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkcase_ctx_t * ctx = STK_GET_CTX(tkcase_ctx_t, scratch, TKCASE_CTX_ALIGN);

    FD_LOG_DEBUG(( "tkcase: run entry ctx=%p tile=%s:%lu", (void *)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id==ULONG_MAX ) )
        FD_LOG_ERR(( "tkcase: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkcase_run( topo, tile );

    tile->allow_shutdown = 1;
    FD_LOG_DEBUG(( "tkcase: run exit consumed=%lu forwarded=%lu case_state=%u",
                   (ulong)ctx->consumed, (ulong)ctx->forwarded, (uint)ctx->scope.state ));
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_CASE_RUN = {
    .name                     = TILE_ID_TKCASE,
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
    .scratch_align            = tkcase_scratch_align_tile,
    .scratch_footprint        = tkcase_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkcase_privileged_init,
    .unprivileged_init        = tkcase_unprivileged_init,
    .run                      = tkcase_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_case,
    TK_CASE_RUN,
    tkcase_tile_scratch_align,
    tkcase_tile_scratch_footprint
)

/* ─── Scratch accessors (supervisor and tests; from the tile object's base) ─── */

#define TKCASE_CTX(scratch) STK_GET_CTX(tkcase_ctx_t, scratch, TKCASE_CTX_ALIGN)

ulong tkcase_consumed( void * scratch )      { return TKCASE_CTX(scratch)->consumed; }
ulong tkcase_forwarded( void * scratch )     { return TKCASE_CTX(scratch)->forwarded; }
ulong tkcase_case_audit_emitted( void * scratch ) { return TKCASE_CTX(scratch)->case_audit_emitted; }
ulong tkcase_capsule_count( void * scratch ) { return TKCASE_CTX(scratch)->capsule_count; }

void
tkcase_scope_copy( void * scratch, void * dst, ulong dst_sz ) {
    if( FD_UNLIKELY( dst_sz!=sizeof(TkCaseScope) ) )
        FD_LOG_ERR(( "tkcase: scope copy of %lu bytes, expected %lu", dst_sz, sizeof(TkCaseScope) ));
    memcpy( dst, &TKCASE_CTX(scratch)->scope, sizeof(TkCaseScope) );
}

void
tkcase_capsule_copy( void * scratch, ulong idx, void * dst, ulong dst_sz ) {
    tkcase_ctx_t * ctx = TKCASE_CTX(scratch);
    if( FD_UNLIKELY( dst_sz!=sizeof(TkEvent) ) )
        FD_LOG_ERR(( "tkcase: capsule copy of %lu bytes, expected %lu", dst_sz, sizeof(TkEvent) ));
    if( FD_UNLIKELY( idx>=ctx->capsule_count ) )
        FD_LOG_ERR(( "tkcase: capsule entry %lu of %lu", idx, (ulong)ctx->capsule_count ));
    memcpy( dst, &tkcase_capsule_of( ctx )[ idx ], sizeof(TkEvent) );
}
