/* tk_pass_stem.c — placeholder fd_stem tiles for the full investment workflow:
 * tkcase, tktool and tkadpt.
 *
 * These tiles have no financial behavior yet: the case, tool and adapter
 * semantics are not defined by the tkagnt migration plan, which does not
 * authorize inventing them.  They exist so the 14-tile investment graph starts
 * and its links are consumed under the same bounded, credit-checked contract as
 * every other tile.  One implementation, three registered identities:
 *
 *   tkcase   forwards every fragment it receives, unchanged, to each of its
 *            outputs (tkpoly and tkdisp).  No case state, no routing decision.
 *   tktool   consumes and counts its input; publishes nothing.
 *   tkadpt   consumes and counts its input; publishes nothing.
 *
 * tktool and tkadpt carry no traffic today (tkagnt issues no tool request), so
 * they are idle bounded consumers.  Their outputs are declared so the topology
 * is the approved one, and they never publish to them.
 *
 * Follows the fd_stem callback contract in stem_helpers.h: DURING_FRAG stages,
 * AFTER_FRAG commits and publishes (at most one fragment per output), and
 * SHOULD_SHUTDOWN is the event gate (tkcase only) plus CNC HALT.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
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
    uint64_t forwarded;           /* fragments published (tkcase only) */
    int      stage_valid;
    ulong    stage_sz;
    uint8_t  stage[TKPASS_MTU];
    int      forward;             /* tkcase: copy to every output */
    void *   cnc;
    void *   wksp;
    ulong    in_chunk0;
    ulong    in_wmark;
    ulong    out_cnt;
    void *   out_wksp[TKPASS_MAX_OUTS];
    ulong    out_chunk0[TKPASS_MAX_OUTS];
    ulong    out_wmark[TKPASS_MAX_OUTS];
    ulong    out_chunk[TKPASS_MAX_OUTS];
    uint64_t event_count;
    int      input_exhausted;
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

static ulong
tkpass_scratch_align_tile( void ) {
    return TKPASS_CTX_ALIGN;
}

static ulong
tkpass_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    return fd_ulong_align_up( sizeof(tkpass_ctx_t), TKPASS_CTX_ALIGN );
}

static uint64_t tkpass_event_count_param;

void
tkpass_set_event_count( uint64_t event_count ) {
    tkpass_event_count_param = event_count;
}

static void
tkpass_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkpass_ctx_t * ctx = STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN);
    memset( ctx, 0, sizeof(*ctx) );
    ctx->forward = strcmp( tile->name, TILE_ID_TKCASE )==0;
    /* Only the forwarding tile has an event gate: tktool and tkadpt see no
       traffic and stop on HALT. */
    ctx->event_count = ctx->forward ? tkpass_event_count_param : 0UL;
    ctx->wksp        = stk_derive_wksp( topo, tile, 0 );
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
    if( FD_UNLIKELY( tile->out_cnt>TKPASS_MAX_OUTS ) )
        FD_LOG_ERR(( "%s: at most %lu output links, found %lu", tile->name, TKPASS_MAX_OUTS, tile->out_cnt ));
    if( FD_UNLIKELY( ctx->forward && tile->out_cnt==0UL ) )
        FD_LOG_ERR(( "%s: a forwarding tile needs an output link", tile->name ));
    if( FD_UNLIKELY( !ctx->wksp ) )
        FD_LOG_ERR(( "%s: input workspace is not joined", tile->name ));

    fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[0]];
    if( FD_UNLIKELY( !in_link->dcache || !in_link->mtu || in_link->mtu>TKPASS_MTU ) )
        FD_LOG_ERR(( "%s: invalid input dcache or mtu %lu (max %lu)", tile->name, in_link->mtu, TKPASS_MTU ));
    ctx->in_chunk0 = fd_dcache_compact_chunk0( ctx->wksp, in_link->dcache );
    ctx->in_wmark  = fd_dcache_compact_wmark( ctx->wksp, in_link->dcache, in_link->mtu );

    ctx->out_cnt = tile->out_cnt;
    for( ulong o=0UL; o<tile->out_cnt; o++ ) {
        fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[o]];
        /* A forwarded fragment must fit every output it is copied to. */
        if( FD_UNLIKELY( !out_link->dcache || (ctx->forward && out_link->mtu<in_link->mtu) ) )
            FD_LOG_ERR(( "%s: output %lu has no dcache or an mtu under the input's", tile->name, o ));
        ctx->out_wksp[o] = fd_topo_obj_wksp_base( topo, out_link->dcache_obj_id );
        if( FD_UNLIKELY( !ctx->out_wksp[o] ) )
            FD_LOG_ERR(( "%s: output %lu workspace is not joined", tile->name, o ));
        ctx->out_chunk0[o] = fd_dcache_compact_chunk0( ctx->out_wksp[o], out_link->dcache );
        ctx->out_wmark[o]  = fd_dcache_compact_wmark( ctx->out_wksp[o], out_link->dcache, out_link->mtu );
        ctx->out_chunk[o]  = ctx->out_chunk0[o];
    }
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
    if( !sz || sz>TKPASS_MTU || !ctx->wksp ) return;
    if( FD_UNLIKELY( chunk<ctx->in_chunk0 || chunk>ctx->in_wmark ) ) return;

    memcpy( ctx->stage, stk_chunk_to_gaddr( ctx->wksp, chunk ), sz );
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
    (void)in_idx; (void)seq; (void)sz; (void)tsorig; (void)tspub;

    if( !ctx->stage_valid ) return;
    ctx->stage_valid = 0;

    ctx->consumed += 1UL;
    if( ctx->forward ) {
        for( ulong o=0UL; o<ctx->out_cnt; o++ ) {
            ulong chunk = ctx->out_chunk[o];
            memcpy( fd_chunk_to_laddr( ctx->out_wksp[o], chunk ), ctx->stage, ctx->stage_sz );
            fd_stem_publish( stem, o, sig, chunk, ctx->stage_sz, 0UL, 0UL, 0UL );
            ctx->out_chunk[o] = fd_dcache_compact_next( chunk, ctx->stage_sz, ctx->out_chunk0[o], ctx->out_wmark[o] );
        }
        ctx->forwarded += 1UL;
        STK_EVENT_EXHAUSTED( ctx, ctx->event_count, ctx->forwarded );
    }
    stk_publish_counter( ctx->cnc, 0UL, ctx->consumed );
}

static void
tkpass_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkpass_ctx_t * ctx = STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN);

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id == ULONG_MAX ) )
        FD_LOG_ERR(( "%s: CNC object not found for tile %lu", tile->name, tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkpass_run( topo, tile );

    tile->allow_shutdown = 1;
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

TKPASS_RUN_TILE( TK_CASE_RUN, TILE_ID_TKCASE );
TKPASS_RUN_TILE( TK_TOOL_RUN, TILE_ID_TKTOOL );
TKPASS_RUN_TILE( TK_ADPT_RUN, TILE_ID_TKADPT );

/* One scratch layout for all three identities. */
ulong tkpass_tile_scratch_align( void )     { return tkpass_scratch_align_tile(); }
ulong tkpass_tile_scratch_footprint( void ) { return tkpass_scratch_footprint_tile( NULL ); }

/* Committed fragments consumed, read from the owning tile object's scratch base. */
ulong
tkpass_consumed( void * scratch ) {
    return STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN)->consumed;
}

ulong
tkpass_forwarded( void * scratch ) {
    return STK_GET_CTX(tkpass_ctx_t, scratch, TKPASS_CTX_ALIGN)->forwarded;
}
