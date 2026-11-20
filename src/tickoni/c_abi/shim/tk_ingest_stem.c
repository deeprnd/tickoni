/* tkings: bounded synthetic producer on Firedancer's fd_stem loop.  Two
   sources, chosen by the Zig child before the harness runs, never both:

   - payment (production): one PaymentMessage fragment per event, generated
     by the Zig payment runtime (syntheticPayment);
   - agent request (test builds only): one multipart agent-request stream per
     offset, built by Zig (tk_ingest_stem.h, tkings_request_builder_t).

   The Zig runtime remains the sole owner of what is generated. */
#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tk_multipart.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_ingest_stem.h"

#include <string.h>
#include <stdlib.h>

extern void tk_sleep_nanos( uint64_t ns );

typedef struct {
    uint64_t produced;
    uint64_t event_count;
    int input_exhausted;
    void * cnc;
    void * out_wksp;
    ulong out_chunk0;
    ulong out_wmark;
    ulong out_chunk;
    stk_diag_out_t diag;
    tkings_payment_generator_t generator;
    tkings_request_builder_t request_builder;   /* agent-request source, else NULL */
    tkings_fragment_hook_t fragment_hook;
    tk_mp_tx_t tx;                              /* request in flight */
    int tx_active;
    int stuck_enabled;
    uint64_t stuck_after;
    uint64_t stuck_sleep_ns;
    uint32_t heartbeats;
    uint32_t crash_after_heartbeats;
    PaymentMessage staged;
} tkings_ctx_t;

#define TKINGS_CTX_ALIGN alignof(tkings_ctx_t)

static uint64_t tkings_event_count_param;
static tkings_payment_generator_t tkings_generator_param;
static tkings_request_builder_t tkings_request_builder_param;
static tkings_fragment_hook_t tkings_fragment_hook_param;
static int tkings_stuck_enabled_param;
static uint64_t tkings_stuck_after_param;
static uint64_t tkings_stuck_sleep_param;
static uint32_t tkings_crash_after_param;

void tkings_set_event_count( uint64_t event_count ) { tkings_event_count_param = event_count; }
void tkings_set_payment_generator( tkings_payment_generator_t generator ) { tkings_generator_param = generator; }
void tkings_set_request_source( tkings_request_builder_t builder, tkings_fragment_hook_t hook ) {
    tkings_request_builder_param = builder;
    tkings_fragment_hook_param = hook;
}
void tkings_set_stuck_hook( uint64_t after_messages, uint64_t sleep_ns ) {
    tkings_stuck_enabled_param = 1;
    tkings_stuck_after_param = after_messages;
    tkings_stuck_sleep_param = sleep_ns;
}
void tkings_set_crash_after_heartbeats( uint32_t heartbeat_count ) { tkings_crash_after_param = heartbeat_count; }

static void
tkings_housekeeping( tkings_ctx_t * ctx ) {
    stk_cnc_liveness( ctx->cnc );
    if( ctx->crash_after_heartbeats && ++ctx->heartbeats>=ctx->crash_after_heartbeats )
        _Exit(1);
}

/* Agent-request source: builds the request for the next offset, once per
   message.  The offset is `produced` because a message counts as produced only
   after its last fragment has been dealt with. */
static void
tkings_stage_request( tkings_ctx_t * ctx ) {
    if( ctx->tx_active ) return;
    uint8_t const * msg = NULL;
    uint64_t run_id = 0UL;
    ulong len = ctx->request_builder( ctx->produced, &msg, &run_id );
    if( FD_UNLIKELY( !len || !msg ||
                     tk_mp_tx_begin( &ctx->tx, TK_MP_DIR_REQUEST, TK_MP_CT_AGENT_REQUEST, run_id, run_id, msg, len )!=0 ) )
        FD_LOG_ERR(( "tkings: no valid agent request for offset %lu (length %lu)", (ulong)ctx->produced, len ));
    ctx->tx_active = 1;
}

/* Publishes the next fragment of the staged request.  The credit for it was
   reserved by fd_stem before this callback ran (STEM_BURST 1).  A fragment the
   hook withholds consumes no credit: the stream simply continues.  Counts the
   message produced once its last fragment is dealt with, withheld or not. */
static void
tkings_publish_request_fragment( tkings_ctx_t * ctx, fd_stem_context_t * stem, int * charge_busy ) {
    if( !ctx->tx_active ) return;
    ulong chunk = ctx->out_chunk;
    uint8_t * frag = (uint8_t *)fd_chunk_to_laddr( ctx->out_wksp, chunk );
    uint32_t frag_idx = ctx->tx.next_idx;
    uint32_t frag_cnt = ctx->tx.frag_cnt;
    int som, eom;
    ulong sz = tk_mp_tx_frag( &ctx->tx, frag, &som, &eom );
    int withhold = ctx->fragment_hook && ctx->fragment_hook( ctx->produced, frag_idx, frag_cnt, frag, sz );
    if( !withhold ) {
        fd_stem_publish( stem, 0UL, TK_LINK_SIG_AGENT_REQUEST, chunk, sz, fd_frag_meta_ctl( 0UL, som, eom, 0 ), 0UL, 0UL );
        ctx->out_chunk = fd_dcache_compact_next( chunk, sz, ctx->out_chunk0, ctx->out_wmark );
    }
    *charge_busy = 1;
    if( !tk_mp_tx_done( &ctx->tx ) ) return;
    ctx->tx_active = 0;
    ctx->produced++;
    stk_publish_counter( ctx->cnc, 0UL, ctx->produced );
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->produced );
}

