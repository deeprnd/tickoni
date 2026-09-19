/* tk_stem_ctx.h — tk_stem_ctx_t type and STEM_CALLBACK_* identity macros.

   This header provides the per-tile context type and callback macros
   that fd_stem.zig.h needs to populate tk_stem_ctx_t, without pulling
   in the full fd_stem.c template that generates stem_run().

   Included by: tk_stem_zig.h (type + macros only), tk_stem.c (type +
   macros + then includes fd_stem.c to generate tk_stem_run).

   Part of v2.22.S5 fd_stem migration. */

#ifndef HEADER_GUARD_tk_stem_ctx_h_
#define HEADER_GUARD_tk_stem_ctx_h_

/* ------------------------------------------------------------------
   Per-tile context placed in workspace at tile->tile_obj_id — populated
   by Tile's Zig code during privileged_init.  The fd_stem run loop
   reads the function pointers from this struct and dispatches into Zig.
   ------------------------------------------------------------------ */
typedef struct tk_stem_ctx {
    void *                      zig_state;
    int   (*should_shutdown)(void *zig_state);
    void  (*before_credit)(void *zig_state, void *stem, int *charge_busy);
    void  (*during_frag)(void *zig_state, uint idx, ulong seq, uint sig, ulong chunk, uint sz, uint ctl);
    void  (*after_credit)(void *zig_state, void *stem, int *poll_in, int *charge_busy);
    void  (*metrics_write)(void *zig_state);
} tk_stem_ctx_t;

/* ------------------------------------------------------------------
   Callback identity macros.

   Firedancer's fd_stem.c uses #ifdef STEM_CALLBACK_* to conditionally
   emit calls.  We define each macro to the same name so the #ifdef
   passes, then provide the actual function implementation.  fd_stem.c
   will emit calls to STEM_CALLBACK_* which expand to these function
   names.
   ------------------------------------------------------------------ */
#define STEM_CALLBACK_SHOULD_SHUTDOWN STEM_CALLBACK_SHOULD_SHUTDOWN
#define STEM_CALLBACK_BEFORE_CREDIT   STEM_CALLBACK_BEFORE_CREDIT
#define STEM_CALLBACK_DURING_FRAG     STEM_CALLBACK_DURING_FRAG
#define STEM_CALLBACK_AFTER_CREDIT    STEM_CALLBACK_AFTER_CREDIT
#define STEM_CALLBACK_METRICS_WRITE   STEM_CALLBACK_METRICS_WRITE

#endif /* HEADER_GUARD_tk_stem_ctx_h_ */
