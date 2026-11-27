/* Dispatches registered tiles to their fd_stem run descriptors.
   Linux uses upstream fd_topo_run_tile(); other targets use Tickoni's
   tk_topo_run_tile() shim. */

#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS
#define _GNU_SOURCE
#endif

#include "../../../util/fd_util.h"
#include "../../../disco/topo/fd_topo.h"
#include "audit_schema.h"

#if FD_HAS_LINUX || FD_HAS_MACOS
#include <unistd.h>
#endif
#include <stdio.h>

extern void tk_topo_run_tile( void * topo, void * tile, int sandbox,
                              int keep_controlling_terminal, int core_dump_level,
                              uint uid, uint gid, int allow_fd, void * tile_run );

/* TK_METRIC_RUN from tk_metric_tile.c. The metric tile uses
   Firedancer's fd_stem-based run loop with fd_http_server for /metrics.
   Shared header prevents two independent extern declarations.
   Linux or macOS: tk_metric_tile.c depends on symbols from fd_metric_tile.c. */
#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS
#include "../topo_run/tk_metric_tile.h"
#include "../topo_run/tk_audit_stem.h"
#include "../topo_run/tk_norm_stem.h"
#include "../topo_run/tk_dedu_stem.h"
#include "../topo_run/tk_policy_stem.h"
#include "../topo_run/tk_model_stem.h"
#include "../topo_run/tk_agent_stem.h"
#include "../topo_run/tk_disp_stem.h"
#include "../topo_run/tk_case_stem.h"
#include "../topo_run/tk_repl_stem.h"
#include "../topo_run/tk_pass_stem.h"
#include "../topo_run/tk_diag_stem.h"
#include "../topo_run/tk_ingest_stem.h"
#include "../topo_run/tk_gate_stem.h"
#endif

static int
tile_is_gate( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKGATE )==0;
}

static int
tile_is_ingest( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKINGS )==0;
}

/* Check if this tile should use the metric run tile. Compares tile name
   the tile's name field (null-terminated in
   tile_name_sz). */
static int
tile_is_metric( fd_topo_tile_t * tile ) {
  FD_LOG_DEBUG(( "tile_run: tile_is_metric ENTER tile=%p", (void*)tile ));
  if( !tile ) {
    FD_LOG_DEBUG(( "tile_run: tile_is_metric EXIT tile=NULL returning 0" ));
    return 0;
  }
  int result = strcmp( tile->name, TILE_ID_METRIC ) == 0;
  FD_LOG_DEBUG(( "tile_run: tile_is_metric EXIT tile->name=%s returning %d", tile->name, result ));
  return result;
}

/* Check if this tile should use the audit stem run tile. Compares tile name
   against TILE_ID_TKAUDT (the name field in the topology that maps to the
   audit stem tile). */
static int
tile_is_audit( fd_topo_tile_t * tile ) {
  FD_LOG_DEBUG(( "tile_run: tile_is_audit ENTER tile=%p", (void*)tile ));
  if( !tile ) {
    FD_LOG_DEBUG(( "tile_run: tile_is_audit EXIT tile=NULL returning 0" ));
    return 0;
  }
  FD_LOG_DEBUG(( "tile_run: tile_is_audit: tile->name=%s", tile->name ));
  int result = strcmp( tile->name, TILE_ID_TKAUDT ) == 0;
  FD_LOG_DEBUG(( "tile_run: tile_is_audit EXIT tile->name=%s returning %d", tile->name, result ));
  return result;
}

/* Check if this tile should use the norm stem run tile. Compares tile name
   against TILE_ID_TKNORM. */
static int
tile_is_norm( fd_topo_tile_t * tile ) {
  FD_LOG_DEBUG(( "tile_run: tile_is_norm ENTER tile=%p", (void*)tile ));
  if( !tile ) {
    FD_LOG_DEBUG(( "tile_run: tile_is_norm EXIT tile=NULL returning 0" ));
    return 0;
  }
  FD_LOG_DEBUG(( "tile_run: tile_is_norm: tile->name=%s", tile->name ));
  int result = strcmp( tile->name, TILE_ID_TKNORM ) == 0;
  FD_LOG_DEBUG(( "tile_run: tile_is_norm EXIT tile->name=%s returning %d", tile->name, result ));
  return result;
}

/* Check if this tile should use the dedu stem run tile. Compares tile name
   against TILE_ID_TKDEDU. */
static int
tile_is_dedu( fd_topo_tile_t * tile ) {
  FD_LOG_DEBUG(( "tile_run: tile_is_dedu ENTER tile=%p", (void*)tile ));
  if( !tile ) {
    FD_LOG_DEBUG(( "tile_run: tile_is_dedu EXIT tile=NULL returning 0" ));
    return 0;
  }
  FD_LOG_DEBUG(( "tile_run: tile_is_dedu: tile->name=%s", tile->name ));
  int result = strcmp( tile->name, TILE_ID_TKDEDU ) == 0;
  FD_LOG_DEBUG(( "tile_run: tile_is_dedu EXIT tile->name=%s returning %d", tile->name, result ));
  return result;
}

/* Check if this tile should use the policy stem run tile. Compares tile name
   against TILE_ID_TKPOLY. */
static int
tile_is_policy( fd_topo_tile_t * tile ) {
  FD_LOG_DEBUG(( "tile_run: tile_is_policy ENTER tile=%p", (void*)tile ));
  if( !tile ) {
    FD_LOG_DEBUG(( "tile_run: tile_is_policy EXIT tile=NULL returning 0" ));
    return 0;
  }
  FD_LOG_DEBUG(( "tile_run: tile_is_policy: tile->name=%s", tile->name ));
  int result = strcmp( tile->name, TILE_ID_TKPOLY ) == 0;
  FD_LOG_DEBUG(( "tile_run: tile_is_policy EXIT tile->name=%s returning %d", tile->name, result ));
  return result;
}

