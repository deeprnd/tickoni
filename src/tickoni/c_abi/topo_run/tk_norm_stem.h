/* Shared extern declaration for TK_NORM_RUN — the Firedancer-based
   tknorm fd_topo_run_tile_t.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.

   The full definition lives in tk_normalize_stem.c.
*/
#ifndef __TK_NORM_STEM_H__
#define __TK_NORM_STEM_H__

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_normalize_stem.c. */
extern fd_topo_run_tile_t TK_NORM_RUN;

/* Wrapper that returns the address of TK_NORM_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t const * tk_get_norm_run_tile( void );

/* Query the scratch footprint for the norm tile without needing a
   fd_topo_tile_t pointer. */
extern ulong tknorm_tile_scratch_footprint( void );

/* Query the alignment of the norm tile's scratch object without needing the
   fd_topo_run_tile_t definition.  Calls through TK_NORM_RUN.scratch_align, so
   the topology builder and the tile cannot disagree: tk_normalize_stem.c
   derives the value from alignof(tknorm_ctx_t) and owns it alone. */
extern ulong tknorm_tile_scratch_align( void );

/* Field accessors for standalone test — avoids Zig-C struct layout mismatch. */
extern char const * tk_get_norm_run_name( void );
extern void * tk_get_norm_run_run( void );
extern void * tk_get_norm_run_scratch_align( void );
extern void * tk_get_norm_run_scratch_footprint( void );
extern void * tk_get_norm_run_privileged_init( void );
extern void * tk_get_norm_run_unprivileged_init( void );

/* Set event_count from topo_build.build() — called before any footprint queries. */
extern void tknorm_set_event_count( ulong event_count );

#endif /* __TK_NORM_STEM_H__ */
