/* V1.14.S8.T4: builds Tickoni's fd_topo_run_tile_t and exposes the
   simplified per-process entry point tile_process.zig calls.

   Deliberately a separate file from topo_run.c: this file's static
   TK_TILE_RUN struct references tk_tile_privileged_init/tk_tile_run,
   which are Zig `export fn`s defined only in
   src/tickoni/runtime/tile_process.zig. Any consumer that links this
   file must also link tile_process.zig's object code — true for the
   supervisor exe and the process-mode integration tests, but not for
   topo_run.c/topob.c's own standalone adapter unit tests, which is why
   this stays out of topo_run.c itself. */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"

#if FD_HAS_LINUX || FD_HAS_MACOS
#include <unistd.h>
#endif

/* Include platform header for tk_topo_platform_* functions */
#include "topo_run_platform.h"

/* Extern declarations for Zig exports */
extern void tk_tile_privileged_init( void * topo, void * tile );
extern void tk_tile_run( void * topo, void * tile );
extern void tk_topo_run_tile( void * topo,
                              void * tile,
                              int    sandbox,
                              int    keep_controlling_terminal,
                              int    core_dump_level,
                              uint   uid,
                              uint   gid,
                              int    allow_fd,
                              void * tile_run );

/* tk_stem_run: Linux-only fd_stem-based run loop.  On non-Linux we fall
   back to tk_tile_run (existing per-tile loop).  See v2.22.S5 fd_stem
   migration plan. */
#if FD_HAS_LINUX
extern void tk_stem_run( fd_topo_t * top, fd_topo_tile_t * tile );
#endif

/* Phase 3 retail policy: process mode remains explicit sandbox=none on macOS
   and every other non-Linux target. This matches the product rule that the
   consumer tier must not depend on sudo, capabilities, or namespaces. */
static int const TK_PROCESS_MODE_SANDBOX_NONE = 0;
static int const TK_KEEP_CONTROLLING_TERMINAL = 1;

static fd_topo_run_tile_t TK_TILE_RUN = {
  .name                     = "tickoni",
  .keep_host_networking     = 0,
  .allow_connect            = 0,
  .allow_renameat           = 0,
  .rlimit_file_cnt          = 0,
  .rlimit_address_space     = 0,
  .rlimit_data              = 0,
  .rlimit_nproc             = 0,
  .for_tpool                = 0,
  .max_event_sz             = NULL,
  .populate_allowed_seccomp = NULL,
  .populate_allowed_fds     = NULL,
  .scratch_align            = NULL,
  .scratch_footprint        = NULL,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_tile_privileged_init,
  .unprivileged_init        = NULL,
  .run                      = (void (*)( fd_topo_t *, fd_topo_tile_t * ))
#if FD_HAS_LINUX
    tk_stem_run,
#else
    tk_tile_run,
#endif
  .rlimit_file_cnt_fn       = NULL,
};

void
tk_topo_run_tile_simple( void * topo, void * tile ) {
  /* All platforms now use tk_topo_run_tile() so the platform shim
     skip in tk_topo_platform_join_tile_workspaces() is applied.
     This prevents hugetlbfs join from overwriting wksp pointers. */
  tk_topo_run_tile( topo, tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
#if FD_HAS_LINUX || FD_HAS_MACOS
                    (uint)getuid(), (uint)getgid(),
#else
                    0U, 0U,
#endif
                    /* allow_fd */ -1,
                    &TK_TILE_RUN );
}
