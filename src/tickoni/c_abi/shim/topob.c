/* Thin wrappers around Firedancer's fd_topob topology builder
   (fd_topob_new/wksp/obj/link/tile/tile_in/tile_out/finish) plus the two
   parent-side workspace-materialization steps
   (fd_topo_create_workspace/fd_topo_wksp_new).

   This file also owns Tickoni's own fd_topo_obj_callbacks_t array
   (mcache/dcache/fseq/metrics/tile/cnc) passed to fd_topob_finish and
   fd_topo_wksp_new. It intentionally does NOT reuse
   src/app/shared/fd_obj_callbacks.c: that file's "tile" callback calls
   fdctl_tile_run(), the real Solana validator's TILES[] dispatcher —
   exactly the fdctl coupling Tickoni must not depend on (V1.14.S8.T12
   finding 1). mcache/dcache/fseq/metrics below are reimplemented
   identically to that file's versions (they only touch generic
   tango/metrics primitives); "tile" and "cnc" are Tickoni-owned:
   - "tile" has zero footprint/no .new — Phase 0 tiles need no fd_scratch
     tile-local memory. Extend this (not fdctl_tile_run) if a future
     tile needs scratch space.
   - "cnc" is a new object type: fd_topob has no built-in concept of cnc,
     so this makes Tickoni's cnc-per-tile a real, offset-accounted
     fd_topob object instead of an ad hoc post-hoc wksp_alloc.

   This file and topo_run.c are the only places Firedancer topology types
   (fd_topo_t, fd_topo_tile_t, fd_topo_obj_t, fd_topo_obj_callbacks_t)
   exist in Tickoni. */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include "../../../util/fd_util.h"
#include "../../../util/pod/fd_pod_format.h"
#include "../../../disco/topo/fd_topob.h"
#include "../../../disco/metrics/fd_metrics.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "../../../tango/mcache/fd_mcache.h"
#include "../../../tango/dcache/fd_dcache.h"
#include "../../../tango/fseq/fd_fseq.h"

/* ---------------------------------------------------------------------
   tk_topob_auto_layout — Tickoni CPU placement.
   ---------------------------------------------------------------------

   Called after all tiles are added. Iterates topo->tiles[] and sets each
   tile->cpu_idx from the cpu_idx[] array passed by the harness.

   This mirrors the Firedancer harness pattern:
     fd_topob_auto_layout(topo, 0);   // Firedancer assigns CPUs from priority arrays
   vs.
     tk_topob_auto_layout(topo, cpu_idx_arr); // Tickoni assigns CPUs from harness array
   Both are called after tile/link wiring and before topob_finish. */

void
tk_topob_auto_layout( void * topo, ulong const * cpu_idx_arr ) {
  fd_topo_t * t = (fd_topo_t *)topo;
  for( ulong i = 0UL; i < t->tile_cnt; i++ ) {
    t->tiles[ i ].cpu_idx = cpu_idx_arr[ i ];
  }
}

/* ---------------------------------------------------------------------
   Tickoni-owned object callbacks.
   --------------------------------------------------------------------- */

#define VAL(name) (__extension__({                                                             \
  ulong __x = fd_pod_queryf_ulong( topo->props, ULONG_MAX, "obj.%lu.%s", obj->id, name );      \
  if( FD_UNLIKELY( __x==ULONG_MAX ) ) FD_LOG_ERR(( "obj.%lu.%s was not set", obj->id, name )); \
  __x; }))

static ulong
mcache_footprint( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  return fd_mcache_footprint( VAL("depth"), 0UL );
}

static ulong
mcache_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_mcache_align();
}

static void
mcache_new( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  FD_TEST( fd_mcache_new( fd_topo_obj_laddr( topo, obj->id ), VAL("depth"), 0UL, 0UL ) );
}

static fd_topo_obj_callbacks_t tk_obj_cb_mcache = {
  .name      = "mcache",
  .footprint = mcache_footprint,
  .align     = mcache_align,
  .new       = mcache_new,
};

static ulong
dcache_footprint( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  ulong app_sz  = fd_pod_queryf_ulong( topo->props, 0UL,       "obj.%lu.app_sz",  obj->id );
  ulong data_sz = fd_pod_queryf_ulong( topo->props, ULONG_MAX, "obj.%lu.data_sz", obj->id );
  if( data_sz==ULONG_MAX ) data_sz = fd_dcache_req_data_sz( VAL("mtu"), VAL("depth"), VAL("burst"), 1 );
  return fd_dcache_footprint( data_sz, app_sz );
}

static ulong
dcache_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_dcache_align();
}

