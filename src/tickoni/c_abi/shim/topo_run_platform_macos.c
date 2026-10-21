#if FD_HAS_MACOS
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include "topo_run_platform.h"

#include "../../../disco/events/fd_event_report.h"
#include "../../../util/tile/fd_tile_private.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/fd_util.h"

#include <pthread.h>
#include <unistd.h>

/* Platform-specific hooks for shared initialize_logging. */
#define TK_PRE_BOOT_THREAD_NAME() \
  do { \
    char thread_name[ 20 ]; \
    FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile->name, tile->kind_id ) ); \
    (void)pthread_setname_np( thread_name ); \
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
  (void)core_dump_level;

  char workspace_name[ 272 ];
  for( ulong i = 0UL; i < topo->wksp_cnt; i++ ) {
    fd_topo_wksp_t * wksp = &topo->workspaces[ i ];
    if( FD_LIKELY( wksp->wksp ) ) continue;
    if( FD_UNLIKELY( !fd_cstr_printf_check( workspace_name, sizeof( workspace_name ), NULL,
                                            "%s_%s.wksp", topo->app_name, wksp->name ) ) )
      FD_LOG_ERR(( "workspace name too long for %s:%s", topo->app_name, wksp->name ));
    wksp->wksp = fd_wksp_attach( workspace_name );
    if( FD_UNLIKELY( !wksp->wksp ) )
      FD_LOG_ERR(( "fd_wksp_attach failed for workspace %s", workspace_name ));
  }

  (void)tile;
}

#endif /* FD_HAS_MACOS */
