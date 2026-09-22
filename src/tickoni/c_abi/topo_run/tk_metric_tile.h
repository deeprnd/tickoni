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

#endif /* __TK_METRIC_TILE_H__ */
