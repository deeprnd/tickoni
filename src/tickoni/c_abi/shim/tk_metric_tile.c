/* tk_metric_tile.c — Tickoni's metric tile (tkmetr) implementation.
 *
 * Reuses Firedancer's fd_stem-based run loop (stem_run) with
 * fd_http_server for Prometheus /metrics endpoint.
 *
 * Linux and macOS: depends on symbols from fd_metric_tile.c (scratch_align,
 * scratch_footprint, privileged_init, unprivileged_init, stem_run,
 * populate_allowed_seccomp, populate_allowed_fds).
 *
 * Design notes:
 *   • We #include disco/metrics/fd_metric_tile.h (header-only declarations)
 *     rather than the .c source file.  The .c file defines all the static
 *     helpers and the fd_topo_run_tile_t (fd_tile_metric) that Firedancer
 *     uses.
 *   • tk_metric_privileged_init / tk_metric_unprivileged_init invoke the
 *     now-exported privileged_init / unprivileged_init from
 *     fd_metric_tile.c (v2.23-m task 2), so we don't duplicate init logic.
 *   • stem_run is exported from fd_stem.c via STEM_EXPORT (v2.23-m task 2),
 *     so tk_metric_run delegates to stem_run instead of maintaining a
 *     custom polling loop.  stem_run internally calls our before_credit
 *     callback for HTTP polling.
 *   • The metric tile is an observer — it has zero mcache/dcache links
 *     and zero fseq objects, so its .in_cnt is 0 and it never produces
 *     output to the pipeline.  stem_run handles in_cnt==0 correctly by
 *     skipping input/output polling and only running before_credit.
 *   • Shutdown: before calling stem_run, we find the CNC object, join it,
 *     and set ctx->cnc.  fd_metric_tile.c's STEM_CALLBACK_SHOULD_SHUTDOWN
 *     (defined in fd_metric_tile.c) checks ctx->cnc for HALT every
 *     iteration of stem_run.  When HALT arrives, STEM_CALLBACK_SHOULD_SHUTDOWN
 *     returns non-zero, stem_run sets tile->allow_shutdown=1 and exits.
 *   • CNC lookup uses tk_topo_find_tile_obj() (v2.23-m task 3) instead of
 *     a raw strcmp scan.  Scratch footprint uses tk_metric_scratch_footprint()
 *     (v2.23-m task 4) so topob.c never needs the full fd_topo_run_tile_t.
 */

#if FD_HAS_LINUX || FD_HAS_MACOS

#define _GNU_SOURCE

#include "disco/metrics/fd_metric_tile.h"
#include "../topo_run/tk_metric_tile.h"

/* This macro mirrors the value defined in fd_metric_tile.c so that
   tk_metric_tile.c can reference it without including the .c source. */
#ifndef FD_HTTP_SERVER_METRICS_MAX_CONNS
#define FD_HTTP_SERVER_METRICS_MAX_CONNS 128
#endif

/* ---------------------------------------------------------------------
   tk_metric_scratch_footprint — thin wrapper that calls through
   TK_METRIC_RUN.scratch_footprint.  Provides a no-argument accessor
   so topob.c never needs the full fd_topo_run_tile_t definition.
   See v2.23-m task 4.
   --------------------------------------------------------------------- */

/* Internal footprint helper used by the struct initializer.  Takes
   a fd_topo_tile_t pointer as required by the callback signature. */
static ulong
tk_metric_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
  return scratch_footprint( tile );
}

/* No-argument wrapper — delegates to TK_METRIC_RUN.scratch_footprint
   with a NULL tile, which is sufficient since scratch_footprint in
   fd_metric_tile.c only reads tile->uses_obj_cnt. */
ulong
tk_metric_scratch_footprint( void ) {
  return TK_METRIC_RUN.scratch_footprint( NULL );
}

static ulong
tk_metric_scratch_align( void ) {
  return scratch_align();
}

/* ---------------------------------------------------------------------
   tk_metric_privileged_init — allocates scratch + HTTP server.
   Mirrors fd_metric_tile.c's privileged_init.
   --------------------------------------------------------------------- */

static void
tk_metric_privileged_init( fd_topo_t const *      topo,
                           fd_topo_tile_t const * tile ) {
  privileged_init( topo, tile );
}

/* ---------------------------------------------------------------------
   tk_metric_unprivileged_init — sets ctx fields and logs startup.
   Mirrors fd_metric_tile.c's unprivileged_init.
   --------------------------------------------------------------------- */

static void
tk_metric_unprivileged_init( fd_topo_t const *      topo,
                             fd_topo_tile_t const * tile ) {
  unprivileged_init( topo, tile );
}

/* ---------------------------------------------------------------------
   tk_metric_run — calls stem_run directly.

   The metric tile is an observer — it has zero mcache/dcache links
   and zero fseq objects, so its .in_cnt is 0 and it never produces
   output to the pipeline.  stem_run handles in_cnt==0 correctly by
   skipping input/output polling and only running before_credit.

   We set ctx->cnc before calling stem_run so stem_run's
   STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT from the supervisor.  This
   is the critical fix: without it, stem_run loops forever because
   ctx->cnc is NULL and the shutdown callback always returns 0.
   --------------------------------------------------------------------- */

static void
tk_metric_run( fd_topo_t *      topo,
               fd_topo_tile_t * tile ) {
  /* ctx is the first object allocated from scratch (after privileged_init
     and unprivileged_init).  We set ctx->cnc here so stem_run's
     STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT from the supervisor. */
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  fd_metric_ctx_t * ctx = (fd_metric_ctx_t *)scratch;

  /* Find the CNC object for this tile and set ctx->cnc so
     STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT. */
  ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
  if( cnc_obj_id != ULONG_MAX ) {
    void * cnc_laddr = fd_topo_obj_laddr( topo, cnc_obj_id );
    ctx->cnc = cnc_laddr;
  }

  stem_run( topo, tile );
}

/* ---------------------------------------------------------------------
   tk_get_metric_run_tile — thin wrapper that returns &TK_METRIC_RUN.
   Provides a named accessor so callers never need to know the symbol
   name.  Declared in tk_metric_tile.h to keep topob.c and tile_run.c
   from maintaining duplicate extern declarations.
   See v2.23-m task 0.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t *
tk_get_metric_run_tile( void ) {
  return &TK_METRIC_RUN;
}

/* ---------------------------------------------------------------------
   TK_METRIC_RUN — the fd_topo_run_tile_t that Tickoni dispatches.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t TK_METRIC_RUN = {
  .name                     = "metric",
  .keep_host_networking     = 0,
  .allow_connect            = 0,
  .allow_renameat           = 0,
  .rlimit_file_cnt          = FD_HTTP_SERVER_METRICS_MAX_CONNS+5UL,
  .rlimit_address_space     = 0,
  .rlimit_data              = 0,
  .rlimit_nproc             = 0,
  .for_tpool                = 0,
  .max_event_sz             = NULL,
  .populate_allowed_seccomp = populate_allowed_seccomp,
  .populate_allowed_fds     = populate_allowed_fds,
  .scratch_align            = tk_metric_scratch_align,
  .scratch_footprint        = tk_metric_scratch_footprint_tile,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_metric_privileged_init,
  .unprivileged_init        = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_metric_unprivileged_init,
  .run                      = tk_metric_run,
  .rlimit_file_cnt_fn       = NULL,
};

#endif /* FD_HAS_LINUX || FD_HAS_MACOS */
