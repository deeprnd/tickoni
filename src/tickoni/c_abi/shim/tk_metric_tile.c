/* tk_metric_tile.c — Tickoni's metric tile (tkmetr) implementation.
 *
 * Reuses Firedancer's fd_metric_tile.c (Prometheus HTTP endpoint,
 * fd_prometheus_render_all, stem-based polling loop) by including it
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
 *   • CRITICAL: tkmetr has 0 in/out links. Firedancer's stem_run loop
 *     dereferences out_seq[0] even when out_cnt==0, causing SIGSEGV.
 *     We use a custom tk_metric_run loop (below) that skips stem entirely
 *     and only calls before_credit for HTTP polling.
 *   • Shutdown: tk_metric_run joins the CNC from topo_build.zig's cnc_obj_id
 *     and checks for HALT signal.  When HALT arrives, it sets
 *     tile->allow_shutdown = 1 and returns.
 */

#define _GNU_SOURCE

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"
#include "../../../disco/metrics/fd_metric_tile.c"  // defines stem_run, METRICS_PARAMS, fd_metric_ctx_t
#include "../../../disco/metrics/fd_prometheus.h"

#include <time.h>   /* nanosleep for the tk_metric_run polling loop */
#include <unistd.h> /* nanosleep declaration (glibc feature test) */

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
  ctx->topo = topo;
  ctx->boot_ts = fd_log_wallclock();
  ctx->metrics_server = fd_http_server_join(
    fd_http_server_new( _metrics, METRICS_PARAMS, metrics_callbacks, ctx )
  );
  fd_http_server_listen( ctx->metrics_server,
                         tile->metric.prometheus_listen_addr,
                         tile->metric.prometheus_listen_port );
}

/* ---------------------------------------------------------------------
   tk_metric_run — custom polling loop for 0-I/O observer tile.
   Firedancer's stem_run crashes when out_cnt == 0 (dereferences NULL
   out_seq[0]).  tkmetr has no mcache/dcache/fseq links, so we only need
   the before_credit loop for HTTP polling.

   Shutdown: the CNC object for tile i is at index cnc_obj_id[i] in the
   topo objects array (set by topo_build.zig's topobTileUses).  We find
   that object by scanning the topo's object list for the "cnc" entry
   whose index matches the cnc_obj_id for this tile.
   --------------------------------------------------------------------- */

static void
tk_metric_run( fd_topo_t *      topo,
               fd_topo_tile_t * tile ) {
  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );

  FD_SCRATCH_ALLOC_INIT( l, scratch );
  fd_metric_ctx_t * ctx = FD_SCRATCH_ALLOC_APPEND( l,
    alignof( fd_metric_ctx_t ), sizeof( fd_metric_ctx_t ) );

  /* Verify scratch matches what privileged_init allocated */
  if( ctx->metrics_server == NULL ) {
    FD_LOG_ERR(( "tkmetr: metrics server not initialized" ));
  }

  /* Find the CNC object for this tile.  In topo_build.zig, every tile
     gets a CNC created via topobTileUses(topo, tile_idx, cnc_obj_id,
     true).  The CNC object is stored in the topo object array; we find
     it by iterating until we find the "cnc" object whose index matches
     what topo_build.zig set up for this tile's uses_obj_id. */
  fd_cnc_t * cnc = NULL;
  for( ulong i = 0; i < tile->uses_obj_cnt; i++ ) {
    ulong obj_id = tile->uses_obj_id[ i ];
    if( !strcmp( topo->objs[ obj_id ].name, "cnc" ) ) {
      void * laddr = fd_topo_obj_laddr( topo, obj_id );
      cnc = fd_cnc_join( laddr );
      break;
    }
  }
  if( !cnc ) {
    /* If we can't find a CNC, just spin until the supervisor kills us */
    FD_LOG_WARNING(( "tkmetr: could not find CNC object, will run until killed" ));
  }

  /* Simple polling loop: only HTTP polling, no stem input/output processing */
  for(;;) {
    int charge_busy = 0;
    before_credit( ctx, NULL, &charge_busy );

    /* Check for shutdown signal via CNC */
    if( cnc ) {
      ulong sig = fd_cnc_signal_query( cnc );
      if( sig == FD_CNC_SIGNAL_HALT ) {
        /* Transition to BOOT before stopping (per CNC state machine) */
        fd_cnc_signal( cnc, FD_CNC_SIGNAL_BOOT );
        tile->allow_shutdown = 1;
        FD_LOG_INFO(( "tkmetr: received HALT signal, shutting down" ));
        fd_cnc_leave( cnc );
        break;
      }
      fd_cnc_leave( cnc );
    }

    /* Sleep briefly to avoid burning CPU */
    struct timespec ts = { .tv_sec = 0, .tv_nsec = 1000000L }; /* 1ms */
    nanosleep( &ts, NULL );
  }
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
  .unprivileged_init        = NULL,   /* tk_metric_run handles full init */
  .run                      = tk_metric_run,
  .rlimit_file_cnt_fn       = NULL,
};
