#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif
#include "topo_run_platform.h"

#include "../../../disco/events/fd_event_report.h"
#include "../../../util/tile/fd_tile_private.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/fd_util.h"

#include <errno.h>
#include <sys/prctl.h>
#include <unistd.h>

/* Platform-specific hooks for shared initialize_logging. */
#define TK_PRE_BOOT_THREAD_NAME() \
  do { \
    char thread_name[ 20 ]; \
    FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile->name, tile->kind_id ) ); \
    if( FD_UNLIKELY( prctl( PR_SET_NAME, thread_name, 0, 0, 0 ) ) ) \
      FD_LOG_ERR(( "prctl(PR_SET_NAME) failed (%i-%s)", errno, fd_io_strerror( errno ) )); \
  } while(0)

#define TK_STACK_DIAGNOSTICS \
  fd_log_private_stack_discover( FD_TILE_PRIVATE_STACK_SZ, \
                                 &fd_tile_private_stack0, &fd_tile_private_stack1 )

#include "topo_run_platform_common.h"

extern int tk_sandbox_getpid( void );
extern int tk_sandbox_gettid( void );

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid ) {
  TK_PRE_BOOT_THREAD_NAME();

  *pid = (ulong)tk_sandbox_getpid();
  *tid = (ulong)tk_sandbox_gettid();
  tk_initialize_logging( tile->name, tile->kind_id, *tid );
}

void
tk_topo_platform_join_tile_workspaces( fd_topo_t *      topo,
                                       fd_topo_tile_t * tile,
                                       int              core_dump_level ) {
  fd_topo_join_tile_workspaces( topo, tile, core_dump_level );
}
