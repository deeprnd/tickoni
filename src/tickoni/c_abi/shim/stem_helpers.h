/* stem_helpers.h — Shared Firedancer stem tile infrastructure helpers.

   Reusable patterns extracted from the Tickoni stem tiles. Runtime helpers
   are static inline; the run-tile accessor macro emits each tile's existing
   external ABI definitions in its owning translation unit. No global state,
   no shared function table.

   Tiles still define their own ctx struct, callbacks, and domain logic.
   This header provides the boilerplate that is identical across all
   Tickoni stem tiles: ctx retrieval, wksp derivation, CNC lookup,
   event-count gating, progress publishing, and run-tile ABI accessors.

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
      make.  The credit gate reserves exactly STEM_BURST slots per iteration;
      a second publish in the same iteration spends a credit the tile does
      not hold and can overrun the downstream consumer.

   A sink tile (out_cnt == 0, e.g. tkaudt) follows the same contract and
   simply ends AFTER_FRAG without publishing.  out_cnt alone decides the
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

/* ─── DURING_FRAG validation preamble ───

   Common checks at the top of every DURING_FRAG that consumes PaymentMessage:
   1. Empty fragment check
   2. Fragment size check (must match PAYMENT_MSG_SIZE)
   3. Workspace initialized check
   4. Chunk-to-gaddr conversion

   Usage (at the top of DURING_FRAG):
     if (!stk_validate_frag(sz, PAYMENT_MSG_SIZE, ctx->wksp)) { return; }
     PaymentMessage const * msg = stk_chunk_to_gaddr(ctx->wksp, chunk);

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
