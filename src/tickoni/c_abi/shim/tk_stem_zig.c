/* tk_stem_zig.c — C helpers to register Zig callbacks in tk_stem_ctx_t.

   Each Tile's Zig code exports C-compatible callback functions. This file
   provides tk_stem_register_ctx() to populate tk_stem_ctx_t in workspace
   at tile_obj_id, so fd_stem can dispatch into Zig during its run loop.

   PLATFORM: Linux-only implementation.  On macOS/Windows this file
   compiles a no-op stub so the build succeeds.
*/

#include "tk_stem_zig.h"

/* ------------------------------------------------------------------
   Linux: full implementation.
   ------------------------------------------------------------------ */
#if FD_HAS_LINUX

/* tk_stem_zig_ctx_t — Zig-owned state passed as zig_state.
   Contains everything the C callbacks need to reach Zig. */
typedef struct tk_stem_zig_ctx {
    /* Pointer to tile_process.zig's g_ctx (opaque to C).
       Zig callbacks receive this as their ctx parameter. */
    void *zig_ctx;
    
    /* Workspace pointer for dcache chunk→laddr conversion in C helpers.
       Used when Zig callbacks need to read fragment data from workspace. */
    void *wksp;
    
    /* Tile ID from topology — used for diagnostics. */
    uint tile_id;
} tk_stem_zig_ctx_t;

void
tk_stem_register_ctx( void *                    topo,
                      void *                    tile,
                      void *                    zig_state,
                      void *                    wksp,
                      tk_stem_before_credit_fn  before_credit,
                      tk_stem_during_frag_fn    during_frag,
                      tk_stem_after_credit_fn   after_credit,
                      tk_stem_metrics_write_fn  metrics_write,
                      tk_stem_should_shutdown_fn should_shutdown ) {
    fd_topo_t *topo_c     = (fd_topo_t *)topo;
    fd_topo_tile_t *tile_c = (fd_topo_tile_t *)tile;
    
    /* Get tk_stem_ctx_t from workspace at tile_obj_id.
       This is where fd_stem expects to find callback function pointers. */
    tk_stem_ctx_t *stem_ctx = (tk_stem_ctx_t *)fd_topo_obj_laddr( topo_c, tile_c->tile_obj_id );
    if( !stem_ctx ) FD_LOG_ERR(( "tk_stem_register_ctx: no tile_obj_id for tile %s", tile_c->name ));
    
    /* Initialize to zero — if a callback pointer is NULL, stem callbacks skip it. */
    memset( stem_ctx, 0, sizeof(*stem_ctx) );
    
    /* Populate function pointers.
       These are Zig export fn functions with callconv(.C). */
    stem_ctx->zig_state = zig_state;
    stem_ctx->before_credit = before_credit;
    stem_ctx->during_frag = during_frag;
    stem_ctx->after_credit = after_credit;
    stem_ctx->metrics_write = metrics_write;
    stem_ctx->should_shutdown = should_shutdown;
}

/* ------------------------------------------------------------------
   Non-Linux: stub implementation.
   ------------------------------------------------------------------ */
#else /* !FD_HAS_LINUX */

void
tk_stem_register_ctx( void *                    topo,
                      void *                    tile,
                      void *                    zig_state,
                      void *                    wksp,
                      tk_stem_before_credit_fn  before_credit,
                      tk_stem_during_frag_fn    during_frag,
                      tk_stem_after_credit_fn   after_credit,
                      tk_stem_metrics_write_fn  metrics_write,
                      tk_stem_should_shutdown_fn should_shutdown ) {
    /* Stub — fd_stem is Linux-only. On non-Linux tile_run.c dispatches
       to tk_tile_run(), so this function is never called. */
    (void)topo; (void)tile; (void)zig_state; (void)wksp;
    (void)before_credit; (void)during_frag; (void)after_credit;
    (void)metrics_write; (void)should_shutdown;
}

#endif /* FD_HAS_LINUX */
