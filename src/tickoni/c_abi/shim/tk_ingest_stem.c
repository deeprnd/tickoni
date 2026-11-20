/* tkings: bounded synthetic payment producer on Firedancer's fd_stem loop.
   The Zig payment runtime remains the sole owner of event generation. */
#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
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
static int tkings_stuck_enabled_param;
static uint64_t tkings_stuck_after_param;
static uint64_t tkings_stuck_sleep_param;
static uint32_t tkings_crash_after_param;

void tkings_set_event_count( uint64_t event_count ) { tkings_event_count_param = event_count; }
void tkings_set_payment_generator( tkings_payment_generator_t generator ) { tkings_generator_param = generator; }
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

static void
tkings_before_credit( tkings_ctx_t * ctx, fd_stem_context_t * stem, int * charge_busy ) {
    (void)stem;
    (void)charge_busy;
    if( ctx->stuck_enabled && ctx->produced>=ctx->stuck_after )
        for(;;) tk_sleep_nanos( ctx->stuck_sleep_ns );
    if( !ctx->event_count || ctx->input_exhausted || fd_cnc_signal_query( (fd_cnc_t *)ctx->cnc )==FD_CNC_SIGNAL_HALT ) return;
    /* Pure staging. This callback runs before reliable output credits are
       checked; the actual publish is in AFTER_CREDIT. */
    ctx->generator( ctx->produced, &ctx->staged );
}

static void
tkings_after_credit( tkings_ctx_t * ctx, fd_stem_context_t * stem, int * poll_in, int * charge_busy ) {
    *poll_in = 0; /* 0 input links; recheck credits before the next publish. */
    if( !ctx->event_count || ctx->input_exhausted || fd_cnc_signal_query( (fd_cnc_t *)ctx->cnc )==FD_CNC_SIGNAL_HALT ) return;
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
    if( FD_UNLIKELY( !tkings_generator_param ) )
        FD_LOG_ERR(( "tkings: payment generator was not configured" ));
    ctx->generator = tkings_generator_param;
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
    if( FD_UNLIKELY( !out->dcache || out->mtu<PAYMENT_MSG_SIZE ) )
        FD_LOG_ERR(( "tkings: invalid output dcache or mtu %lu", out->mtu ));
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
