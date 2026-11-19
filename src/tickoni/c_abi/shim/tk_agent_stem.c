/* tk_agent_sink_stem.c — Stem fd_stem sink for the tkmodl result link.
 *
 * Registered under the tkagnt tile id: the consumer of tkmodl's result link.
 * tkagnt is not yet a runnable agent tile, so this is a bounded observer that
 * receives each correlated ModelResultMsg, keeps it in a fixed ring for
 * inspection from the supervisor's scratch base, and counts committed results.
 * It makes no decisions and calls nothing.
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - DURING_FRAG: validate framing and wire version, copy the result into the
 *   staged slot.  Stages only.
 * - AFTER_FRAG: append the staged result to the ring, advance the committed
 *   count, apply the event gate.  Sink: no publish.
 * - SHOULD_SHUTDOWN: event_count exhaustion + CNC HALT.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_agent_sink_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKAGNT_RESULT_CAPACITY 256

typedef struct {
    uint64_t received;          /* committed results */
    int      stage_valid;
    ModelResultMsg staged;
    void *   cnc;
    void *   wksp;
    ulong    in_chunk0;
    ulong    in_wmark;
    uint64_t event_count;
    int      input_exhausted;
    /* results[] follows the context in the same scratch object; see
       tkagnt_results_of(). */
} tkagnt_ctx_t;

#define TKAGNT_CTX_ALIGN alignof(tkagnt_ctx_t)

static void tkagnt_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkagnt_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkagnt_during_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkagnt_after_frag( tkagnt_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkagnt_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkagnt
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkagnt_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKAGNT_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG         tkagnt_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkagnt_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* The result ring sits directly after the aligned context.  The single
   definition of that offset: init uses it, and the accessors recompute it from
   the caller's scratch base (a cross-process read cannot trust a stored
   pointer). */
static inline ModelResultMsg *
tkagnt_results_of( tkagnt_ctx_t * ctx ) {
    return (ModelResultMsg *)fd_ulong_align_up( (ulong)ctx + sizeof(tkagnt_ctx_t),
                                                alignof(ModelResultMsg) );
}

static ulong
tkagnt_scratch_align_tile( void ) {
    return fd_ulong_max( TKAGNT_CTX_ALIGN, alignof(ModelResultMsg) );
}

static ulong
tkagnt_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tkagnt_ctx_t), alignof(ModelResultMsg) );
    footprint += sizeof(ModelResultMsg) * TKAGNT_RESULT_CAPACITY;
    return fd_ulong_align_up( footprint, tkagnt_scratch_align_tile() );
}

static uint64_t tkagnt_event_count_param;

void
tkagnt_set_event_count( uint64_t event_count ) {
    tkagnt_event_count_param = event_count;
}

static void
tkagnt_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
    ctx->event_count = tkagnt_event_count_param;
    ctx->wksp        = stk_derive_wksp( topo, tile, 0 );
}

static void
tkagnt_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "tkagnt: CNC object not found for tile %lu", tile->id ));
    if( FD_UNLIKELY( tile->in_cnt != 1UL ) )
        FD_LOG_ERR(( "tkagnt: expected exactly one input link, found %lu", tile->in_cnt ));
    if( FD_UNLIKELY( tile->out_cnt != 0UL ) )
        FD_LOG_ERR(( "tkagnt: sink expects no output links, found %lu", tile->out_cnt ));
    if( FD_UNLIKELY( !ctx->wksp ) )
        FD_LOG_ERR(( "tkagnt: input workspace is not joined" ));

    fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[0]];
    if( FD_UNLIKELY( !in_link->dcache || in_link->mtu < sizeof(ModelResultMsg) ) )
        FD_LOG_ERR(( "tkagnt: invalid input dcache or mtu %lu", in_link->mtu ));
    ctx->in_chunk0 = fd_dcache_compact_chunk0( ctx->wksp, in_link->dcache );
    ctx->in_wmark  = fd_dcache_compact_wmark( ctx->wksp, in_link->dcache, in_link->mtu );
}