/* Predicate that matches the tkmodl tile by comparing the tile name against
   TILE_ID_TKMODL. */
static int
tile_is_model( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKMODL ) == 0;
}

/* Predicate that matches the tkagnt agent-worker tile. */
static int
tile_is_agent( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKAGNT ) == 0;
}

/* Predicates for the placeholder tiles of the investment workflow. */
static int
tile_is_case( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKCASE ) == 0;
}

static int
tile_is_tool( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKTOOL ) == 0;
}

static int
tile_is_adpt( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKADPT ) == 0;
}

/* Predicate that matches the tkdisp terminal-result sink tile. */
static int
tile_is_disp( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKDISP ) == 0;
}

/* Predicate that matches the tkrepl replay tile. */
static int
tile_is_replay( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKREPL ) == 0;
}

/* Predicate that matches the tkdiag diagnostic observer tile. */
static int
tile_is_diag( fd_topo_tile_t * tile ) {
  return tile!=NULL && strcmp( tile->name, TILE_ID_TKDIAG ) == 0;
}

static int const TK_PROCESS_MODE_SANDBOX_NONE = 0;
static int const TK_KEEP_CONTROLLING_TERMINAL = 1;

/* One tile per process, sandbox=none, regular core dumps, and the current
   process's uid/gid on hosted Unix. Reject unknown tile IDs before launch. */
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
  fd_topo_tile_t * tile_c = (fd_topo_tile_t *)tile;
  fd_topo_run_tile_t * run_tile = NULL;
#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS
  if( tile_is_gate( tile_c ) ) {
    run_tile = &TK_GATE_RUN;
  } else if( tile_is_ingest( tile_c ) ) {
    run_tile = &TK_INGEST_RUN;
  } else if( tile_is_dedu( tile_c ) ) {
    run_tile = &TK_DEDU_RUN;
  } else if( tile_is_audit( tile_c ) ) {
    run_tile = &TK_AUDIT_RUN;
  } else if( tile_is_metric( tile_c ) ) {
    run_tile = &TK_METRIC_RUN;
  } else if( tile_is_norm( tile_c ) ) {
    run_tile = &TK_NORM_RUN;
  } else if( tile_is_policy( tile_c ) ) {
    run_tile = &TK_POLICY_RUN;
  } else if( tile_is_model( tile_c ) ) {
    run_tile = &TK_MODEL_RUN;
  } else if( tile_is_agent( tile_c ) ) {
    run_tile = &TK_AGENT_RUN;
  } else if( tile_is_disp( tile_c ) ) {
    run_tile = &TK_DISP_RUN;
  } else if( tile_is_case( tile_c ) ) {
    run_tile = &TK_CASE_RUN;
  } else if( tile_is_tool( tile_c ) ) {
    run_tile = &TK_TOOL_RUN;
  } else if( tile_is_adpt( tile_c ) ) {
    run_tile = &TK_ADPT_RUN;
  } else if( tile_is_diag( tile_c ) ) {
    run_tile = &TK_DIAG_RUN;
  } else if( tile_is_replay( tile_c ) ) {
    run_tile = &TK_REPL_RUN;
  } else {
    FD_LOG_ERR(( "tile_run: unregistered tile %s", tile_c ? tile_c->name : "(null)" ));
  }
#else
  (void)tile_is_gate;
  (void)tile_is_ingest;
  (void)tile_is_dedu;
  (void)tile_is_audit;
  (void)tile_is_metric;
  (void)tile_is_norm;
  (void)tile_is_policy;
  (void)tile_is_model;
  (void)tile_is_agent;
  (void)tile_is_disp;
  (void)tile_is_case;
  (void)tile_is_tool;
  (void)tile_is_adpt;
  (void)tile_is_diag;
  (void)tile_is_replay;
  FD_LOG_ERR(( "tile_run: no stem tiles available for this target" ));
#endif

  FD_LOG_DEBUG(( "tile_run: calling fd_topo_run_tile, run_tile=%p", (void*)run_tile ));
  FD_LOG_DEBUG(( "tile_run: tile->id=%lu name=%s in_cnt=%lu",
    tile_c->id, tile_c->name, tile_c->in_cnt ));
  for( ulong j=0UL; j < tile_c->in_cnt; j++ ) {
    FD_LOG_DEBUG(( "tile_run:   in_link[%lu] fseq_obj_id=%lu",
      j, tile_c->in_link_fseq_obj_id[j] ));
  }

#if FD_HAS_LINUX
  fd_topo_run_tile( (fd_topo_t *)topo, (fd_topo_tile_t *)tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    (uint)getuid(), (uint)getgid(), /* allow_fd */ -1,
                    run_tile );
  FD_LOG_DEBUG(( "tile_run: fd_topo_run_tile returned (tile_name=%s)", tile_c->name ));
#elif FD_HAS_MACOS
  tk_topo_run_tile( topo, tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    (uint)getuid(), (uint)getgid(), /* allow_fd */ -1,
                    run_tile );
#else
  tk_topo_run_tile( topo, tile,
                    TK_PROCESS_MODE_SANDBOX_NONE, TK_KEEP_CONTROLLING_TERMINAL,
                    FD_TOPO_CORE_DUMP_LEVEL_REGULAR,
                    0U, 0U, /* allow_fd */ -1,
                    run_tile );
#endif
  FD_LOG_DEBUG(( "tile_run: tk_topo_run_tile_simple EXIT" ));
}
