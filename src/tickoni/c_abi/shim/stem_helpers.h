/* stem_helpers.h — Shared Firedancer stem tile infrastructure helpers.

   Reusable patterns extracted from the Tickoni stem tiles. Runtime helpers
   are static inline; the run-tile accessor macro emits each tile's existing
   external ABI definitions in its owning translation unit. No global state,
   no shared function table.

   Tiles still define their own ctx struct, callbacks, and domain logic.
   This header provides the boilerplate that is identical across all
   Tickoni stem tiles: ctx retrieval, wksp derivation, CNC lookup,
   event-count gating, progress publishing, CNC liveness (RUN + heartbeat),
   and run-tile ABI accessors.

   Usage: #include "stem_helpers.h" at the top of each tk_*_stem.c file.
*/
#ifndef __STEM_HELPERS_H__
#define __STEM_HELPERS_H__

/* ─── Callback contract (MANDATORY for every tk_*_stem.c) ───

   fd_stem re-checks the input sequence number AFTER DURING_FRAG returns
   (fd_stem.c, the `seq_test != seq_found` branch) and abandons the frag if
   the producer overran the reader.  DURING_FRAG therefore runs on data that
   may be torn, and anything it commits cannot be taken back.

   1. DURING_FRAG stages, and nothing else.  Clear the staging-valid flag
      first, validate via stk_validate_frag, copy out of the input dcache
      into tile-local scratch, and compute only pure functions of that copy
      (hashes, framing verdicts).  No counters, no table/ring writes, no
      stk_publish_counter, no STK_EVENT_EXHAUSTED, no fd_stem_publish.

   2. AFTER_FRAG commits.  It is the first callback reached after the overrun
      re-check, so it is the only point at which the frag is known intact.
      State mutation, counters, stk_publish_counter, STK_EVENT_EXHAUSTED and
      fd_stem_publish all belong here.

   3. AFTER_CREDIT is NOT defined unless the tile has frag-independent work
      (a timer, a backlog drain).  Never as a second "safety" publish path:
      SHOULD_SHUTDOWN is evaluated at the TOP of the stem loop, before
      AFTER_CREDIT, so a tile that gates shutdown on its own progress and
      publishes in AFTER_CREDIT silently drops its final event.

   4. STEM_BURST == the maximum fd_stem_publish calls one loop iteration can
      make to any ONE reliable output link.  The credit gate reserves exactly
      STEM_BURST slots per iteration; a second publish to the same reliable
      link in the same iteration spends a credit the tile does not hold and
      can overrun the downstream consumer.  Credits are accounted per output
      and only for outputs that have a reliable consumer (fd_stem_publish), so
      a publish to an UNRELIABLE output, such as the diagnostic link to tkdiag
      (stem_diag.h), draws none and does not raise STEM_BURST.

   A sink tile (no pipeline output, e.g. tkaudt) follows the same contract and
   simply ends AFTER_FRAG without a pipeline publish; its only publish is the
   optional diagnostic fragment.  The pipeline output count alone decides the
   shape of the tile, not which callbacks it happens to define.

   Rationale and the full statement of this contract live in
   doc/execution/contribution/tickoni.md, "fd_stem Callback Contract".
*/

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"

/* ─── Context retrieval ───

   Retrieve ctx from scratch. Takes the ctx type and alignment constant as
   parameters (via macro) so the result type is correct.

   Usage:
     tknorm_ctx_t * ctx = STK_GET_CTX(tknorm_ctx_t, scratch, TKNORM_CTX_ALIGN);
     tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);
*/
#define STK_GET_CTX(ctx_type, scratch, align) \
    ((ctx_type *)fd_ulong_align_up((ulong)(scratch), (align)))

