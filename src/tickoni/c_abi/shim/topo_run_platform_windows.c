/* Windows platform-specific tile launcher operations.
   This file is only compiled on Windows. */

#include "topo_run_platform.h"

#include "../../../disco/events/fd_event_report.h"
#include "../../../util/tile/fd_tile_private.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/fd_util.h"

extern int tk_sandbox_getpid( void );
extern int tk_sandbox_gettid( void );

static void
initialize_logging( char const * tile_name,
                    ulong        tile_kind_id,
                    ulong        tid ) {
  fd_log_cpu_set( NULL );
  fd_log_private_tid_set( tid );
  char thread_name[ 20 ];
  FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile_name, tile_kind_id ) );
  fd_log_thread_set( thread_name );
  /* Win32 owns the default thread stack; stack diagnostics remain disabled
     for this launcher path. */
  FD_LOG_INFO(( "booting tile %s pid:%lu tid:%lu", thread_name, fd_log_group_id(), tid ));

  char wallclock[ FD_LOG_WALLCLOCK_CSTR_BUF_SZ ];
  fd_log_wallclock_cstr( 0L, wallclock );
}

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid ) {
  *pid = (ulong)tk_sandbox_getpid();
  *tid = (ulong)tk_sandbox_gettid();
  initialize_logging( tile->name, tile->kind_id, *tid );
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
