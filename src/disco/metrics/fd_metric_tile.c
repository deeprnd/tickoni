/* fd_metric_tile.c — Firedancer's metric tile implementation for Tickoni.
 *
 * This file redefines all the STEM callbacks and includes fd_stem.c to
 * generate stem_run with a CNC-aware shutdown check.  It mirrors the
 * upstream fd_metric_tile.c layout so the Firedancer lib keeps its own
 * version (for native metric tiles) while Tickoni gets a tile that
 * actually obeys HALT signals from the supervisor.
 *
 * Key difference from upstream:
 *   - STEM_CALLBACK_SHOULD_SHUTDOWN checks ctx->cnc for HALT instead
 *     of always returning 0.
 *
 * This file is compiled by the Tickoni build system and linked into
 * libfd_disco.a alongside the Firedancer build.
 *
 * See v2.23-m task 2: "Fix the root cause of the stem_run SIGSEGV and
 * use stem directly".
 */

#include "fd_metric_tile.h"
#include "fd_metrics.h"
#include "fd_prometheus.h"
#include "../../waltz/http/fd_http_server_private.h"
#include "../../util/net/fd_ip4.h"
#include "../../tango/cnc/fd_cnc.h"

#include <sys/types.h>
#include <sys/socket.h> /* SOCK_CLOEXEC, SOCK_NONBLOCK needed for seccomp filter */
#include <unistd.h>
#include <string.h>

#include "generated/fd_metric_tile_seccomp.h"

#define FD_HTTP_SERVER_METRICS_MAX_CONNS          128
#define FD_HTTP_SERVER_METRICS_MAX_REQUEST_LEN    8192
#define FD_HTTP_SERVER_METRICS_OUTGOING_BUFFER_SZ (32UL<<20UL) /* 32MiB reserved for buffering metrics responses */

/* ---------------------------------------------------------------------
   Configuration constant
   --------------------------------------------------------------------- */

const fd_http_server_params_t METRICS_PARAMS = {
  .max_connection_cnt    = FD_HTTP_SERVER_METRICS_MAX_CONNS,
  .max_ws_connection_cnt = 0UL,
  .max_request_len       = FD_HTTP_SERVER_METRICS_MAX_REQUEST_LEN,
  .max_ws_recv_frame_len = 0UL,
  .max_ws_send_frame_cnt = 0UL,
  .outgoing_buffer_sz    = FD_HTTP_SERVER_METRICS_OUTGOING_BUFFER_SZ,
};

/* ---------------------------------------------------------------------
   Scratch helpers
   --------------------------------------------------------------------- */

FD_FN_CONST inline ulong
scratch_align( void ) {
  return 128UL;
}

FD_FN_PURE inline ulong
scratch_footprint( fd_topo_tile_t const * tile ) {
  (void)tile;

  ulong l = FD_LAYOUT_INIT;
  l = FD_LAYOUT_APPEND( l, alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );
  l = FD_LAYOUT_APPEND( l, fd_http_server_align(), fd_http_server_footprint( METRICS_PARAMS ) );
  return FD_LAYOUT_FINI( l, scratch_align() );
}

/* ---------------------------------------------------------------------
   Stem callbacks — before_credit called every iteration for HTTP polling.
   --------------------------------------------------------------------- */

void
before_credit( fd_metric_ctx_t *   ctx,
               fd_stem_context_t * stem,
               int *               charge_busy ) {
  (void)stem;
  *charge_busy = fd_http_server_poll( ctx->metrics_server, 1 ); /* 1ms */
}

/* ---------------------------------------------------------------------
   HTTP request handler
   --------------------------------------------------------------------- */

fd_http_server_response_t
metrics_http_request( fd_http_server_request_t const * request ) {
  fd_metric_ctx_t * ctx = (fd_metric_ctx_t *)request->ctx;

  if( FD_UNLIKELY( request->method!=FD_HTTP_SERVER_METHOD_GET ) ) {
    return (fd_http_server_response_t){
      .status = 400,
    };
  }

  if( FD_LIKELY( !strcmp( request->path, "/metrics" ) ) ) {
    fd_prometheus_render_all( ctx->topo, ctx->metrics_server );

    fd_http_server_response_t response = {
      .status       = 200,
      .content_type = "text/plain; version=0.0.4",
    };
    if( FD_UNLIKELY( fd_http_server_stage_body( ctx->metrics_server, &response ) ) ) {
      FD_LOG_WARNING(( "fd_http_server_stage_body failed, metrics response too long" ));
      return (fd_http_server_response_t){
        .status = 500,
      };
    }
    return response;
  } else {
    return (fd_http_server_response_t){
      .status = 404,
    };
  }
}

/* ---------------------------------------------------------------------
   metrics_write — called by stem_run's housekeeping loop.
   --------------------------------------------------------------------- */

static void
metrics_write( fd_metric_ctx_t * ctx ) {
  FD_MGAUGE_SET( METRIC, BOOT_TIMESTAMP_NANOS, (ulong)ctx->boot_ts );

  FD_MGAUGE_SET( METRIC, CONN_ACTIVE, ctx->metrics_server->metrics.connection_cnt );

  FD_MCNT_SET( METRIC, BYTES_WRITTEN, ctx->metrics_server->metrics.bytes_written );
  FD_MCNT_SET( METRIC, BYTES_READ,    ctx->metrics_server->metrics.bytes_read );
}

/* ---------------------------------------------------------------------
   privileged_init / unprivileged_init
   --------------------------------------------------------------------- */