/* ─── Workspace derivation ───

   Derive workspace pointer from a tile's input link mcache. The topology
   records which workspace each object was allocated from, and the tile's
   workspace join (fd_topo_join_tile_workspaces / its Windows shim) stores
   the local join pointer in topo->workspaces[], so fd_topo_obj_wksp_base
   returns the correct workspace for THIS process.

   fd_wksp_containing must not be used here: it relies on
   fd_shmem_join_query_by_addr, which is hard-coded to ENOENT on Windows
   (fd_shmem_windows.c), so it always returned NULL and every fragment was
   silently rejected by stk_validate_frag.

   Takes the topo, tile, and input link index (0 for single-input tiles).
   Returns the workspace pointer, or NULL if the link has no mcache.

   Usage (in privileged_init):
     ctx->wksp = stk_derive_wksp(topo, tile, 0);
*/
static inline void *
stk_derive_wksp(fd_topo_t const * topo, fd_topo_tile_t const * tile, ulong in_idx) {
    ulong in_link_id = tile->in_link_id[in_idx];
    fd_topo_link_t const * link = &topo->links[in_link_id];
    if (link->mcache_obj_id == ULONG_MAX) return NULL;
    return fd_topo_obj_wksp_base(topo, link->mcache_obj_id);
}

/* ─── CNC lookup ───

   Find the CNC object for a tile. Returns the object ID or ULONG_MAX if
   not found. The caller uses the ID to get the local address.

   Usage:
     ulong cnc_obj_id = stk_find_cnc(topo, tile->id);
     if (cnc_obj_id != ULONG_MAX) {
         ctx->cnc = fd_topo_obj_laddr(topo, cnc_obj_id);
     }
*/
extern ulong tk_topo_find_tile_obj(fd_topo_t const * topo, ulong tile_id, char const * obj_type);

static inline ulong
stk_find_cnc(fd_topo_t const * topo, ulong tile_id) {
    return tk_topo_find_tile_obj(topo, tile_id, "cnc");
}

/* ─── Event-count exhaustion check ───

   Macro version — each tile passes its own ctx pointer directly so the
   input_exhausted field is accessible. The check is only 2 lines but is
   identical across all tiles.

   Usage (in AFTER_FRAG — never DURING_FRAG; see the callback contract at
   the top of this header):
     STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->audited)
     STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->normalized + ctx->invalid)

   Sets ctx->input_exhausted = 1 when triggered.
*/
#define STK_EVENT_EXHAUSTED(ctx, event_count, total) \
    do { \
        if ((event_count) && (total) >= (event_count)) \
            (ctx)->input_exhausted = 1; \
    } while (0)

/* ─── Unprivileged init helper ───

   Common unprivileged_init pattern: find the CNC and set ctx->cnc.
   Both tkaudt and tknorm do the same thing — the only difference is
   the ctx type.

   Usage (in unprivileged_init, after ctx-specific init):
     STK_UNPRIV_INIT(topo, tile, ctx);

   The caller still handles tile-specific ctx field init (zeroing, etc.).
*/
#define STK_UNPRIV_INIT(topo, tile, ctx) \
    do { \
        ulong _cnc_obj = stk_find_cnc(topo, (ulong)(tile)->id); \
        if (_cnc_obj != ULONG_MAX) \
            (ctx)->cnc = fd_topo_obj_laddr((fd_topo_t *)topo, _cnc_obj); \
    } while (0)

/* ─── Counter publishing ───

   Publish a tile counter to its CNC app slot.  Safe no-op if cnc is NULL.
   Slot ownership per tile is declared in tile_registry.zig's
   TileEntry.counters, and supervisor.zig reads each slot back through that
   same schema — pass the index the registry assigns rather than
   hand-rolling an app[] write.

   There is deliberately no slot-0 convenience wrapper: slot 0 names a
   different counter on every tile (produced for tkings, normalized for
   tknorm, duplicates for tkdedu, audited for tkaudt), so each call site
   states which slot it writes instead of leaving it implicit.

   Usage (in AFTER_FRAG — never DURING_FRAG; see the callback contract at
   the top of this header):
     stk_publish_counter(ctx->cnc, 0UL, ctx->audited);               // app[0]
     stk_publish_counter(ctx->cnc, 1UL, ctx->invalid);               // app[1]
*/
#include "tango/cnc/fd_cnc.h"

static inline void
stk_publish_counter(void * cnc, ulong slot, ulong value) {
    if (!cnc) return;
    ulong * app = (ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc);
    if (app) app[slot] = value;
}