static void
dcache_new( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  ulong app_sz  = fd_pod_queryf_ulong( topo->props, 0UL,       "obj.%lu.app_sz",  obj->id );
  ulong data_sz = fd_pod_queryf_ulong( topo->props, ULONG_MAX, "obj.%lu.data_sz", obj->id );
  if( data_sz==ULONG_MAX ) data_sz = fd_dcache_req_data_sz( VAL("mtu"), VAL("depth"), VAL("burst"), 1 );
  FD_TEST( fd_dcache_new( fd_topo_obj_laddr( topo, obj->id ), data_sz, app_sz ) );
}

static fd_topo_obj_callbacks_t tk_obj_cb_dcache = {
  .name      = "dcache",
  .footprint = dcache_footprint,
  .align     = dcache_align,
  .new       = dcache_new,
};

static ulong
fseq_footprint( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_fseq_footprint();
}

static ulong
fseq_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_fseq_align();
}

static void
fseq_new( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  FD_TEST( fd_fseq_new( fd_topo_obj_laddr( topo, obj->id ), ULONG_MAX ) );
}

static fd_topo_obj_callbacks_t tk_obj_cb_fseq = {
  .name      = "fseq",
  .footprint = fseq_footprint,
  .align     = fseq_align,
  .new       = fseq_new,
};

static ulong
metrics_footprint( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  return FD_METRICS_FOOTPRINT( VAL("in_cnt") );
}

static ulong
metrics_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return FD_METRICS_ALIGN;
}

static void
metrics_new( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  FD_TEST( fd_metrics_new( fd_topo_obj_laddr( topo, obj->id ), VAL("in_cnt") ) );
}

static fd_topo_obj_callbacks_t tk_obj_cb_metrics = {
  .name      = "metrics",
  .footprint = metrics_footprint,
  .align     = metrics_align,
  .new       = metrics_new,
};

/* Tickoni-owned "tile" object: Phase 0 tiles need no fd_scratch tile-local
   memory, so this is a deliberate minimal (not zero — fd_topob_finish's
   NUMA-assignment step requires every object to have a non-zero
   footprint) placeholder, NOT a call into fdctl_tile_run()/TILES[]. */
static ulong
tile_footprint( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return 1UL;
}

static ulong
tile_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return 1UL;
}

static fd_topo_obj_callbacks_t tk_obj_cb_tile = {
  .name      = "tile",
  .footprint = tile_footprint,
  .align     = tile_align,
  .new       = NULL,
};

/* Tickoni-owned "cnc" object: fd_topob has no built-in cnc concept.
   Finds the owning tile by scanning uses_obj_id[] (same pattern
   Firedancer's own tile_footprint() uses to find a tile from an obj id,
   just over uses_obj_id[] instead of tile_obj_id) and uses that tile's
   id as fd_cnc_new's cnc_type, matching what supervisor.zig passes
   today. app_sz is fixed at 64 bytes, matching cnc_counters.zig's
   existing app-region layout. */
static ulong
cnc_footprint( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_cnc_footprint( 64UL );
}

static ulong
cnc_align( fd_topo_t const * topo FD_FN_UNUSED, fd_topo_obj_t const * obj FD_FN_UNUSED ) {
  return fd_cnc_align();
}

static void
cnc_new( fd_topo_t const * topo, fd_topo_obj_t const * obj ) {
  ulong cnc_type = ULONG_MAX;
  for( ulong i=0UL; i<topo->tile_cnt; i++ ) {
    fd_topo_tile_t const * tile = &topo->tiles[ i ];
    for( ulong j=0UL; j<tile->uses_obj_cnt; j++ ) {
      if( FD_UNLIKELY( tile->uses_obj_id[ j ]==obj->id ) ) { cnc_type = tile->id; break; }
    }
    if( FD_UNLIKELY( cnc_type!=ULONG_MAX ) ) break;
  }
  FD_TEST( cnc_type!=ULONG_MAX );
  FD_TEST( fd_cnc_new( fd_topo_obj_laddr( topo, obj->id ), 64UL, cnc_type, fd_log_wallclock() ) );
}

static fd_topo_obj_callbacks_t tk_obj_cb_cnc = {
  .name      = "cnc",
  .footprint = cnc_footprint,
  .align     = cnc_align,
  .new       = cnc_new,
};

static fd_topo_obj_callbacks_t * TK_CALLBACKS[] = {
  &tk_obj_cb_mcache,
  &tk_obj_cb_dcache,
  &tk_obj_cb_fseq,
  &tk_obj_cb_metrics,
  &tk_obj_cb_tile,
  &tk_obj_cb_cnc,
  NULL,
};

