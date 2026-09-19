/* tk_stem.c — bridges Firedancer fd_stem with Tickoni Zig tiles.

   Each Tile provides Zig callbacks via tk_stem_ctx_t placed in the tile's
   workspace object.  fd_stem's run loop calls those callbacks through the
   STEM_CALLBACK_* macros below.  No per-tile logic lives here.

   This file is the source of truth for the C bridge between fd_stem and
   Tickoni.  The template pattern (Firedancer's include-with-macros)
   generates tk_stem_run() from src/disco/stem/fd_stem.c.
*/

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"
#include "../../../disco/metrics/fd_metrics.h"
#include "../../../tango/fd_tango.h"
#include "../../../disco/stem/fd_stem.h"

/* Per-tile context placed in workspace at tile->tile_obj_id — populated by
   Tile's Zig code during privileged_init.  The fd_stem run loop reads the
   function pointers from this struct and dispatches into Zig. */
typedef struct tk_stem_ctx {
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

   Firedancer's fd_stem.c template uses #ifdef STEM_CALLBACK_* to
   conditionally emit calls.  Each macro maps to a function name; we
   define those functions here.
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
   Template configuration — tell fd_stem.c how to generate tk_stem_run().

   STEM_NAME=tk_stem   → generates tk_stem_run(fd_topo_t*, fd_topo_tile_t*)
   STEM_BURST=1        → conservative burst size for Tickoni's per-tile model
   STEM_CALLBACK_CONTEXT_TYPE=tk_stem_ctx_t
   STEM_CALLBACK_CONTEXT_ALIGN=alignof(tk_stem_ctx_t)
   ------------------------------------------------------------------ */
#define STEM_NAME tk_stem
#define STEM_BURST 1
#define STEM_CALLBACK_CONTEXT_TYPE tk_stem_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN alignof(tk_stem_ctx_t)

/* Wire our dispatch functions as the callbacks.  fd_stem.c's #ifdef
   STEM_CALLBACK_* checks will include these calls in the generated loop. */
#define STEM_CALLBACK_SHOULD_SHUTDOWN STEM_CALLBACK_SHOULD_SHUTDOWN
#define STEM_CALLBACK_BEFORE_CREDIT   STEM_CALLBACK_BEFORE_CREDIT
#define STEM_CALLBACK_DURING_FRAG     STEM_CALLBACK_DURING_FRAG
#define STEM_CALLBACK_AFTER_CREDIT    STEM_CALLBACK_AFTER_CREDIT
#define STEM_CALLBACK_METRICS_WRITE   STEM_CALLBACK_METRICS_WRITE

/* Include the template — generates tk_stem_run(fd_topo_t*, fd_topo_tile_t*)
   which reads tk_stem_ctx_t from the workspace and runs the stem loop. */
#include "../../../disco/stem/fd_stem.c"
