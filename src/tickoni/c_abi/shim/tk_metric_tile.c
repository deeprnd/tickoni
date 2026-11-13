/* tk_metric_tile.c — Tickoni's metric tile implementation.
 *
 * Reuses Firedancer's fd_metric_tile implementation and fd_http_server
 * for the Prometheus /metrics endpoint.
 *
 * Linux-only: depends on symbols from fd_metric_tile.c (scratch_align,
 * scratch_footprint, privileged_init, unprivileged_init, fd_tile_metric,
 * populate_allowed_seccomp, populate_allowed_fds).
 *
 * Design notes:
 *   • We #include disco/metrics/fd_metric_tile.h (header-only declarations)
 *     rather than the .c source file.
 *   • tk_metric_privileged_init / tk_metric_unprivileged_init invoke the
 *     exported Firedancer initialization callbacks.
 *   • tk_metric_run delegates through fd_tile_metric.run so the metric tile
 *     always uses the stem specialization generated with fd_metric_ctx_t and
 *     the metric callbacks.
 *   • The metric tile is an observer — it has zero mcache/dcache links
 *     and zero fseq objects, so its .in_cnt is 0 and it never produces
 *     output to the pipeline.
 *   • Shutdown: before entering the run loop, we find the CNC object and set
 *     ctx->cnc. fd_metric_tile.c's STEM_CALLBACK_SHOULD_SHUTDOWN checks it
 *     for HALT on each stem iteration.
 *   • CNC lookup uses tk_topo_find_tile_obj() (v2.23-m task 3) instead of
 *     a raw strcmp scan. Scratch footprint uses tk_metric_scratch_footprint()
 *     (v2.23-m task 4) so topob.c never needs the full fd_topo_run_tile_t.
 */

#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS

#define _GNU_SOURCE

#include "disco/metrics/fd_metric_tile.h"
#include "../topo_run/tk_metric_tile.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "audit_schema.h"

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
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_footprint_tile ENTER" ));
  ulong result = scratch_footprint( tile );
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_footprint_tile EXIT %lu", result ));
  return result;
}

/* No-argument wrapper — delegates to TK_METRIC_RUN.scratch_footprint
   with a NULL tile, which is sufficient since scratch_footprint in
   fd_metric_tile.c only reads tile->uses_obj_cnt. */
ulong
tk_metric_scratch_footprint( void ) {
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_footprint ENTER" ));
  ulong result = TK_METRIC_RUN.scratch_footprint( NULL );
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_footprint EXIT %lu", result ));
  return result;
}

static ulong
tk_metric_scratch_align( void ) {
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_align ENTER" ));
  ulong result = scratch_align();
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_scratch_align EXIT %lu", result ));
  return result;
}

/* ---------------------------------------------------------------------
   tk_metric_privileged_init — allocates scratch + HTTP server.
   Mirrors fd_metric_tile.c's privileged_init.
   --------------------------------------------------------------------- */

static void
tk_metric_privileged_init( fd_topo_t const *      topo,
                           fd_topo_tile_t const * tile ) {
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_privileged_init ENTER tile_id=%lu", tile->id ));
  privileged_init( topo, tile );
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_privileged_init EXIT tile_id=%lu", tile->id ));
}

/* ---------------------------------------------------------------------
   tk_metric_unprivileged_init — sets ctx fields and logs startup.
   Mirrors fd_metric_tile.c's unprivileged_init.
   --------------------------------------------------------------------- */

static void
tk_metric_unprivileged_init( fd_topo_t const *      topo,
                             fd_topo_tile_t const * tile ) {
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_unprivileged_init ENTER tile_id=%lu tile_obj_id=%lu", tile->id, tile->tile_obj_id ));
  unprivileged_init( topo, tile );
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_unprivileged_init after unprivileged_init tile_id=%lu", tile->id ));

  /* Write boot_ts to CNC app-region immediately so the supervisor can
     read it without timing issues. Index 2 = metric_boot_timestamp
     (indices 0,1 are metric_snapshots and metric_backpressure_waits). */
  void * scratch = (void *)fd_topo_obj_laddr( topo, tile->tile_obj_id );
  fd_metric_ctx_t * ctx = (fd_metric_ctx_t *)scratch;
  ulong cnc_obj_id = tk_topo_find_tile_obj( (fd_topo_t *)topo, tile->id, "cnc" );
  if( cnc_obj_id != ULONG_MAX ) {
    void * cnc_laddr = fd_topo_obj_laddr( (fd_topo_t *)topo, cnc_obj_id );
    ctx->cnc = cnc_laddr;
    ((ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc_laddr))[2] = (ulong)ctx->boot_ts;
    ((ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc_laddr))[3] = 0xCAFEBABE;
  }
}