#undef VAL

/* ---------------------------------------------------------------------
   tk_* wrappers.
   --------------------------------------------------------------------- */

ulong
tk_topo_sizeof( void ) { return sizeof( fd_topo_t ); }

ulong
tk_topo_alignof( void ) { return alignof( fd_topo_t ); }

void *
tk_topob_new( void * mem, char const * app_name ) {
  FD_LOG_NOTICE(( "tk_topob_new: mem=%p app_name=%s", mem, app_name ));
  void * result = fd_topob_new( mem, app_name );
  FD_LOG_DEBUG(( "tk_topob_new: result=%p", result ));
  return result;
}

ulong
tk_topob_wksp( void * topo, char const * name ) {
  fd_topo_wksp_t * wksp = fd_topob_wksp( (fd_topo_t *)topo, name );
  return wksp->id;
}

ulong
tk_topob_obj( void * topo, char const * obj_type, char const * wksp_name ) {
  fd_topo_obj_t * obj = fd_topob_obj( (fd_topo_t *)topo, obj_type, wksp_name );
  return obj->id;
}

void
tk_topob_tile_uses( void * topo, ulong tile_id, ulong obj_id, int mode ) {
  fd_topo_t * t = (fd_topo_t *)topo;
  fd_topob_tile_uses( t, &t->tiles[ tile_id ], &t->objs[ obj_id ], mode );
}

ulong
tk_topob_link( void * topo, char const * link_name, char const * wksp_name, ulong depth, ulong mtu, ulong burst ) {
  fd_topo_link_t * link = fd_topob_link( (fd_topo_t *)topo, link_name, wksp_name, depth, mtu, burst );
  return link->id;
}

ulong
tk_topob_tile( void * topo, char const * tile_name, char const * tile_wksp, char const * metrics_wksp, ulong cpu_idx ) {
  fd_topo_tile_t * tile = fd_topob_tile( (fd_topo_t *)topo, tile_name, tile_wksp, metrics_wksp, cpu_idx,
                                        /* is_agave */ 0, /* uses_id_keyswitch */ 0, /* uses_av_keyswitch */ 0 );
  return tile->id;
}

/* Returns the fseq object id fd_topob_tile_in creates for this in-link
   (the last entry of the tile's in_link_fseq_obj_id[] array right after
   its in_cnt is incremented) — needed by the parent to resolve/gaddr the
   fseq it must not create twice, and by anything that wants to read the
   fseq's laddr directly (V1.14.S8.T12). */
ulong
tk_topob_tile_in( void * topo, char const * tile_name, ulong tile_kind_id, char const * fseq_wksp,
                  char const * link_name, ulong link_kind_id, int reliable, int polled ) {
  fd_topo_t * t = (fd_topo_t *)topo;
  ulong tile_id = fd_topo_find_tile( t, tile_name, tile_kind_id );
  fd_topob_tile_in( t, tile_name, tile_kind_id, fseq_wksp, link_name, link_kind_id, reliable, polled );
  fd_topo_tile_t * tile = &t->tiles[ tile_id ];
  return tile->in_link_fseq_obj_id[ tile->in_cnt - 1UL ];
}

ulong
tk_topo_link_mcache_obj_id( void * topo, ulong link_id ) {
  return ((fd_topo_t *)topo)->links[ link_id ].mcache_obj_id;
}

ulong
tk_topo_link_dcache_obj_id( void * topo, ulong link_id ) {
  return ((fd_topo_t *)topo)->links[ link_id ].dcache_obj_id;
}

void
tk_topob_tile_out( void * topo, char const * tile_name, ulong tile_kind_id, char const * link_name, ulong link_kind_id ) {
  fd_topob_tile_out( (fd_topo_t *)topo, tile_name, tile_kind_id, link_name, link_kind_id );
}

void
tk_topob_finish( void * topo ) {
  fd_topob_finish( (fd_topo_t *)topo, TK_CALLBACKS );
}

int
tk_topo_create_workspace( void * topo, ulong wksp_idx, int update_existing ) {
  fd_topo_t * t = (fd_topo_t *)topo;
  return fd_topo_create_workspace( t, &t->workspaces[ wksp_idx ], update_existing );
}

void
tk_topo_wksp_new( void * topo, ulong wksp_idx ) {
  fd_topo_t * t = (fd_topo_t *)topo;
  fd_topo_wksp_new( t, &t->workspaces[ wksp_idx ], TK_CALLBACKS );
}

