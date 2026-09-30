/* tk_stem.h — tk_stem_ctx_t definition for tile_footprint in topob.c.

   This header contains only the struct definition so that topob.c can
   include it to compute tile_footprint.  The full implementation
   (stem callbacks, fd_stem template) lives in tk_stem.c.

   This file intentionally does NOT include fd_stem.c — it's a
   standalone header for compile-time footprint calculation only.
*/

#ifndef HEADER_fd_src_tickoni_c_abi_shim_tk_stem_h
#define HEADER_fd_src_tickoni_c_abi_shim_tk_stem_h

#include "../../../util/fd_util.h"
#include "../../../disco/stem/fd_stem.h"

/* Per-tile context placed in workspace at tile->tile_obj_id.
   Populated by Zig callbacks via tk_stem_register_ctx() during
   privileged_init.  The fd_stem run loop reads function pointers
   from this struct and dispatches into Zig. */
typedef struct tk_stem_ctx {
    void *                      zig_state;
    int   (*should_shutdown)(void *zig_state);
    void  (*before_credit)(void *zig_state, fd_stem_context_t *stem, int *charge_busy);
    void  (*during_frag)(void *zig_state, uint idx, ulong seq, uint sig, ulong chunk, uint sz, uint ctl);
    void  (*after_credit)(void *zig_state, fd_stem_context_t *stem, int *poll_in, int *charge_busy);
    void  (*metrics_write)(void *zig_state);
} tk_stem_ctx_t;

#endif /* HEADER_fd_src_tickoni_c_abi_shim_tk_stem_h */