/* ---------------------------------------------------------------------
   tk_metric_run — calls the metric tile's own stem specialization.

   The metric tile is an observer — it has zero mcache/dcache links
   and zero fseq objects, so its .in_cnt is 0 and it never produces
   output to the pipeline.

   We set ctx->cnc before entering the run loop so its
   STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT from the supervisor.
   --------------------------------------------------------------------- */

static void
tk_metric_run( fd_topo_t *      topo,
               fd_topo_tile_t * tile ) {
  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_run ENTER tile_id=%lu tile_obj_id=%lu", tile->id, tile->tile_obj_id ));

  /* ctx is the first object allocated from scratch. We set ctx->cnc before
     entering the metric stem so its shutdown callback can detect HALT. */
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  fd_metric_ctx_t * ctx = (fd_metric_ctx_t *)scratch;

  /* DIAG: log that we reached tk_metric_run */
  FD_LOG_NOTICE(( "tk_metric_run: entering, tile_id=%lu tile_obj_id=%lu boot_ts=%lld",
                  tile->id, tile->tile_obj_id, (long long)ctx->boot_ts ));

  /* Find the CNC object for this tile and set ctx->cnc so
     STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT. */
  ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
  if( cnc_obj_id != ULONG_MAX ) {
    void * cnc_laddr = fd_topo_obj_laddr( topo, cnc_obj_id );
    ctx->cnc = cnc_laddr;

    /* Write boot_ts to the CNC app-region so the supervisor can read it
       across the process boundary without needing to inspect scratch.
       Index 2 is reserved for metric_boot_timestamp (indices 0,1 are
       metric_snapshots and metric_backpressure_waits per tile_registry).
       This is the diagnostic hook for "boot_timestamp is a valid large
       positive value" — if the supervisor reads 0, unprivileged_init
       never ran (tile crashed in privileged_init), and HTTP never
       started. If the supervisor reads a valid timestamp but HTTP fails,
       the problem is isolated to the HTTP subsystem. */
    ulong app_laddr = (ulong)fd_cnc_app_laddr((fd_cnc_t *)cnc_laddr);
    FD_LOG_NOTICE(( "tk_metric_run: writing boot_ts=%lld to cnc_app_laddr=%lu obj_id=%lu",
                    (long long)ctx->boot_ts, app_laddr, cnc_obj_id ));
    ((ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc_laddr))[2] = (ulong)ctx->boot_ts;
    /* Verify write */
    ulong verify = ((ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc_laddr))[2];
    FD_LOG_NOTICE(( "tk_metric_run: verify write boot_ts=%lu", (ulong)verify ));
  } else {
    FD_LOG_NOTICE(( "tk_metric_run: cnc not found for tile, cnc_obj_id=ULONG_MAX" ));
  }

  /* Use the metric tile's own stem specialization.  Its run callback is
     generated in fd_metric_tile.c with metric context and callbacks; calling
     another tile's stem specialization would reinterpret scratch and exit
     under the wrong lifecycle rules. */
  fd_tile_metric.run( topo, tile );

  /* Signal to Firedancer dispatch (fd_topo_run_tile / tk_topo_run_tile)
     that the tile exited cleanly. The dispatch resets allow_shutdown=0
     before calling run(), then checks it after — crash if still 0. */
  tile->allow_shutdown = 1;

  FD_LOG_NOTICE(( "tk_metric_tile: tk_metric_run EXIT tile_id=%lu", tile->id ));
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
  .name                     = TILE_ID_METRIC,
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

#endif /* FD_HAS_LINUX */
