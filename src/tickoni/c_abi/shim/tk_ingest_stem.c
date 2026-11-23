/* tkings: the ingestion tile on Firedancer's fd_stem loop -- the single entry
   point for every event into the spine.  Its only source is its one input
   link: tkapi's output in the product topologies (user requests), later also
   tkrepl's replay capsules, and in the isolation fixtures a link no tile
   produces (Firedancer's permit_no_producers) on which the integration test
   harness publishes directly.  tkings does not know or care which.

   Per fragment it validates the canonical framing of a TkEvent
   (tk_event_wire.h): one whole fragment of exactly sizeof(TkEvent), a known
   wire version, kind, source and flags (the replay bit only from tkrepl), and
   a nonzero producer-stamped trace_id.  It knows no domain semantics: the
   kind's own fields are tknorm's to judge.  A fragment that fails is dropped
   and counted (CNC slot 1, invalid).  One that passes gets its source_offset
   -- a per-source counter, so it is deterministic in arrival order -- has
   every field a later tile owns reset, and is published once.

   Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG copies
   and judges the copy, AFTER_FRAG commits (counters, offset, publish). */
#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_event_framing.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_ingest_stem.h"

#include <string.h>

typedef struct {
    uint64_t produced;               /* events forwarded */
    uint64_t invalid;                /* fragments dropped for their framing */
    uint64_t event_count;
    int input_exhausted;
    void * cnc;
    stk_link_in_t in;                /* from tkapi, or from outside the tile graph */
    stk_link_out_t out;              /* to tknorm */
    stk_diag_out_t diag;
    uint64_t next_offset[TK_EVENT_SOURCE_CNT];
    int stage_valid;                 /* a fragment was staged */
    int stage_ok;                    /* ...and its framing is canonical */
    TkEvent stage;
} tkings_ctx_t;

#define TKINGS_CTX_ALIGN alignof(tkings_ctx_t)

static uint64_t tkings_event_count_param;

void tkings_set_event_count( uint64_t event_count ) { tkings_event_count_param = event_count; }

/* The canonical framing of a whole-fragment TkEvent: the shared envelope
   checks (tk_event_framing.h) and a trace id.  A pure function of the staged
   copy. */
int
tkings_framing_ok( TkEvent const * ev ) {
    return tk_event_envelope_ok( ev ) && !tk_event_trace_id_is_zero( ev->trace_id );
}

/* DURING_FRAG: stage only (callback contract, stem_helpers.h).  A fragment
   whose chunk lies outside the input dcache is not read at all; one of the
   wrong size, or one that is not a whole message, is staged as invalid. */
static void
tkings_during_frag( tkings_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig, ulong chunk, ulong sz, ulong ctl ) {
    (void)in_idx; (void)seq;
    ctx->stage_valid = 0;
    ctx->stage_ok    = 0;
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) ) return;
    ctx->stage_valid = 1;
    if( FD_UNLIKELY( sig!=TK_LINK_SIG_EVENT || sz!=TK_EVENT_SIZE ) ) return;
    if( FD_UNLIKELY( !fd_frag_meta_ctl_som( ctl ) || !fd_frag_meta_ctl_eom( ctl ) ) ) return;
    memcpy( &ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), TK_EVENT_SIZE );
    ctx->stage_ok = tkings_framing_ok( &ctx->stage );
}

/* AFTER_FRAG: the fragment is intact.  Count a drop, or frame and publish. */
static void
tkings_after_frag( tkings_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig, ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem ) {
    (void)sig; (void)sz; (void)tsorig; (void)tspub;
    if( !ctx->stage_valid ) return;
    ctx->stage_valid = 0;

    if( !ctx->stage_ok ) {
        ctx->invalid++;
    } else {
        TkEvent * ev = &ctx->stage;
        /* The fields later tiles own start empty, whatever the producer wrote. */
        ev->source_offset = ctx->next_offset[ev->source]++;
        ev->pipeline_hops = 1;
        ev->duplicate     = 0;
        ev->decision      = (uint8_t)POLICY_ALLOW;
        ev->event_hash    = 0UL;
        ev->case_id       = 0UL;
        memset( ev->decided_by, 0, sizeof(ev->decided_by) );
        memset( ev->_pad, 0, sizeof(ev->_pad) );

        stk_link_out_publish( &ctx->out, stem, 0UL, TK_LINK_SIG_EVENT, ev, TK_EVENT_SIZE );
        ctx->produced++;
    }
    stk_publish_counter( ctx->cnc, 0UL, ctx->produced );
    stk_publish_counter( ctx->cnc, 1UL, ctx->invalid );
    /* Unreliable diagnostic link: draws no credit, STEM_BURST stays 1. */
    stk_diag_publish( &ctx->diag, stem, in_idx, seq, ctx->produced + ctx->invalid, ctx->invalid, 0UL );
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->produced + ctx->invalid );
}

#define STEM_NAME tkings
#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE tkings_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKINGS_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG tkings_during_frag
#define STEM_CALLBACK_AFTER_FRAG tkings_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
    ( (ctx)->input_exhausted || \
      ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc )==FD_CNC_SIGNAL_HALT ) )
#include "disco/stem/fd_stem.c"
#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

static ulong tkings_scratch_align_tile( void ) { return TKINGS_CTX_ALIGN; }
static ulong tkings_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkings_ctx_t), TKINGS_CTX_ALIGN );
}

static void
tkings_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkings_ctx_t * ctx = STK_GET_CTX( tkings_ctx_t, scratch, TKINGS_CTX_ALIGN );
    memset( ctx, 0, sizeof(*ctx) );
    /* Its input link is tkings's only source. */
    if( FD_UNLIKELY( tile->in_cnt!=1UL ) )
        FD_LOG_ERR(( "tkings: exactly one input link, found %lu", tile->in_cnt ));
    ctx->event_count = tkings_event_count_param;
}

static void
tkings_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkings_ctx_t * ctx = STK_GET_CTX( tkings_ctx_t, scratch, TKINGS_CTX_ALIGN );
    STK_UNPRIV_INIT( topo, tile, ctx );
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkings: CNC object not found for tile %lu", tile->id ));
    stk_diag_out_init( &ctx->diag, topo, tile, 1UL );

    stk_link_in_init ( &ctx->in,  topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
    stk_link_out_init( &ctx->out, topo, tile, 0UL, (ulong)TK_EVENT_SIZE );
}

static void
tkings_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile ) {
    tkings_run( topo, tile );
    tile->allow_shutdown = 1;
}

fd_topo_run_tile_t TK_INGEST_RUN = {
    .name = TILE_ID_TKINGS,
    .keep_host_networking = 0,
    .allow_connect = 0,
    .allow_renameat = 0,
    .rlimit_file_cnt = 0,
    .rlimit_address_space = 0,
    .rlimit_data = 0,
    .rlimit_nproc = 0,
    .for_tpool = 0,
    .max_event_sz = NULL,
    .populate_allowed_seccomp = NULL,
    .populate_allowed_fds = NULL,
    .scratch_align = tkings_scratch_align_tile,
    .scratch_footprint = tkings_scratch_footprint_tile,
    .loose_footprint = NULL,
    .privileged_init = tkings_privileged_init,
    .unprivileged_init = tkings_unprivileged_init,
    .run = tkings_run_entry,
    .rlimit_file_cnt_fn = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_ingest,
    TK_INGEST_RUN,
    tkings_tile_scratch_align,
    tkings_tile_scratch_footprint
)
