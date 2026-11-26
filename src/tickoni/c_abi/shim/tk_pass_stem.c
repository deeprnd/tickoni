/* tk_pass_stem.c — placeholder fd_stem tiles for the full investment workflow:
 * tktool and tkadpt.
 *
 * These tiles have no financial behavior yet: the tool and adapter semantics
 * are not defined by the tkagnt migration plan, which does not authorize
 * inventing them.  They exist so the investment graph starts and its links are
 * consumed under the same bounded, credit-checked contract as every other tile.
 * One implementation, two registered identities:
 *
 *   tktool   consumes and counts its input; publishes nothing.
 *   tkadpt   consumes and counts its input; publishes nothing.
 *
 * They carry no traffic today (tkagnt issues no tool request), so they are idle
 * bounded consumers.  Their outputs are declared so the topology is the
 * approved one, and they never publish to them.  (tkcase, which used to share
 * this file as a forwarder, has its own tile: tk_case_stem.c.)
 *
 * Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG stages,
 * AFTER_FRAG commits, and SHOULD_SHUTDOWN is CNC HALT (no event gate: neither
 * tile sees an event).
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/shim/stem_diag.h"
#include "tickoni/c_abi/topo_run/tk_pass_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

#define TKPASS_MAX_OUTS 4UL
#define TKPASS_MTU      512UL     /* the largest link these tiles are wired to */

typedef struct {
    uint64_t consumed;            /* fragments committed from the input */
    int      stage_valid;
    ulong    stage_sz;
    uint8_t  stage[TKPASS_MTU];
    void *   cnc;
    stk_link_in_t  in;
    ulong          out_cnt;       /* pipeline outputs; the diagnostic link is not counted */
    stk_link_out_t out[TKPASS_MAX_OUTS];
    stk_diag_out_t diag;
} tkpass_ctx_t;

#define TKPASS_CTX_ALIGN alignof(tkpass_ctx_t)

static void tkpass_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkpass_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkpass_during_frag( tkpass_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong chunk, ulong sz, ulong ctl );
static void tkpass_after_frag( tkpass_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                               ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkpass_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define STEM_NAME                         tkpass
#define STEM_BURST                        (TKPASS_MAX_OUTS)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkpass_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKPASS_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tkpass_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkpass_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

static ulong
tkpass_scratch_align_tile( void ) {
    return TKPASS_CTX_ALIGN;
}

static ulong
tkpass_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkpass_ctx_t), TKPASS_CTX_ALIGN );
}

static void
tkpass_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkpass_ctx_t * ctx = STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
}

static void
tkpass_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkpass_ctx_t * ctx = STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if( FD_UNLIKELY( !ctx->cnc ) )
        FD_LOG_ERR(( "%s: CNC object not found for tile %lu", tile->name, tile->id ));
    if( FD_UNLIKELY( tile->in_cnt!=1UL ) )
        FD_LOG_ERR(( "%s: expected exactly one input link, found %lu", tile->name, tile->in_cnt ));
    /* The optional diagnostic link is the last output; stk_diag_out_init fails
       closed if a tile that is not a diagnostic producer (tktool, tkadpt) is
       wired to tkdiag. */
    ulong pipeline_out_cnt = tile->out_cnt - ( stk_diag_out_find( topo, tile )!=ULONG_MAX ? 1UL : 0UL );
    stk_diag_out_init( &ctx->diag, topo, tile, pipeline_out_cnt );
    if( FD_UNLIKELY( pipeline_out_cnt>TKPASS_MAX_OUTS ) )
        FD_LOG_ERR(( "%s: at most %lu output links, found %lu", tile->name, TKPASS_MAX_OUTS, pipeline_out_cnt ));
    fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[0]];
    if( FD_UNLIKELY( in_link->mtu>TKPASS_MTU ) )
        FD_LOG_ERR(( "%s: input mtu %lu above the %lu a fragment is staged in", tile->name, in_link->mtu, TKPASS_MTU ));
    stk_link_in_init( &ctx->in, topo, tile, 0UL, 1UL );

    /* Bound, never published to. */
    ctx->out_cnt = pipeline_out_cnt;
    for( ulong o=0UL; o<pipeline_out_cnt; o++ )
        stk_link_out_init( &ctx->out[o], topo, tile, o, 1UL );
}

static void
tkpass_during_frag( tkpass_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    ctx->stage_valid = 0;
    if( !sz || sz>TKPASS_MTU || !ctx->in.wksp ) return;
    if( FD_UNLIKELY( !stk_link_in_contains( &ctx->in, chunk ) ) ) return;

    memcpy( ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), sz );
    ctx->stage_sz    = sz;
    ctx->stage_valid = 1;
}

static void
tkpass_after_frag( tkpass_ctx_t *      ctx,
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

    ctx->consumed += 1UL;
    stk_publish_counter( ctx->cnc, 0UL, ctx->consumed );
    /* Unreliable diagnostic link: draws no credit, so STEM_BURST is unchanged. */
    stk_diag_publish( &ctx->diag, stem, in_idx, seq, ctx->consumed, 0UL, 0UL );
}

static void
tkpass_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkpass_ctx_t * ctx = STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN);

    FD_LOG_DEBUG(( "tkpass: run entry ctx=%p tile=%s:%lu", (void*)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "%s: CNC object not found for tile %lu", tile->name, tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkpass_run( topo, tile );

    tile->allow_shutdown = 1;
    FD_LOG_DEBUG(( "tkpass: run exit ctx=%p consumed=%lu", (void*)ctx, ctx->consumed ));
}

#define TKPASS_RUN_TILE( sym, tile_name )                          \
fd_topo_run_tile_t sym = {                                         \
    .name                     = tile_name,                         \
    .keep_host_networking     = 0,                                 \
    .allow_connect            = 0,                                 \
    .allow_renameat           = 0,                                 \
    .rlimit_file_cnt          = 0,                                 \
    .rlimit_address_space     = 0,                                 \
    .rlimit_data              = 0,                                 \
    .rlimit_nproc             = 0,                                 \
    .for_tpool                = 0,                                 \
    .max_event_sz             = NULL,                              \
    .populate_allowed_seccomp = NULL,                              \
    .populate_allowed_fds     = NULL,                              \
    .scratch_align            = tkpass_scratch_align_tile,         \
    .scratch_footprint        = tkpass_scratch_footprint_tile,     \
    .loose_footprint          = NULL,                              \
    .privileged_init          = tkpass_privileged_init,            \
    .unprivileged_init        = tkpass_unprivileged_init,          \
    .run                      = tkpass_run_entry,                  \
    .rlimit_file_cnt_fn       = NULL,                              \
}

TKPASS_RUN_TILE( TK_TOOL_RUN, TILE_ID_TKTOOL );
TKPASS_RUN_TILE( TK_ADPT_RUN, TILE_ID_TKADPT );

/* One scratch layout for both identities. */
ulong tkpass_tile_scratch_align( void )     { return tkpass_scratch_align_tile(); }
ulong tkpass_tile_scratch_footprint( void ) { return tkpass_scratch_footprint_tile( NULL ); }

/* Committed fragments consumed, read from the owning tile object's scratch base. */
ulong
tkpass_consumed( void * scratch ) {
    return STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN)->consumed;
}
