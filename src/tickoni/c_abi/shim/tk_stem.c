/* tk_stem.c — bridges Firedancer fd_stem with Tickoni Zig tiles.

   Each Tile provides Zig callbacks via tk_stem_ctx_t placed in the tile's
   workspace object.  fd_stem's run loop calls those callbacks through the
   STEM_CALLBACK_* macros below.  No per-tile logic lives here.

   This file is the source of truth for the C bridge between fd_stem and
   Tickoni.  The template pattern (Firedancer's include-with-macros)
   generates tk_stem_run() from src/disco/stem/fd_stem.c.

   NOTE: fd_stem.c generates tk_stem_run() as a non-static function so it
   is linkable by tile_run.c's TK_TILE_RUN struct.

   PLATFORM: fd_stem is Linux-only.  On macOS/Windows tile_run.c dispatches
   to tk_tile_run() (the old per-tile loop).  The stub tk_stem_run() below
   is never called on non-Linux but exists to avoid link errors.
*/

/* ------------------------------------------------------------------
   Linux: full fd_stem integration.
   ------------------------------------------------------------------ */
#if FD_HAS_LINUX

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
   Callback implementations.

   Firedancer's fd_stem.c uses #ifdef STEM_CALLBACK_* to conditionally
   emit calls.  We define each macro so the #ifdef passes, then use the
   same name as the function (identity macros).  fd_stem.c will emit
   calls to STEM_CALLBACK_* which expand to the actual function names.
   ------------------------------------------------------------------ */

#define STEM_CALLBACK_SHOULD_SHUTDOWN STEM_CALLBACK_SHOULD_SHUTDOWN
int
STEM_CALLBACK_SHOULD_SHUTDOWN(void *ctx) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->should_shutdown) return tk->should_shutdown(tk->zig_state);
    return 0;
}

#define STEM_CALLBACK_BEFORE_CREDIT STEM_CALLBACK_BEFORE_CREDIT
void
STEM_CALLBACK_BEFORE_CREDIT(void *ctx, fd_stem_context_t *stem, int *charge_busy) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    (void)stem;
    if (tk->before_credit) tk->before_credit(tk->zig_state, stem, charge_busy);
    else *charge_busy = 0;
}

#define STEM_CALLBACK_DURING_FRAG STEM_CALLBACK_DURING_FRAG
void
STEM_CALLBACK_DURING_FRAG(void *ctx, uint idx, ulong seq, uint sig, ulong chunk, uint sz, uint ctl) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->during_frag) tk->during_frag(tk->zig_state, idx, seq, sig, chunk, sz, ctl);
}

#define STEM_CALLBACK_AFTER_CREDIT STEM_CALLBACK_AFTER_CREDIT
void
STEM_CALLBACK_AFTER_CREDIT(void *ctx, fd_stem_context_t *stem, int *poll_in, int *charge_busy) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    (void)stem;
    if (tk->after_credit) tk->after_credit(tk->zig_state, stem, poll_in, charge_busy);
    else { *poll_in = 1; *charge_busy = 0; }
}

#define STEM_CALLBACK_METRICS_WRITE STEM_CALLBACK_METRICS_WRITE
void
STEM_CALLBACK_METRICS_WRITE(void *ctx) {
    tk_stem_ctx_t *tk = (tk_stem_ctx_t *)ctx;
    if (tk->metrics_write) tk->metrics_write(tk->zig_state);
}

/* ------------------------------------------------------------------
   Template configuration — tell fd_stem.c how to generate tk_stem_run().

   STEM_NAME=tk_stem   → generates tk_stem_run(fd_topo_t*, fd_topo_tile_t*)
   STEM_BURST=1        → conservative burst size for Tickoni's per-tile model
   STEM_CALLBACK_CONTEXT_TYPE=tk_stem_ctx_t
   STEM_CALLBACK_CONTEXT_ALIGN=alignof(tk_stem_ctx_t)

   The STEM_CALLBACK_* macros are already defined above (identity macros).
   ------------------------------------------------------------------ */
#define STEM_NAME tk_stem_gen
#define STEM_BURST 1
#define STEM_CALLBACK_CONTEXT_TYPE tk_stem_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN alignof(tk_stem_ctx_t)

/* Include the template — generates tk_stem_gen_run(fd_topo_t*, fd_topo_tile_t*)
   which reads tk_stem_ctx_t from the workspace and runs the stem loop.
   We use tk_stem_gen to avoid collision with the non-static tk_stem_run()
   we define below for tile_run.c's TK_TILE_RUN .run pointer. */
#include "../../../disco/stem/fd_stem.c"

/* Non-static redirect for tile_run.c's TK_TILE_RUN .run pointer.
   The template generates a static inline void tk_stem_gen_run(...);
   this function is linkable by tile_run.c. */
void tk_stem_run( fd_topo_t * topo, fd_topo_tile_t * tile ) {
    FD_LOG_NOTICE(( "tk_stem_run: topo=%p tile=%p tile_obj_id=%lu", topo, tile, tile ? tile->tile_obj_id : 0 ));
    tk_stem_gen_run(topo, tile);
}

/* ------------------------------------------------------------------
   Non-Linux: stub that does nothing.  On macOS/Windows tile_run.c
   dispatches to tk_tile_run() instead, so this function is never
   called.  Kept only to avoid link errors on non-Linux builds.
   ------------------------------------------------------------------ */
#else /* !FD_HAS_LINUX */

void tk_stem_run( void * topo, void * tile ) {
    /* Stub — fd_stem is Linux-only. On non-Linux tile_run.c dispatches
       to tk_tile_run() instead, so this function is never called. */
    (void)topo;
    (void)tile;
}

#endif /* FD_HAS_LINUX */
