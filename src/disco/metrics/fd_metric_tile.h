/* Public declarations for the Firedancer metric tile implementation.

   These symbols are normally static inside fd_metric_tile.c.  Tickoni's
   tk_metric_tile.c needs direct access to several of them (scratch
   layout, before_credit, HTTP request handler, seccomp/fd helpers)
   so they are promoted to external linkage here.

   This header lets tk_metric_tile.c #include it instead of the
   fragile `#include "fd_metric_tile.c"` which was pulling in the
   entire source file (including stem_run's static helpers and
   unprivileged_init) and creating tight coupling.

   See v2.23-m task 1.
*/
#ifndef HEADER_fd_src_disco_metrics_fd_metric_tile_h
#define HEADER_fd_src_disco_metrics_fd_metric_tile_h

#include "waltz/http/fd_http_server.h"
#include "disco/topo/fd_topo.h"

/* ---------------------------------------------------------------------
   Configuration constant — external so tk_metric_tile.c can reference it.
   --------------------------------------------------------------------- */

extern const fd_http_server_params_t METRICS_PARAMS;

/* ---------------------------------------------------------------------
   Context type
   --------------------------------------------------------------------- */

typedef struct {
  fd_topo_t const * topo;
  fd_http_server_t * metrics_server;
  long boot_ts;
} fd_metric_ctx_t;

/* ---------------------------------------------------------------------
   Scratch helpers — duplicated from fd_metric_tile.c for Tickoni.
   (We declare them extern because fd_metric_tile.c now exports them.)
   --------------------------------------------------------------------- */

ulong scratch_align( void );

ulong scratch_footprint( fd_topo_tile_t const * tile );

/* ---------------------------------------------------------------------
   Stem callbacks (before_credit / metrics_write) — promoted from static.
   --------------------------------------------------------------------- */

void before_credit( fd_metric_ctx_t *   ctx,
                    fd_stem_context_t * stem,
                    int *               charge_busy );

/* ---------------------------------------------------------------------
   HTTP request handler — promoted from static.
   --------------------------------------------------------------------- */

fd_http_server_response_t metrics_http_request( fd_http_server_request_t const * request );

/* ---------------------------------------------------------------------
   Seccomp / FD helpers — promoted from static.
   --------------------------------------------------------------------- */

ulong populate_allowed_seccomp( fd_topo_t const *      topo,
                                fd_topo_tile_t const * tile,
                                ulong                  out_cnt,
                                struct sock_filter *   out );

ulong populate_allowed_fds( fd_topo_t const *      topo,
                            fd_topo_tile_t const * tile,
                            ulong                  out_fds_cnt,
                            int *                  out_fds );

/* ---------------------------------------------------------------------
   The canonical Firedancer metric-tile run config (read-only).
   --------------------------------------------------------------------- */

extern const fd_topo_run_tile_t fd_tile_metric;

#endif /* HEADER_fd_src_disco_metrics_fd_metric_tile_h */
