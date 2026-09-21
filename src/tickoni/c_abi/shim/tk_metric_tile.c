/* tk_metric_tile.c — Tickoni's metric tile (tkmetr) implementation.
 *
 * Reuses Firedancer's fd_metric_tile.c (Prometheus HTTP endpoint,
 * fd_prometheus_render_all, fd_stem-based polling loop) by including it
 * wholesale.  The included file defines stem_run and all static helpers;
 * this file exposes a fd_topo_run_tile_t (TK_METRIC_RUN) that Tickoni's
 * process-mode pipeline can dispatch.
 *
 * Design notes:
 *   • fd_tile_metric.c's privileged_init / unprivileged_init are static,
 *     so we duplicate only the init logic (scratch + HTTP + ctx setup)
 *     rather than trying to call through to static symbols.
 *   • unprivileged_init is intentionally NULL: stem_run (the .run
 *     callback) calls fd_metric_tile's unprivileged_init internally,
 *     so Tickoni's fd_topo_run_tile would double-call it and crash.
 *   • The metric tile is an observer — it has zero mcache/dcache links
 *     and zero fseq objects, so its .in_cnt is 0 and it never produces
 *     output to the pipeline.
 *   • Shutdown: stem_run checks STEM_CALLBACK_SHOULD_SHUTDOWN which is
 *     not defined, so it runs forever.  The process is killed by
 *     fd_topo_run_tile's SHUTDOWN signal path (fd_cnc_signal).
 */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"
#include "../../../disco/metrics/fd_metric_tile.c"  // defines stem_run, METRICS_PARAMS, fd_metric_ctx_t
#include "../../../disco/metrics/fd_prometheus.h"

/* ---------------------------------------------------------------------
   tk_metric_scratch_footprint — identical to fd_tile_metric's version.
   --------------------------------------------------------------------- */

static ulong
tk_metric_scratch_footprint( fd_topo_tile_t const * tile ) {
  return scratch_footprint( tile );
}

static ulong
tk_metric_scratch_align( void ) {
  return scratch_align();
}

/* ---------------------------------------------------------------------
   tk_metric_privileged_init — allocates scratch + HTTP server.
   --------------------------------------------------------------------- */

static void
tk_metric_privileged_init( fd_topo_t const *      topo,
                           fd_topo_tile_t const * tile ) {
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );

  FD_SCRATCH_ALLOC_INIT( l, scratch );

  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l,
    alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  fd_http_server_t * _metrics = FD_SCRATCH_ALLOC_APPEND( l,
    fd_http_server_align(), fd_http_server_footprint( METRICS_PARAMS ) );

  fd_http_server_callbacks_t metrics_callbacks = {
    .request = metrics_http_request,
  };
  ctx->metrics_server = fd_http_server_join(
    fd_http_server_new( _metrics, METRICS_PARAMS, metrics_callbacks, ctx )
  );
  fd_http_server_listen( ctx->metrics_server,
                         tile->metric.prometheus_listen_addr,
                         tile->metric.prometheus_listen_port );
}

/* ---------------------------------------------------------------------
   TK_METRIC_RUN — the fd_topo_run_tile_t that Tickoni dispatches.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t TK_METRIC_RUN = {
  .name                     = "tickoni-metric",
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
  .scratch_footprint        = tk_metric_scratch_footprint,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_metric_privileged_init,
  .unprivileged_init        = NULL,   /* stem_run handles it; double-init = crash */
  .run                      = (void (*)( fd_topo_t *, fd_topo_tile_t * ))stem_run,
  .rlimit_file_cnt_fn       = NULL,
};
