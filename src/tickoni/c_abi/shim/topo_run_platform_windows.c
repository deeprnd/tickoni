/* V1.14.S8.T4: platform-specific shim for joining tile workspaces on
   Windows. */

/* Only compiled when FD_HAS_WINDOWS is defined. */
#if FD_HAS_WINDOWS

#include "topo_run_platform.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/fd_util.h"

#include <windows.h>

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid ) {
  *pid = (ulong)GetCurrentProcessId();
  *tid = (ulong)GetCurrentThreadId();
  char thread_name[ 20 ];
  int n = snprintf( thread_name, sizeof( thread_name ), "%s:%lu", tile->name, tile->kind_id );
  if( n < 0 || n >= (int)sizeof( thread_name ) ) thread_name[ sizeof( thread_name ) - 1 ] = 0;
  fd_log_thread_set( thread_name );
}

void
tk_topo_platform_join_tile_workspaces( fd_topo_t *      topo,
                                       fd_topo_tile_t * tile,
                                       int              core_dump_level ) {
  /* Windows shim is a no-op — Windows doesn't use Firedancer shmem
     workspaces in the same way as Unix. */
  (void)topo;
  (void)tile;
  (void)core_dump_level;
}

#endif /* FD_HAS_WINDOWS */
