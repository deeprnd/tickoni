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
  fd_log_private_stack_discover( FD_TILE_PRIVATE_STACK_SZ,
                                 &fd_tile_private_stack0, &fd_tile_private_stack1 );
  FD_LOG_INFO(( "booting tile %s pid:%lu tid:%lu", thread_name, fd_log_group_id(), tid ));

  char wallclock[ FD_LOG_WALLCLOCK_CSTR_BUF_SZ ];
  fd_log_wallclock_cstr( 0L, wallclock );
}

void
tk_topo_platform_pre_boot( fd_topo_tile_t const * tile,
                           ulong *                pid,
                           ulong *                tid ) {
  char thread_name[ 20 ];
  FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile->name, tile->kind_id ) );
  if( FD_UNLIKELY( prctl( PR_SET_NAME, thread_name, 0, 0, 0 ) ) )
    FD_LOG_ERR(( "prctl(PR_SET_NAME) failed (%i-%s)", errno, fd_io_strerror( errno ) ));

  *pid = (ulong)tk_sandbox_getpid();
  *tid = (ulong)tk_sandbox_gettid();
  initialize_logging( tile->name, tile->kind_id, *tid );
}

void
tk_topo_platform_join_tile_workspaces( fd_topo_t *      topo,
                                       fd_topo_tile_t * tile,
                                       int              core_dump_level ) {
  /* Skip hugetlbfs join: the supervisor already injected normal-page wksp
     pointers via topoWkspSetPtr.  The upstream fd_topo_join_tile_workspaces
     overwrites wksp->wksp with hugetlbfs joins that fail on normal-page
     regions, NULLing out the pointer and corrupting the topology. */
  fd_topo_t * t = topo;
  fd_topo_tile_t * tl = tile;
  ulong metrics_wksp_id = t->objs[ tl->metrics_obj_id ].wksp_id;
  for( ulong i = 0UL; i < t->wksp_cnt; i++ ) {
    if( i == metrics_wksp_id ) continue;
    int needs_wksp = -1;
    for( ulong j = 0UL; j < tl->uses_obj_cnt; j++ ) {
      if( FD_UNLIKELY( t->objs[ tl->uses_obj_id[ j ] ].wksp_id == i ) ) {
        int mode = tl->uses_obj_mode[ j ];
        if( mode > needs_wksp ) needs_wksp = mode;
      }
    }
    if( FD_LIKELY( -1 != needs_wksp ) ) {
      /* Skip if already joined (supervisor injected normal-page wksp). */
      if( t->workspaces[ i ].wksp ) continue;
      int dump = core_dump_level >= t->workspaces[ i ].core_dump_level ? 1 : 0;
      fd_topo_join_workspace( t, &t->workspaces[ i ], needs_wksp, dump );
    }
  }
}
