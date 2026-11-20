/* Shared C/FFI declarations for the tkdiag diagnostics fd_stem specialization.
   tkdiag takes one unreliable diagnostic input link from each pipeline tile and
   has no output link; the tile object and context stay private to
   tk_diag_stem.c, and the observable outputs are the tile's CNC app slots 0 to
   4, read by the supervisor through tile_registry.zig, and the `tkdiag` metrics
   kind plus the per-tile OS metrics it writes, served by the metric tile.  The
   fragment format, aggregation and liveness rules are in
   shim/tk_diag_fragment.h.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology builder)
   reference these symbols. */
#ifndef __TK_DIAG_STEM_H__
#define __TK_DIAG_STEM_H__

#include "../../../disco/topo/fd_topo.h"

extern fd_topo_run_tile_t TK_DIAG_RUN;

extern fd_topo_run_tile_t const * tk_get_diag_run_tile( void );
extern char const * tk_get_diag_run_name( void );
extern void * tk_get_diag_run_run( void );
extern void * tk_get_diag_run_scratch_align( void );
extern void * tk_get_diag_run_scratch_footprint( void );
extern void * tk_get_diag_run_privileged_init( void );
extern void * tk_get_diag_run_unprivileged_init( void );

/* Scratch layout of the tile object, read back through the wired
   fd_topo_run_tile_t fields so topob.c never restates it. */
extern ulong tkdiag_tile_scratch_align( void );
extern ulong tkdiag_tile_scratch_footprint( void );

#endif /* __TK_DIAG_STEM_H__ */