/* Maps every workspace in the topology into this process's address space
   (parent-side: needed before fd_topo_obj_laddr-based object content can
   be written by tk_topo_wksp_new, or read/written directly afterward).
   Distinct from tk_topo_join_tile_workspaces in topo_run.c, which only
   joins the subset of workspaces one tile needs. */
void
tk_topo_join_workspaces( void * topo, int mode, int core_dump_level ) {
  fd_topo_join_workspaces( (fd_topo_t *)topo, mode, core_dump_level );
}

void
tk_topo_leave_workspaces( void * topo ) {
  fd_topo_leave_workspaces( (fd_topo_t *)topo );
}

ulong
tk_topo_find_wksp( void * topo, char const * name ) {
  return fd_topo_find_wksp( (fd_topo_t *)topo, name );
}

ulong
tk_topo_find_tile( void * topo, char const * name, ulong kind_id ) {
  return fd_topo_find_tile( (fd_topo_t *)topo, name, kind_id );
}

ulong
tk_topo_find_link( void * topo, char const * name, ulong kind_id ) {
  return fd_topo_find_link( (fd_topo_t *)topo, name, kind_id );
}

void *
tk_topo_obj_laddr( void * topo, ulong obj_id ) {
  return fd_topo_obj_laddr( (fd_topo_t *)topo, obj_id );
}

/* Returns the fd_wksp_t* backing a joined workspace, so callers can reuse
   Tickoni's existing c_abi/wksp.zig gaddr/laddr helpers (wkspGaddr in
   particular, to convert a fd_topo_obj_laddr result back into the gaddr
   form LaunchSpec/LinkHandles already carry) instead of duplicating them
   here. NULL if the workspace hasn't been joined yet. */
void *
tk_topo_wksp_ptr( void * topo, ulong wksp_idx ) {
  return ((fd_topo_t *)topo)->workspaces[ wksp_idx ].wksp;
}

/* V1.14.S8.T12 finding 3: fd_topo_create_workspace/fd_topo_join_workspace
   hard-require huge/gigantic pages (fd_topob_finish computes page_sz from
   topo->max_page_size and asserts it's FD_SHMEM_HUGE_PAGE_SZ or
   FD_SHMEM_GIGANTIC_PAGE_SZ) — exactly the hugetlbfs/root requirement
   Tickoni's V1.14.S1 deliberately avoided (see c_abi/wksp.zig's module
   doc). fd_topob_finish's *offset/footprint* computation is otherwise
   page-size-independent generic layout math, so Tickoni reuses that part
   and backs the memory with its own normal-page wksp (wkspNewNamed) by
   injecting the already-attached fd_wksp_t* here instead of calling
   fd_topo_create_workspace/fd_topo_join_workspace at all.
   tk_topo_wksp_footprint/part_max below let the caller size that
   wkspNewNamed call off fd_topob_finish's real computed values instead
   of a hand-picked constant. */
void
tk_topo_wksp_set_ptr( void * topo, ulong wksp_idx, void * wksp_ptr ) {
  ((fd_topo_t *)topo)->workspaces[ wksp_idx ].wksp = (fd_wksp_t *)wksp_ptr;
}

ulong
tk_topo_wksp_footprint( void * topo, ulong wksp_idx ) {
  return ((fd_topo_t *)topo)->workspaces[ wksp_idx ].total_footprint;
}

ulong
tk_topo_wksp_part_max( void * topo, ulong wksp_idx ) {
  return ((fd_topo_t *)topo)->workspaces[ wksp_idx ].part_max;
}

/* V1.14.S8.T4: fd_topob_tile() never sets allow_shutdown (defaults to 0
   via fd_topob_new's zero-init). fd_topo_run_tile treats a clean run()
   return as a fatal error unless it's 1 — Tickoni tiles do exit
   gracefully after their bounded work, unlike a Solana validator tile
   that runs forever, so the caller must set this explicitly. */
void
tk_topo_tile_set_allow_shutdown( void * topo, ulong tile_id, int allow ) {
  ((fd_topo_t *)topo)->tiles[ tile_id ].allow_shutdown = allow;
}

void *
tk_topo_tile_ptr( void * topo, ulong tile_id ) {
  return &((fd_topo_t *)topo)->tiles[ tile_id ];
}

/* Forward declaration — defined in fd_topob.c as a Tickoni-owned
   replacement for the old env-var path.  The header is upstream
   Firedancer and this function is Tickoni-specific, so we declare
   it extern here rather than modifying the header. */
extern void fd_topob_set_kind_id_offset( ulong offset );

void
tk_topob_set_kind_id_offset( ulong offset ) {
  fd_topob_set_kind_id_offset( offset );
}
