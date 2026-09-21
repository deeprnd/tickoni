/* V1.14.S8.T4: platform-specific shim for joining tile workspaces on
   macOS. */

/* Only compiled when FD_HAS_MACOS is defined. */
#if FD_HAS_MACOS

#define _GNU_SOURCE
#include "topo_run_platform.h"

#include "../../../util/tile/fd_tile_private.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/fd_util.h"

#include <errno.h>
#include <unistd.h>

extern int tk_sandbox_getpid( void );
extern int tk_sandbox_gettid( void );

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid ) {
  char thread_name[ 20 ];
  FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile->name, tile->kind_id ) );
  *pid = (ulong)tk_sandbox_getpid();
  *tid = (ulong)tk_sandbox_gettid();
  fd_log_cpu_set( NULL );
  fd_log_private_tid_set( *tid );
  fd_log_thread_set( thread_name );
  fd_log_private_stack_discover( FD_TILE_PRIVATE_STACK_SZ,
                                 &fd_tile_private_stack0, &fd_tile_private_stack1 );
  FD_LOG_INFO(( "booting tile %s pid:%lu tid:%lu", thread_name, fd_log_group_id(), *tid ));
}

void
tk_topo_platform_join_tile_workspaces( fd_topo_t *      topo,
                                       fd_topo_tile_t * tile,
                                       int              core_dump_level ) {
  (void)core_dump_level;

  /* Join normal-page workspaces using fd_shmem_join+fd_wksp_join (regular
     shmem) instead of fd_topo_join_workspace (hugetlbfs join) which fails
     on normal-page regions.  Skip workspaces already joined by the
     supervisor via topoWkspSetPtr (main wksp and metrics wksp). */
  fd_topo_t * t = topo;
  fd_topo_tile_t * tl = tile;
  ulong metrics_wksp_id = t->objs[ tl->metrics_obj_id ].wksp_id;

  for( ulong i = 0UL; i < t->wksp_cnt; i++ ) {
    /* Skip if already joined (supervisor injected normal-page wksp). */
    if( FD_LIKELY( t->workspaces[ i ].wksp ) ) continue;
    /* Skip metrics workspace — tile process joined it separately. */
    if( i == metrics_wksp_id ) continue;

    /* Check if this tile needs this workspace. */
    int needs_wksp = -1;
    for( ulong j = 0UL; j < tl->uses_obj_cnt; j++ ) {
      if( FD_UNLIKELY( t->objs[ tl->uses_obj_id[ j ] ].wksp_id == i ) ) {
        int mode = tl->uses_obj_mode[ j ];
        if( mode > needs_wksp ) needs_wksp = mode;
      }
    }
    if( FD_LIKELY( -1 != needs_wksp ) ) {
      char workspace_name[ 272 ];
      if( FD_UNLIKELY( !fd_cstr_printf_check( workspace_name, sizeof( workspace_name ), NULL,
                                              "%s_%s.wksp", t->app_name, t->workspaces[ i ].name ) ) )
        FD_LOG_ERR(( "workspace name too long for %s:%s", t->app_name, t->workspaces[ i ].name ));

      int join_mode = needs_wksp == 2 ? FD_SHMEM_JOIN_MODE_READ_WRITE : FD_SHMEM_JOIN_MODE_READ_ONLY;
      void * shmem = fd_shmem_join( workspace_name, join_mode, 0, NULL, NULL, NULL );
      if( FD_UNLIKELY( !shmem ) )
        FD_LOG_ERR(( "fd_shmem_join failed for workspace %s", workspace_name ));
      void * wksp = fd_wksp_join( shmem );
      if( FD_UNLIKELY( !wksp ) )
        FD_LOG_ERR(( "fd_wksp_join failed for workspace %s", workspace_name ));
      t->workspaces[ i ].wksp = wksp;
    }
  }
}

#endif /* FD_HAS_MACOS */