void
privileged_init( fd_topo_t const *      topo,
                 fd_topo_tile_t const * tile ) {
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );

  FD_SCRATCH_ALLOC_INIT( l, scratch );
  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l, alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  fd_http_server_t * _metrics = FD_SCRATCH_ALLOC_APPEND( l, fd_http_server_align(), fd_http_server_footprint( METRICS_PARAMS ) );

  fd_http_server_callbacks_t metrics_callbacks = {
    .request = metrics_http_request,
  };
  ctx->metrics_server = fd_http_server_join( fd_http_server_new( _metrics, METRICS_PARAMS, metrics_callbacks, ctx ) );
  fd_http_server_listen( ctx->metrics_server, tile->metric.prometheus_listen_addr, tile->metric.prometheus_listen_port );
}

void
unprivileged_init( fd_topo_t const *      topo,
                   fd_topo_tile_t const * tile ) {
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );

  FD_SCRATCH_ALLOC_INIT( l, scratch );
  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l, alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  ctx->topo = topo;
  ctx->boot_ts = fd_log_wallclock();
  ctx->cnc = NULL;

  ulong scratch_top = FD_SCRATCH_ALLOC_FINI( l, scratch_align() );
  if( FD_UNLIKELY( scratch_top > (ulong)scratch + scratch_footprint( tile ) ) )
    FD_LOG_ERR(( "scratch overflow %lu %lu %lu", scratch_top - (ulong)scratch - scratch_footprint( tile ), scratch_top, (ulong)scratch + scratch_footprint( tile ) ));

  FD_LOG_NOTICE(( "prometheus metrics endpoint listening at http://" FD_IP4_ADDR_FMT ":%u/metrics", FD_IP4_ADDR_FMT_ARGS( tile->metric.prometheus_listen_addr ), tile->metric.prometheus_listen_port ));
}

/* ---------------------------------------------------------------------
   Seccomp / FD helpers
   --------------------------------------------------------------------- */

ulong
populate_allowed_seccomp( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile,
                          ulong                  out_cnt,
                          struct sock_filter *   out ) {

#if FD_HAS_LINUX
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  FD_SCRATCH_ALLOC_INIT( l, scratch );
  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l, alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  populate_sock_filter_policy_fd_metric_tile( out_cnt, out, (uint)fd_log_private_logfile_fd(), (uint)fd_http_server_fd( ctx->metrics_server ) );
  return sock_filter_policy_fd_metric_tile_instr_cnt;
#else
  (void)topo; (void)tile;
  (void)out_cnt; (void)out;
  return 0UL;
#endif
}

ulong
populate_allowed_fds( fd_topo_t const *      topo,
                      fd_topo_tile_t const * tile,
                      ulong                  out_fds_cnt,
                      int *                  out_fds ) {
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  FD_SCRATCH_ALLOC_INIT( l, scratch );
  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l, alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  if( FD_UNLIKELY( out_fds_cnt<3UL ) ) FD_LOG_ERR(( "out_fds_cnt %lu", out_fds_cnt ));

  ulong out_cnt = 0;
  out_fds[ out_cnt++ ] = 2; /* stderr */
  if( FD_LIKELY( -1!=fd_log_private_logfile_fd() ) )
    out_fds[ out_cnt++ ] = fd_log_private_logfile_fd(); /* logfile */
  out_fds[ out_cnt++ ] = fd_http_server_fd( ctx->metrics_server ); /* metrics listen socket */
  return out_cnt;
}

/* ---------------------------------------------------------------------
   stem_run — generated via the fd_stem template.
   
   KEY DIFFERENCE FROM UPSTREAM: STEM_CALLBACK_SHOULD_SHUTDOWN checks
   ctx->cnc for HALT instead of always returning 0.  This is the fix
   for v2.23-m task 2 — tkmetr now properly shuts down when the
   supervisor sends HALT via CNC.
   
   For Firedancer's native metric tile, ctx->cnc is NULL so the check
   still returns 0 (no change).  Tickoni's tk_metric_tile sets ctx->cnc
   before calling stem_run, enabling the HALT check.
   --------------------------------------------------------------------- */

#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6) /* 10ms */

#undef STEM_EXPORT
#define STEM_EXPORT
#define STEM_CALLBACK_CONTEXT_TYPE  fd_metric_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN alignof(fd_metric_ctx_t)

#define STEM_CALLBACK_BEFORE_CREDIT before_credit
#define STEM_CALLBACK_METRICS_WRITE metrics_write

/* Check CNC for HALT if ctx->cnc is set; otherwise never shut down
   (matches upstream behavior for Firedancer's native metric tile). */
#define STEM_CALLBACK_SHOULD_SHUTDOWN( ctx ) \
  ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT )

#include "../stem/fd_stem.c"

/* Clear STEM_EXPORT after the include so subsequent STEM instantiations
   (e.g. verify tile) see no STEM_EXPORT and use their own #ifndef
   STEM_EXPORT / #define STEM_EXPORT static blocks to default to static.
   This prevents duplicate stem_run symbols. */
#undef STEM_EXPORT

/* ---------------------------------------------------------------------
   fd_tile_metric — the canonical Firedancer metric-tile run config.
   --------------------------------------------------------------------- */

const fd_topo_run_tile_t fd_tile_metric = {
  .name                     = "metric",
  .rlimit_file_cnt          = FD_HTTP_SERVER_METRICS_MAX_CONNS+5UL, /* pipefd, socket, stderr, logfile, and one spare for new accept() connections */
  .populate_allowed_seccomp = populate_allowed_seccomp,
  .populate_allowed_fds     = populate_allowed_fds,
  .scratch_align            = scratch_align,
  .scratch_footprint        = scratch_footprint,
  .privileged_init          = privileged_init,
  .unprivileged_init        = unprivileged_init,
  .run                      = stem_run,
};
