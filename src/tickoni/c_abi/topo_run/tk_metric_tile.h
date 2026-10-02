/* Shared extern declaration for TK_METRIC_RUN — the Firedancer-based
   metric-tile fd_topo_run_tile_t used by tkmetr.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.  Consolidating into a
   single header prevents two independent extern declarations and
   makes the FFI boundary explicit.  See v2.23-m task 0.
*/
#ifndef __TK_METRIC_TILE_H__
#define __TK_METRIC_TILE_H__

#include "../../../disco/topo/fd_topo.h"

/* Extern declaration — full definition lives in tk_metric_tile.c. */
extern fd_topo_run_tile_t TK_METRIC_RUN;

/* Wrapper that returns the address of TK_METRIC_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t * tk_get_metric_run_tile( void );

/* Query the scratch footprint for the metric tile without needing a
   fd_topo_tile_t pointer.  Calls through TK_METRIC_RUN.scratch_footprint.

   This keeps topob.c from depending on the full fd_topo_run_tile_t
   definition — it only sees the extern declaration and this thin
   accessor.  See v2.23-m task 4. */
extern ulong tk_metric_scratch_footprint( void );

/* Topology helper: find the object ID of the first object of type
   `obj_type` that belongs to the given tile (i.e. is listed in the
   tile's uses_obj_id[]).  Returns ULONG_MAX if not found.

   Used by tk_metric_run to find the CNC object for shutdown checking
   without resorting to a raw strcmp scan in the run path.
   See v2.23-m task 3. */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id,
                                    char const * obj_type );

#endif /* __TK_METRIC_TILE_H__ */
