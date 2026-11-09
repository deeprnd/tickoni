/* stem_helpers.h — Shared Firedancer stem tile infrastructure helpers.

   Reusable patterns extracted from tkaudt and consumed by tknorm (and future
   stem tiles). Each helper is static inline — included in every translation
   unit that needs it. No global state, no shared function table.

   Tiles still define their own ctx struct, callbacks, and domain logic.
   This header provides the boilerplate that is identical across all
   Tickoni stem tiles: ctx retrieval, wksp derivation, CNC lookup,
   event-count gating, and progress publishing.

   Usage: #include "stem_helpers.h" at the top of each tk_*_stem.c file.
*/
#ifndef __STEM_HELPERS_H__
#define __STEM_HELPERS_H__

#include "../../../disco/topo/fd_topo.h"
#include "../../../util/wksp/fd_wksp.h"

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

   Derive workspace pointer from a tile's input link mcache. The mcache is
   set by fd_topo_fill_tile as a real local address in this tile process;
   fd_wksp_containing returns the correct workspace for THIS process.

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
    void * mcache = fd_topo_obj_laddr((fd_topo_t *)topo, link->mcache_obj_id);
    return (void *)fd_wksp_containing(mcache);
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

   Usage (in DURING_FRAG):
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

/* ─── Progress publishing ───

   Publish a progress value to CNC app[0]. Safe no-op if cnc is NULL.

   Usage (in DURING_FRAG):
     stk_publish_progress(ctx->cnc, ctx->audited);
     stk_publish_progress(ctx->cnc, ctx->normalized + ctx->invalid);
*/
#include "../../../tango/cnc/fd_cnc.h"

static inline void
stk_publish_progress(void * cnc, ulong value) {
    if (!cnc) return;
    ulong * app = (ulong *)fd_cnc_app_laddr((fd_cnc_t *)cnc);
    if (app) app[0] = value;
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

#endif /* __STEM_HELPERS_H__ */