static void
tkings_before_credit( tkings_ctx_t * ctx, fd_stem_context_t * stem, int * charge_busy ) {
    (void)stem;
    (void)charge_busy;
    if( ctx->stuck_enabled && ctx->produced>=ctx->stuck_after )
        for(;;) tk_sleep_nanos( ctx->stuck_sleep_ns );
    if( !ctx->event_count || ctx->input_exhausted || fd_cnc_signal_query( (fd_cnc_t *)ctx->cnc )==FD_CNC_SIGNAL_HALT ) return;
    /* Pure staging. This callback runs before reliable output credits are
       checked; the actual publish is in AFTER_CREDIT. */
    if( ctx->request_builder ) {
        tkings_stage_request( ctx );
        return;
    }
    ctx->generator( ctx->produced, &ctx->staged );
}

static void
tkings_after_credit( tkings_ctx_t * ctx, fd_stem_context_t * stem, int * poll_in, int * charge_busy ) {
    *poll_in = 0; /* 0 input links; recheck credits before the next publish. */
    if( !ctx->event_count || ctx->input_exhausted || fd_cnc_signal_query( (fd_cnc_t *)ctx->cnc )==FD_CNC_SIGNAL_HALT ) return;
    if( ctx->request_builder ) {
        tkings_publish_request_fragment( ctx, stem, charge_busy );
        return;
    }
    ulong chunk = ctx->out_chunk;
    memcpy( fd_chunk_to_laddr( ctx->out_wksp, chunk ), &ctx->staged, PAYMENT_MSG_SIZE );
    fd_stem_publish( stem, 0UL, 0UL, chunk, PAYMENT_MSG_SIZE, 0UL, 0UL, 0UL );
    ctx->out_chunk = fd_dcache_compact_next( chunk, PAYMENT_MSG_SIZE, ctx->out_chunk0, ctx->out_wmark );
    ctx->produced++;
    stk_publish_counter( ctx->cnc, 0UL, ctx->produced );
    stk_diag_publish( &ctx->diag, stem, 0UL, 0UL, ctx->produced, 0UL, 0UL );
    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->produced );
    *charge_busy = 1;
}

#define STEM_NAME tkings
#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE tkings_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKINGS_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) tkings_housekeeping( ctx )
#define STEM_CALLBACK_BEFORE_CREDIT tkings_before_credit
#define STEM_CALLBACK_AFTER_CREDIT tkings_after_credit
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
    ( (ctx)->input_exhausted || \
      ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc )==FD_CNC_SIGNAL_HALT ) )
#include "disco/stem/fd_stem.c"
#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_BEFORE_CREDIT
#undef STEM_CALLBACK_AFTER_CREDIT
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
    if( FD_UNLIKELY( !tkings_generator_param == !tkings_request_builder_param ) )
        FD_LOG_ERR(( "tkings: exactly one of the payment generator and the request source must be configured" ));
    ctx->generator = tkings_generator_param;
    ctx->request_builder = tkings_request_builder_param;
    ctx->fragment_hook = tkings_fragment_hook_param;
    ctx->event_count = tkings_event_count_param;
    ctx->stuck_enabled = tkings_stuck_enabled_param;
    ctx->stuck_after = tkings_stuck_after_param;
    ctx->stuck_sleep_ns = tkings_stuck_sleep_param;
    ctx->crash_after_heartbeats = tkings_crash_after_param;
    ctx->input_exhausted = 0;
}

static void
tkings_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkings_ctx_t * ctx = STK_GET_CTX( tkings_ctx_t, scratch, TKINGS_CTX_ALIGN );
    if( FD_UNLIKELY( tile->in_cnt ) )
        FD_LOG_ERR(( "tkings: expected no input links, found %lu", tile->in_cnt ));
    STK_UNPRIV_INIT( topo, tile, ctx );
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkings: CNC object not found for tile %lu", tile->id ));
    stk_diag_out_init( &ctx->diag, topo, tile, 1UL );
    fd_topo_link_t const * out = &topo->links[tile->out_link_id[0]];
    ulong need_mtu = ctx->request_builder ? (ulong)TK_MP_LINK_MTU : (ulong)PAYMENT_MSG_SIZE;
    if( FD_UNLIKELY( !out->dcache || out->mtu<need_mtu ) )
        FD_LOG_ERR(( "tkings: invalid output dcache or mtu %lu (need %lu)", out->mtu, need_mtu ));
    ctx->out_wksp = fd_topo_obj_wksp_base( topo, out->dcache_obj_id );
    if( FD_UNLIKELY( !ctx->out_wksp ) )
        FD_LOG_ERR(( "tkings: output workspace is not joined" ));
    ctx->out_chunk0 = fd_dcache_compact_chunk0( ctx->out_wksp, out->dcache );
    ctx->out_wmark = fd_dcache_compact_wmark( ctx->out_wksp, out->dcache, out->mtu );
    ctx->out_chunk = ctx->out_chunk0;
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