/* ─── CNC liveness (BOOT -> RUN + heartbeat) ───

   The supervisor classifies a tile stale only when its CNC signal reads RUN
   and its CNC heartbeat has not advanced within the stale threshold
   (supervisor.zig, refreshProcessHealth).  A stem tile that does neither is
   never eligible, so a wedged or stopped loop is indistinguishable from a
   healthy one.  EVERY tk_*_stem.c therefore defines, as its housekeeping
   callback, which fd_stem runs once per housekeeping event whether or not any
   fragment or credit is available:

     #define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) \
         stk_cnc_liveness( (ctx)->cnc )

   and #undefs it after including fd_stem.c.  Nothing else is needed: the first
   call, which is the first loop iteration, also moves the CNC BOOT -> RUN.

   Why RUN is signalled from the loop and not from the run entry: the stem's
   own setup runs before its loop, and its first call to fd_tempo_tick_per_ns
   calibrates the tick rate for about half a second.  RUN signalled earlier
   would make the tile eligible for staleness during that setup, and it would
   be classified stale against the 100 ms default before it ever looped.  From
   the loop on, the gap between housekeeping events is below 4 * STEM_LAZY
   (see doc/knowledge/tile-orchestration.md, "Health And Lifecycle").

   The transition is a compare-and-swap from BOOT, so it never overwrites a
   HALT that arrived while the tile was booting: the loop then sees the HALT at
   its next SHOULD_SHUTDOWN check and exits.  The heartbeat is written first,
   so the supervisor never sees RUN with a heartbeat from before the boot.

   Clock and units: the CNC heartbeat is Tickoni's wrapping u32 milliseconds of
   the monotonic clock, which is what the Zig supervisor compares against
   (util.process.monotonicNanos).  The helper therefore reads
   tk_monotonic_nanos() (os.c) and writes through tk_cnc_heartbeat (tango.c),
   the same functions the Zig side uses.  Never call fd_cnc_heartbeat directly
   or with fd_log_wallclock(): a different clock or unit makes the tile look
   permanently stale or permanently fresh.

   A safe no-op for a NULL cnc.

   After the heartbeat it runs the process's liveness faults (tango.c,
   tk_cnc_liveness_fault_check): test-build crash and stuck hooks the supervisor
   tests use, installed from the LaunchSpec, so no tile carries its own. */
extern int64_t tk_monotonic_nanos( void );
extern void    tk_cnc_heartbeat( fd_cnc_t * cnc, int64_t now_ns );
extern void    tk_cnc_liveness_fault_check( void );

