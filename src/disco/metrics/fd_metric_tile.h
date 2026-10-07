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

   In v2.23-m task 2 we also export stem_run, privileged_init and
   unprivileged_init so tk_metric_tile.c can call stem_run directly
   instead of maintaining a custom polling loop.
*/
#ifndef HEADER_fd_src_disco_metrics_fd_metric_tile_h
#define HEADER_fd_src_disco_metrics_fd_metric_tile_h

#include "../../waltz/http/fd_http_server.h"
#include "../topo/fd_topo.h"

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
  long long boot_ts;
  /* Optional CNC pointer for shutdown checking.  When non-NULL,
     STEM_CALLBACK_SHOULD_SHUTDOWN (defined in fd_metric_tile.c)
     checks ctx->cnc for HALT each iteration of stem_run.  When
     HALT is detected, STEM_CALLBACK_SHOULD_SHUTDOWN sets
     tile->allow_shutdown=1, which stem_run checks at the end of
     its loop and exits.
     Firedancer's native metric tile leaves this NULL.
     Tickoni's tk_metric_tile sets it in tk_metric_run.
     See v2.23-m task 2. */
  void * cnc;
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
   HTTP request handler — external so tk_metric_tile.c can register it.
   --------------------------------------------------------------------- */

fd_http_server_response_t metrics_http_request( fd_http_server_request_t const * request );

/* ---------------------------------------------------------------------
   Seccomp / FD helpers — external so tk_metric_tile.c can register them.
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

/* ---------------------------------------------------------------------
   stem_run — exported from fd_stem.c via STEM_EXPORT (v2.23-m task 2).
   This is the stem-based polling loop that calls before_credit every
   iteration.  tk_metric_tile.c uses it instead of maintaining a custom
   loop.  Before calling stem_run, tk_metric_tile sets ctx->cnc so
   STEM_CALLBACK_SHOULD_SHUTDOWN (defined in fd_metric_tile.c) can
   check for HALT via CNC and set tile->allow_shutdown=1 when detected
   (stem_run checks allow_shutdown at the end of its loop and exits
   when it's set).
   --------------------------------------------------------------------- */

void stem_run( fd_topo_t *      topo,
               fd_topo_tile_t * tile );

/* ---------------------------------------------------------------------
   privileged_init / unprivileged_init — promoted from static so that
   tk_metric_tile.c can invoke them before calling stem_run (v2.23-m task 2).
   --------------------------------------------------------------------- */

void privileged_init( fd_topo_t const *      topo,
                      fd_topo_tile_t const * tile );

void unprivileged_init( fd_topo_t const *      topo,
                        fd_topo_tile_t const * tile );

#endif /* HEADER_fd_src_disco_metrics_fd_metric_tile_h */
