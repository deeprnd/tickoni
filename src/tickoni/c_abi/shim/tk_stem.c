/* tk_stem.c — bridges Firedancer fd_stem with Tickoni Zig tiles.

   Each Tile provides Zig callbacks via tk_stem_ctx_t placed in the tile's
   workspace object.  fd_stem's run loop calls those callbacks through the
   STEM_CALLBACK_* macros below.  No per-tile logic lives here.
*/

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"
#include "../../../disco/metrics/fd_metrics.h"
#include "../../../tango/fd_tango.h"
#include "../../stem/fd_stem.h"

/* Per-tile context placed in workspace at tile->tile_obj_id — populated by
   Tile's Zig code during privileged_init.  The fd_stem run loop reads the
   function pointers from this struct and dispatches into Zig.
*/
typedef struct {
    void *                      zig_state;
    int   (*should_shutdown)(void *zig_state);
    void  (*before_credit)(void *zig_state, fd_stem_context_t *stem, int *charge_busy);
    void  (*during_frag)(void *zig_state, uint idx, ulong seq, uint sig, ulong chunk, uint sz, uint ctl);
    void  (*after_credit)(void *zig_state, fd_stem_context_t *stem, int *poll_in, int *charge_busy);
    void  (*metrics_write)(void *zig_state);
} tk_stem_ctx_t;

/* ------------------------------------------------------------------
   STEM_CALLBACK_* dispatchers — these replace Firedancer's own callbacks
   (before_credit, during_frag, after_credit, metrics_write, should_shutdown)
   and forward to the Zig tile's exported functions.
   ------------------------------------------------------------------ */

#ifdef STEM_CALLBACK_SHOULD_SHUTDOWN
int
STEM_CALLBACK_SHOULD_SHUTDOWN(void *ctx) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->should_shutdown) return tk->should_shutdown(tk->zig_state);
    return 0;
}
#endif

#ifdef STEM_CALLBACK_BEFORE_CREDIT
void
STEM_CALLBACK_BEFORE_CREDIT(void *ctx, fd_stem_context_t *stem, int *charge_busy) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    (void)stem;
    if (tk->before_credit) tk->before_credit(tk->zig_state, stem, charge_busy);
    else *charge_busy = 0;
}
#endif

#ifdef STEM_CALLBACK_DURING_FRAG
void
STEM_CALLBACK_DURING_FRAG(void *ctx, uint idx, ulong seq, uint sig, ulong chunk, uint sz, uint ctl) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->during_frag) tk->during_frag(tk->zig_state, idx, seq, sig, chunk, sz, ctl);
}
#endif

#ifdef STEM_CALLBACK_AFTER_CREDIT
void
STEM_CALLBACK_AFTER_CREDIT(void *ctx, fd_stem_context_t *stem, int *poll_in, int *charge_busy) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    (void)stem;
    if (tk->after_credit) tk->after_credit(tk->zig_state, stem, poll_in, charge_busy);
    else { *poll_in = 1; *charge_busy = 0; }
}
#endif

#ifdef STEM_CALLBACK_METRICS_WRITE
void
STEM_CALLBACK_METRICS_WRITE(void *ctx) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->metrics_write) tk->metrics_write(tk->zig_state);
}
#endif

/* ------------------------------------------------------------------
   Entry point — called as TK_TILE_RUN.run by fd_topo_run_tile.

   Reads the tk_stem_ctx_t from the workspace at tile_obj_id, then
   delegates to fd_stem's run loop (stem_run) with those callbacks.
   ------------------------------------------------------------------ */
void
tk_stem_run(fd_topo_t *topo, fd_topo_tile_t *tile) {
    tk_stem_ctx_t *ctx = (tk_stem_ctx_t *)fd_topo_obj_laddr(topo, tile->tile_obj_id);
    if (!ctx) {
        FD_LOG_ERR(("tk_stem_run: tile %s tile_obj_id %lu not found",
                     tile->name, tile->tile_obj_id));
    }

    /* Read the stem from the registry — this is the same tk_stem_ctx_t
       placed at tile_obj_id; stem_run expects it as its ctx. */
    stem_run(ctx);
}