static inline void
stk_cnc_liveness(void * cnc) {
    if (!cnc) return;
    fd_cnc_t * c = (fd_cnc_t *)cnc;
    tk_cnc_heartbeat(c, tk_monotonic_nanos());
    if (fd_cnc_signal_query(c) == FD_CNC_SIGNAL_BOOT) {
        ulong expected = FD_CNC_SIGNAL_BOOT;
        __atomic_compare_exchange_n(&c->signal, &expected, FD_CNC_SIGNAL_RUN,
                                    0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
    }
    /* Test-build crash/stuck faults, if installed (tango.c); a no-op otherwise. */
    tk_cnc_liveness_fault_check();
}

/* ─── DURING_FRAG validation preamble ───

   Common checks at the top of every DURING_FRAG that consumes a TkEvent:
   1. Empty fragment check
   2. Fragment size check (must match TK_EVENT_SIZE)
   3. Workspace initialized check
   4. Chunk-to-gaddr conversion

   Usage (at the top of DURING_FRAG):
     if (!stk_validate_frag(sz, TK_EVENT_SIZE, ctx->wksp)) { return; }
     TkEvent const * msg = stk_chunk_to_gaddr(ctx->wksp, chunk);

   Returns 1 if fragment is valid (caller should continue), 0 if should return.

   NOTE: The including tile MUST #include "firedancer.h" BEFORE this header
   — these helpers depend on FD_UNLIKELY and FD_CHUNK_ALIGN from it.
*/
#include <stddef.h>
#include <stdint.h>

static inline int
stk_validate_frag(ulong sz, ulong expected_sz, void * wksp) {
    if (FD_UNLIKELY(!sz)) return 0;
    if (FD_UNLIKELY(sz != expected_sz)) return 0;
    if (FD_UNLIKELY(!wksp)) return 0;
    return 1;
}

static inline void *
stk_chunk_to_gaddr(void * wksp, ulong chunk) {
    return fd_wksp_laddr_fast(wksp, chunk * FD_CHUNK_ALIGN);
}

/* ─── Links: the dcache side of every input and output ───

   One pattern for every link a stem tile reads or writes.  Every link
   between tiles is reliable: fd_stem publishes to it only while every
   reliable consumer holds credits, so a producer waits and never drops.  The
   only unreliable links are the diagnostic links to tkdiag (stem_diag.h);
   they use the same cursor, and fd_stem_publish charges them no credit.  So
   no tile decides, publish by publish, whether to drop.

   stk_link_in_t   an input's dcache: its workspace (from the input's mcache,
                   see stk_derive_wksp) and its valid chunk range.
   stk_link_out_t  an output's dcache: its workspace, chunk range and the
                   next chunk to write.

   Both init functions fail closed (FD_LOG_ERR) on a link with no dcache, an
   MTU below what the tile publishes or reads, or an unjoined workspace.  Call
   them from unprivileged_init, after the workspaces are joined.

   Usage:
     unprivileged_init:  stk_link_in_init ( &ctx->in,  topo, tile, 0UL, TK_EVENT_SIZE );
                         stk_link_out_init( &ctx->out, topo, tile, 0UL, TK_EVENT_SIZE );
     DURING_FRAG:        if( !stk_link_in_contains( &ctx->in, chunk ) ) return;
                         memcpy( &ctx->stage, stk_link_in_laddr( &ctx->in, chunk ), sz );
     AFTER_FRAG:         stk_link_out_publish( &ctx->out, stem, 0UL, sig, &ctx->stage, sz );

   A tile that builds its fragment in place writes to stk_link_out_laddr and
   then calls stk_link_out_commit; one that publishes a multipart message
   passes each fragment's own ctl to stk_link_out_commit. */
#include "disco/stem/fd_stem.h"
#include "tango/dcache/fd_dcache.h"
#include <string.h>

typedef struct {
    void * wksp;
    ulong  chunk0;
    ulong  wmark;
} stk_link_in_t;

typedef struct {
    void * wksp;
    ulong  chunk0;
    ulong  wmark;
    ulong  chunk;     /* next chunk to write */
} stk_link_out_t;

static inline void
stk_link_in_init( stk_link_in_t *         in,
                  fd_topo_t const *       topo,
                  fd_topo_tile_t const *  tile,
                  ulong                   in_idx,
                  ulong                   min_mtu ) {
    fd_topo_link_t const * link = &topo->links[ tile->in_link_id[ in_idx ] ];
    if( FD_UNLIKELY( !link->dcache || link->mtu<min_mtu ) )
        FD_LOG_ERR(( "%s: input link %lu has no dcache or an mtu %lu below %lu",
                     tile->name, in_idx, (ulong)link->mtu, min_mtu ));
    in->wksp = stk_derive_wksp( topo, tile, in_idx );
    if( FD_UNLIKELY( !in->wksp ) )
        FD_LOG_ERR(( "%s: input link %lu workspace is not joined", tile->name, in_idx ));
    in->chunk0 = fd_dcache_compact_chunk0( in->wksp, link->dcache );
    in->wmark  = fd_dcache_compact_wmark ( in->wksp, link->dcache, link->mtu );
}

/* 1 if `chunk` lies in the input's dcache; a fragment outside it is not read. */
static inline int
stk_link_in_contains( stk_link_in_t const * in, ulong chunk ) {
    return chunk>=in->chunk0 && chunk<=in->wmark;
}

static inline void const *
stk_link_in_laddr( stk_link_in_t const * in, ulong chunk ) {
    return stk_chunk_to_gaddr( in->wksp, chunk );
}

static inline void
stk_link_out_init( stk_link_out_t *        out,
                   fd_topo_t const *       topo,
                   fd_topo_tile_t const *  tile,
                   ulong                   out_idx,
                   ulong                   min_mtu ) {
    fd_topo_link_t const * link = &topo->links[ tile->out_link_id[ out_idx ] ];
    if( FD_UNLIKELY( !link->dcache || link->mtu<min_mtu ) )
        FD_LOG_ERR(( "%s: output link %lu has no dcache or an mtu %lu below %lu",
                     tile->name, out_idx, (ulong)link->mtu, min_mtu ));
    out->wksp = fd_topo_obj_wksp_base( topo, link->dcache_obj_id );
    if( FD_UNLIKELY( !out->wksp ) )
        FD_LOG_ERR(( "%s: output link %lu workspace is not joined", tile->name, out_idx ));
    out->chunk0 = fd_dcache_compact_chunk0( out->wksp, link->dcache );
    out->wmark  = fd_dcache_compact_wmark ( out->wksp, link->dcache, link->mtu );
    out->chunk  = out->chunk0;
}

/* Where the next fragment on this output is written. */
static inline void *
stk_link_out_laddr( stk_link_out_t const * out ) {
    return fd_chunk_to_laddr( out->wksp, out->chunk );
}

/* Publishes the `sz` bytes already written at stk_link_out_laddr as output
   `out_idx`'s next fragment, with control bits `ctl`, and advances to the
   next chunk. */
static inline void
stk_link_out_commit( stk_link_out_t *     out,
                     fd_stem_context_t *  stem,
                     ulong                out_idx,
                     ulong                sig,
                     ulong                sz,
                     ulong                ctl ) {
    fd_stem_publish( stem, out_idx, sig, out->chunk, sz, ctl, 0UL, 0UL );
    out->chunk = fd_dcache_compact_next( out->chunk, sz, out->chunk0, out->wmark );
}

/* Copies `sz` bytes from `src` and publishes them as one whole fragment
   (SOM and EOM). */
static inline void
stk_link_out_publish( stk_link_out_t *     out,
                      fd_stem_context_t *  stem,
                      ulong                out_idx,
                      ulong                sig,
                      void const *         src,
                      ulong                sz ) {
    memcpy( stk_link_out_laddr( out ), src, sz );
    stk_link_out_commit( out, stem, out_idx, sig, sz, fd_frag_meta_ctl( 0UL, 1, 1, 0 ) );
}

/* ─── Run-tile ABI accessors ───

   Define the read-only C ABI wrappers shared by Tickoni stem tiles.  Invoke
   this once, after the tile's fd_topo_run_tile_t descriptor is defined.

   The explicit scratch accessor names preserve the existing public ABI even
   though the older tiles use different naming conventions.  Tile-specific
   descriptor initialization, scratch layout, and runtime parameters remain
   in the owning translation unit.

   Usage:
     STK_DEFINE_RUN_TILE_ACCESSORS(
         tk_get_norm,
         TK_NORM_RUN,
         tknorm_tile_scratch_align,
         tknorm_tile_scratch_footprint
     )
*/
#define STK_DEFINE_RUN_TILE_ACCESSORS(api_prefix, run_descriptor, scratch_align_fn, scratch_footprint_fn) \
    fd_topo_run_tile_t const *                                                                    \
    api_prefix##_run_tile( void ) {                                                               \
        return &(run_descriptor);                                                                 \
    }                                                                                             \
                                                                                                  \
    ulong                                                                                         \
    scratch_align_fn( void ) {                                                                    \
        return (run_descriptor).scratch_align();                                                   \
    }                                                                                             \
                                                                                                  \
    ulong                                                                                         \
    scratch_footprint_fn( void ) {                                                                \
        return (run_descriptor).scratch_footprint( NULL );                                         \
    }                                                                                             \
                                                                                                  \
    char const *                                                                                  \
    api_prefix##_run_name( void ) {                                                               \
        return (run_descriptor).name;                                                             \
    }                                                                                             \
                                                                                                  \
    void *                                                                                        \
    api_prefix##_run_run( void ) {                                                                \
        return (void *)(run_descriptor).run;                                                      \
    }                                                                                             \
                                                                                                  \
    void *                                                                                        \
    api_prefix##_run_scratch_align( void ) {                                                      \
        return (void *)(run_descriptor).scratch_align;                                            \
    }                                                                                             \
                                                                                                  \
    void *                                                                                        \
    api_prefix##_run_scratch_footprint( void ) {                                                  \
        return (void *)(run_descriptor).scratch_footprint;                                        \
    }                                                                                             \
                                                                                                  \
    void *                                                                                        \
    api_prefix##_run_privileged_init( void ) {                                                    \
        return (void *)(run_descriptor).privileged_init;                                          \
    }                                                                                             \
                                                                                                  \
    void *                                                                                        \
    api_prefix##_run_unprivileged_init( void ) {                                                  \
        return (void *)(run_descriptor).unprivileged_init;                                        \
    }

#endif /* __STEM_HELPERS_H__ */