static void
tkagnt_during_frag( tkagnt_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    ctx->stage_valid = 0;

    if( !stk_validate_frag( sz, sizeof(ModelResultMsg), ctx->wksp ) )
        return;
    if( FD_UNLIKELY( chunk < ctx->in_chunk0 || chunk > ctx->in_wmark ) )
        return;

    memcpy( &ctx->staged, stk_chunk_to_gaddr( ctx->wksp, chunk ), sizeof(ModelResultMsg) );
    if( ctx->staged.version != TKMODL_WIRE_VERSION )
        return;
    ctx->stage_valid = 1;
}

static void
tkagnt_after_frag( tkagnt_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub; (void)stem;

    if( !ctx->stage_valid )
        return;
    ctx->stage_valid = 0;

    if( FD_UNLIKELY( ctx->received >= TKAGNT_RESULT_CAPACITY ) ) {
        FD_LOG_WARNING(( "tkagnt: result ring full at %lu", (ulong)ctx->received ));
        return;
    }
    tkagnt_results_of( ctx )[ctx->received] = ctx->staged;
    ctx->received += 1;

    STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->received );
}

static void
tkagnt_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "tkagnt: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkagnt_run( topo, tile );

    tile->allow_shutdown = 1;
}

fd_topo_run_tile_t TK_AGENT_SINK_RUN = {
    .name                     = TILE_ID_TKAGNT,
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
    .scratch_align            = tkagnt_scratch_align_tile,
    .scratch_footprint        = tkagnt_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkagnt_privileged_init,
    .unprivileged_init        = tkagnt_unprivileged_init,
    .run                      = tkagnt_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_agent_sink,
    TK_AGENT_SINK_RUN,
    tkagnt_tile_scratch_align,
    tkagnt_tile_scratch_footprint
)

/* ─── Scratch-base accessors (committed results only) ─── */

ulong
tkagnt_result_count( void * scratch ) {
    return STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN)->received;
}

static ModelResultMsg const *
tkagnt_result_at( void * scratch, ulong idx ) {
    tkagnt_ctx_t * ctx = STK_GET_CTX(tkagnt_ctx_t, scratch, TKAGNT_CTX_ALIGN);
    if( FD_UNLIKELY( idx>=ctx->received ) )
        FD_LOG_ERR(( "tkagnt: result index %lu out of range (committed %lu)", idx, (ulong)ctx->received ));
    return &tkagnt_results_of( ctx )[idx];
}

ulong tkagnt_result_request_id( void * s, ulong i )     { return tkagnt_result_at( s, i )->request_id; }
ulong tkagnt_result_run_id( void * s, ulong i )         { return tkagnt_result_at( s, i )->run_id; }
uint  tkagnt_result_decision( void * s, ulong i )       { return (uint)tkagnt_result_at( s, i )->decision; }
ulong tkagnt_result_prompt_hash( void * s, ulong i )    { return tkagnt_result_at( s, i )->prompt_hash; }
ulong tkagnt_result_response_hash( void * s, ulong i )  { return tkagnt_result_at( s, i )->response_hash; }
ulong tkagnt_result_replay_substitution_id( void * s, ulong i ) { return tkagnt_result_at( s, i )->replay_substitution_id; }
uint  tkagnt_result_total_tokens( void * s, ulong i )   { return tkagnt_result_at( s, i )->total_tokens; }
uint  tkagnt_result_prompt_tokens( void * s, ulong i )  { return tkagnt_result_at( s, i )->prompt_tokens; }
uint  tkagnt_result_completion_tokens( void * s, ulong i ) { return tkagnt_result_at( s, i )->completion_tokens; }

void
tkagnt_result_failed_scope_dim( void * scratch, ulong idx, uint8_t * dst ) {
    memcpy( dst, tkagnt_result_at( scratch, idx )->failed_scope_dim, TKMODL_SCOPE_DIM_LEN );
}

void
tkagnt_result_model_id( void * scratch, ulong idx, uint8_t * dst ) {
    memcpy( dst, tkagnt_result_at( scratch, idx )->model_id, TKMODL_MODEL_ID_LEN );
}
