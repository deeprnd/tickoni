/* V1.14.S8.T4: builds Tickoni's fd_topo_run_tile_t and exposes the
   simplified per-process entry point tile_process.zig calls.

   Linux process mode must stay on upstream fd_topo_run_tile(); only
   non-Linux targets fall back to Tickoni's tk_topo_run_tile() shim.

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

/* fd_topo_run_tile_t's callbacks have a fixed C signature
   (fd_topo_t*, fd_topo_tile_t*) with no room for Zig closure state.
   Resolved the way Firedancer's own fdctl_tile_run pattern resolves it:
   these symbols are Zig `export fn`s taking (*anyopaque, *anyopaque) —
   never Firedancer types by name, satisfying tile_process.zig's "no
   Firedancer types" rule — that read a single per-process global Zig
   variable set once before tk_topo_run_tile_simple is called. Safe
   because Tickoni runs exactly one tile per process. */
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

static int const TK_PROCESS_MODE_SANDBOX_NONE = 0;
static int const TK_KEEP_CONTROLLING_TERMINAL = 1;

/* Phase 3 retail policy: process mode remains explicit sandbox=none on macOS
   and every other non-Linux target. This matches the product rule that the
   consumer tier must not depend on sudo, capabilities, or namespaces. */
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
  .unprivileged_init        = NULL, /* nothing to do here yet; mcache/dcache/fseq/metrics
                                        auto-joined by fd_topo_fill_tile before this point,
                                        cnc already joined in privileged_init */
  .run                      = (void (*)( fd_topo_t *, fd_topo_tile_t * ))tk_tile_run,
  .rlimit_file_cnt_fn       = NULL,
};

/* Simplified entry point for Tickoni's one-tile-per-process model:
   explicit sandbox=none, keep_controlling_terminal=1, regular core dumps,
   current process's real uid/gid on hosted Unix, no extra allowed fd.
   Linux must dispatch directly to upstream fd_topo_run_tile() so process mode stays on
   Firedancer's canonical runtime path; non-Linux targets fall back to
   tk_topo_run_tile(), which mirrors the same launch order where upstream's
   Linux-only implementation is unavailable. */
int
 tk_topo_run_tile_simple_uses_upstream( void ) {
#if FD_HAS_LINUX
  return 1;
#else
  return 0;
#endif
}

void
tk_topo_run_tile_simple( void * topo, void * tile ) {
#if FD_HAS_LINUX
  fd_topo_run_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    (uint)getuid(), (uint)getgid(), /* allow_fd */ -1,
                    &TK_TILE_RUN );
#elif FD_HAS_MACOS
  tk_topo_run_tile( topo, tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    (uint)getuid(), (uint)getgid(), /* allow_fd */ -1,
                    &TK_TILE_RUN );
#else
  tk_topo_run_tile( topo, tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    0U, 0U, /* allow_fd */ -1,
                    &TK_TILE_RUN );
#endif
}
