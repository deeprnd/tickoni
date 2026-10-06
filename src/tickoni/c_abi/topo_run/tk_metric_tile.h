/* Shared extern declaration for TK_METRIC_RUN — the Firedancer-based
   metric-tile fd_topo_run_tile_t used by tkmetr.

   Both tile_run.c (process-mode dispatcher) and topob.c (topology
   builder) need to reference this symbol.  Consolidating into a
   single header prevents two independent extern declarations and
   makes the FFI boundary explicit.  See v2.23-m task 0.
*/
#ifndef HEADER_fd_src_tickoni_c_abi_topo_run_tk_metric_tile_h
#define HEADER_fd_src_tickoni_c_abi_topo_run_tk_metric_tile_h

#include "../../../disco/topo/fd_topo.h"

/* Windows currently links fd_http_server_windows_stub.c, not a real
   HTTP transport.  Remove the FD_HAS_WINDOWS exclusion when that
   transport is linked. */
#if FD_HAS_HOSTED && (FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS) && \
    !FD_HAS_WINDOWS
#define TK_HAS_METRIC_TILE 1
#else
#define TK_HAS_METRIC_TILE 0
#endif

#if TK_HAS_METRIC_TILE

/* Extern declaration — full definition lives in tk_metric_tile.c. */
extern fd_topo_run_tile_t TK_METRIC_RUN;

/* Wrapper that returns the address of TK_METRIC_RUN so callers
   never need to know the symbol name. */
extern fd_topo_run_tile_t * tk_get_metric_run_tile( void );

/* tk_metric_scratch_requirements returns the exact alignment and
   footprint required by TK_METRIC_RUN.  Keeping both queries here
   prevents Zig from reproducing the metric context or HTTP server
   layout. */
void
tk_metric_scratch_requirements( ulong * align,
                                ulong * footprint );

#endif /* TK_HAS_METRIC_TILE */

/* Topology helper: find the object ID of the first object of type
   `obj_type` that belongs to the given tile (i.e. is listed in the
   tile's uses_obj_id[]).  Returns ULONG_MAX if not found.

   Used by tk_metric_run to find the CNC object for shutdown checking
   without resorting to a raw strcmp scan in the run path.
   See v2.23-m task 3. */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id,
                                    char const * obj_type );

#endif /* HEADER_fd_src_tickoni_c_abi_topo_run_tk_metric_tile_h */
