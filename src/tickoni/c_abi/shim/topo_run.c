/* Thin wrappers around Firedancer's per-process tile launcher workflow.
   This is the only file in Tickoni that includes fd_topo.h.

   Platform differences are delegated to build-selected shim implementations
   via topo_run_platform.h. The orchestration below stays identical across
   Linux and macOS; only the leaf operations vary. */

#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS
#if FD_HAS_LINUX || FD_HAS_MACOS
#define _GNU_SOURCE
#endif

#include "../../../util/fd_util.h"
#include "../../../disco/events/fd_event_report.h"
#include "../../../disco/metrics/fd_metrics.h"
#include "../../../disco/topo/fd_topo.h"
#include "topo_run_platform.h"

void
tk_topo_join_tile_workspaces( void * topo, void * tile, int core_dump_level ) {
  fd_topo_join_tile_workspaces( (fd_topo_t *)topo, (fd_topo_tile_t *)tile, core_dump_level );
}

void
tk_topo_fill_tile( void * topo, void * tile ) {
  fd_topo_fill_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile );
}

extern void tk_sandbox_enter( uint        desired_uid,
                              uint        desired_gid,
                              int         keep_host_networking,
                              int         allow_connect,
                              int         allow_renameat,
                              int         keep_controlling_terminal,
                              int         dumpable,
                              ulong       rlimit_file_cnt,
                              ulong       rlimit_address_space,
                              ulong       rlimit_data,
                              ulong       rlimit_nproc,
                              ulong       allowed_file_descriptor_cnt,
                              int const * allowed_file_descriptor,
                              ulong       seccomp_filter_cnt,
                              void *      seccomp_filter );
extern void tk_sandbox_switch_uid_gid( uint desired_uid, uint desired_gid );

void
tk_topo_run_tile( void * topo,
                  void * tile,
                  int    sandbox,
                  int    keep_controlling_terminal,
                  int    core_dump_level,
                  uint   uid,
                  uint   gid,
                  int    allow_fd,
                  void * tile_run ) {
  fd_topo_t *          topo_c     = (fd_topo_t *)topo;
  fd_topo_tile_t *     tile_c     = (fd_topo_tile_t *)tile;
  fd_topo_run_tile_t * tile_run_c = (fd_topo_run_tile_t *)tile_run;

  FD_LOG_DEBUG(( "tk_topo_run_tile: tile=%s:%lu sandbox=%d", tile_c->name, tile_c->kind_id, sandbox ));

  ulong pid = 0UL;
  ulong tid = 0UL;
  tk_topo_platform_pre_boot( tile_c, &pid, &tid );

  FD_LOG_DEBUG(( "tk_topo_run_tile: pre_boot pid=%lu tid=%lu", pid, tid ));

  tk_topo_platform_join_tile_workspaces( topo_c, tile_c, core_dump_level );

  if( FD_UNLIKELY( tile_run_c->privileged_init ) )
    tile_run_c->privileged_init( topo_c, tile_c );

  ulong allow_fds_offset = 0UL;
  int allow_fds[ 256 ] = { 0 };
  if( FD_LIKELY( -1!=allow_fd ) ) {
    allow_fds_offset = 1UL;
    allow_fds[ 0 ] = allow_fd;
  }
  ulong allow_fds_cnt = 0UL;
  if( FD_LIKELY( tile_run_c->populate_allowed_fds ) ) {
    allow_fds_cnt = tile_run_c->populate_allowed_fds( topo_c,
                                                      tile_c,
                                                      (sizeof(allow_fds)/sizeof(allow_fds[ 0 ]))-allow_fds_offset,
                                                      allow_fds+allow_fds_offset );
  }

#if FD_HAS_LINUX
  struct sock_filter seccomp_filter[ 256UL ];
  ulong seccomp_filter_cnt = 0UL;
  if( FD_LIKELY( tile_run_c->populate_allowed_seccomp ) ) {
    seccomp_filter_cnt = tile_run_c->populate_allowed_seccomp( topo_c,
                                                               tile_c,
                                                               sizeof(seccomp_filter)/sizeof( seccomp_filter[ 0 ] ),
                                                               seccomp_filter );
  }
#else
  struct sock_filter * seccomp_filter = NULL;
  ulong seccomp_filter_cnt = 0UL;
#endif

  ulong rlimit_file_cnt = tile_run_c->rlimit_file_cnt;
  if( tile_run_c->rlimit_file_cnt_fn ) {
    rlimit_file_cnt = tile_run_c->rlimit_file_cnt_fn( topo_c, tile_c );
  }

  if( FD_LIKELY( sandbox ) ) {
    int dumpable = core_dump_level == FD_TOPO_CORE_DUMP_LEVEL_DISABLED ? 0 : 1;
    tk_sandbox_enter( uid,
                      gid,
                      tile_run_c->keep_host_networking,
                      tile_run_c->allow_connect,
                      tile_run_c->allow_renameat,
                      keep_controlling_terminal,
                      dumpable,
                      rlimit_file_cnt,
                      tile_run_c->rlimit_address_space,
                      tile_run_c->rlimit_data,
                      tile_run_c->rlimit_nproc,
                      allow_fds_cnt+allow_fds_offset,
                      allow_fds,
                      seccomp_filter_cnt,
                      seccomp_filter );
  } else {
    tk_sandbox_switch_uid_gid( uid, gid );
  }

  fd_topo_fill_tile( topo_c, tile_c );

  FD_TEST( tile_c->metrics );
  fd_metrics_register( tile_c->metrics );
  fd_event_register( topo_c, tile_c );

  FD_MGAUGE_SET( TILE, PID, pid );
  FD_MGAUGE_SET( TILE, TID, tid );

  if( FD_UNLIKELY( tile_run_c->unprivileged_init ) )
    tile_run_c->unprivileged_init( topo_c, tile_c );

  tile_run_c->run( topo_c, tile_c );
  if( FD_UNLIKELY( !tile_c->allow_shutdown ) )
    FD_LOG_ERR(( "tile %s:%lu run loop returned", tile_c->name, tile_c->kind_id ));

  FD_LOG_DEBUG(( "tk_topo_run_tile: tile=%s:%lu completed", tile_c->name, tile_c->kind_id ));
  FD_MGAUGE_SET( TILE, STATUS, 2UL );
}
