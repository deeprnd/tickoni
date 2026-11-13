/* tk_dedu_stem.c — Stem fd_stem tile for tkdedu.

   Tile behavior:
   - DURING_FRAG: read PaymentMessage from input dcache, copy to scratch,
     increment pipeline_hops, skip dedup for malformed_drop, linear scan
     seen_keys/seen_hashes for duplicate, mark + forward as-is
   - AFTER_CREDIT: if output_ready, write to pre-computed output dcache slot,
     publish to output dcache via fd_stem_publish, advance chunk, reset output_ready
   - SHOULD_SHUTDOWN: CNC HALT + event_count exhaustion

   Uses stem_helpers.h for shared boilerplate:
   STK_GET_CTX, stk_derive_wksp, STK_UNPRIV_INIT,
   stk_validate_frag, stk_chunk_to_gaddr, STK_EVENT_EXHAUSTED,
   stk_publish_progress
*/

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>
#include <stdlib.h>

/* ─── Context ───
   tkdedu_ctx_t MUST be defined BEFORE STEM_CALLBACK_CONTEXT_TYPE
   so fd_stem.c sees a complete type when it expands.
*/
typedef struct {
    /* Counters */
    uint64_t duplicates;
    uint64_t processed;

    /* Dedup state — scratch-allocated arrays */
    uint64_t seen_count;
    uint64_t *seen_keys;
    uint64_t *seen_hashes;

    /* Output state (set in during_frag, consumed in after_credit) */
    int      output_ready;
    uint64_t output_sz;

    /* Output dcache allocation state (computed in unprivileged_init) */
    void *   out_wksp;
    ulong    out_chunk0;
    ulong    out_wmark;
    ulong    out_chunk;

    /* CNC reference for shutdown detection */
    void     *cnc;

    /* Tile pointer */
    fd_topo_tile_t const *tile;

    /* Workspace pointer for input dcache reads */
    void *wksp;

    /* Scratch-allocated output PaymentMessage buffer */
    PaymentMessage *output_msg;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;
} tkdedu_ctx_t;

/* Forward declarations */
static void tkdedu_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdedu_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkdedu_during_frag( tkdedu_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                 ulong chunk, ulong sz, ulong ctl );
static void tkdedu_after_credit( tkdedu_ctx_t * ctx, fd_stem_context_t * stem,
                                 int * opt_poll_in, int * charge_busy );
static void tkdedu_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define TKDEDU_CTX_ALIGN alignof(tkdedu_ctx_t)
#define TKDEDU_OUTPUT_CAPACITY 1

/* Generate a dedu-specific static stem specialization. */
#define STEM_NAME                         tkdedu
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkdedu_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKDEDU_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG         tkdedu_during_frag
#define STEM_CALLBACK_AFTER_CREDIT        tkdedu_after_credit
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_CREDIT
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint ───

   STEM_CALLBACK generates STEM_(scratch_footprint)( ulong in_cnt, ... )
   and STEM_(scratch_align)( void ).  We provide the tile-specific variant
   (footprint_tile) and a no-argument wrapper (tile_scratch_footprint)
   for topob.c so it never needs the full fd_topo_tile_t definition.
*/

static ulong
tkdedu_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    /* Context + alignment */
    ulong footprint = fd_ulong_align_up( sizeof(tkdedu_ctx_t), TKDEDU_CTX_ALIGN );

    /* Dedup arrays: N entries each (N determined at runtime from env).
       Conservative estimate: default event_count = 10000 (matches
       supervisor config). */
    ulong event_count = 10000;
    {
        const char *env = getenv("TKDEDU_EVENT_COUNT");
        if (env) {
            event_count = strtoull(env, NULL, 10);
            if (event_count == 0) event_count = 10000;
        }
    }

    /* seen_keys and seen_hashes follow aligned context */
    ulong arr_align = fd_ulong_align_up( footprint, alignof(uint64_t) );
    footprint = arr_align + sizeof(uint64_t) * event_count * 2;

    /* output_msg follows aligned arrays */
    footprint = fd_ulong_align_up( footprint, alignof(PaymentMessage) );
    footprint += sizeof(PaymentMessage) * TKDEDU_OUTPUT_CAPACITY;

    return footprint;
}

/* ─── Callbacks ─── */

static void
tkdedu_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdedu_ctx_t * ctx = STK_GET_CTX(tkdedu_ctx_t, scratch, TKDEDU_CTX_ALIGN);

    ctx->duplicates = 0;
    ctx->processed = 0;
    ctx->seen_count = 0;
    ctx->output_ready = 0;
    ctx->cnc = NULL;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;
    ctx->out_wksp = NULL;
    ctx->out_chunk0 = 0;
    ctx->out_wmark = 0;
    ctx->out_chunk = 0;

    /* Derive workspace pointer from input mcache */
    ctx->wksp = stk_derive_wksp(topo, tile, 0);

    /* Read event_count from environment */
    {
        const char *env = getenv("TKDEDU_EVENT_COUNT");
        if (env) {
            ctx->event_count = strtoull(env, NULL, 10);
            FD_LOG_NOTICE(( "tkdedu: event_count=%lu from env", (unsigned long)ctx->event_count ));
        }
    }

    /* Allocate dedup arrays from scratch */
    ulong arr_align = fd_ulong_align_up( (ulong)ctx + sizeof(tkdedu_ctx_t), alignof(uint64_t) );
    uint64_t * arr = (uint64_t *)arr_align;
    ctx->seen_keys = arr;
    ctx->seen_hashes = arr + ctx->event_count;

    /* Point output_msg at scratch block after arrays */
    ulong out_align = fd_ulong_align_up( (ulong)arr + sizeof(uint64_t) * ctx->event_count * 2,
                                          alignof(PaymentMessage) );
    ctx->output_msg = (PaymentMessage *)out_align;

    FD_LOG_NOTICE(( "tkdedu: privileged init ctx=%p seen_keys=%p seen_hashes=%p output=%p wksp=%p",
                    ctx, ctx->seen_keys, ctx->seen_hashes, ctx->output_msg, ctx->wksp ));
}

static void
tkdedu_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdedu_ctx_t * ctx = STK_GET_CTX(tkdedu_ctx_t, scratch, TKDEDU_CTX_ALIGN);

    /* Shared boilerplate: find CNC and set ctx->cnc */
    STK_UNPRIV_INIT(topo, tile, ctx);

    /* Compute output dcache workspace fields for after_credit publish.
       Matches the tknorm pattern: get the output link, find its dcache
       object, compute chunk0/wmark, start at chunk0. */
    if (FD_UNLIKELY(tile->out_cnt != 1UL))
        FD_LOG_ERR(( "tkdedu: expected exactly one output link, found %lu", tile->out_cnt ));
    fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[0]];
    if (FD_UNLIKELY(!out_link->dcache || out_link->mtu < PAYMENT_MSG_SIZE))
        FD_LOG_ERR(( "tkdedu: invalid output dcache or mtu %lu", out_link->mtu ));
    ctx->out_wksp = fd_topo_obj_wksp_base(topo, out_link->dcache_obj_id);
    if (FD_UNLIKELY(!ctx->out_wksp))
        FD_LOG_ERR(( "tkdedu: output workspace is not joined" ));
    ctx->out_chunk0 = fd_dcache_compact_chunk0(ctx->out_wksp, out_link->dcache);
    ctx->out_wmark = fd_dcache_compact_wmark(ctx->out_wksp, out_link->dcache, out_link->mtu);
    ctx->out_chunk = ctx->out_chunk0;

    FD_LOG_NOTICE(( "tkdedu: unprivileged init tile_id=%lu cnc=%p out_chunk0=%lu out_wmark=%lu",
                    tile->id, ctx->cnc, ctx->out_chunk0, ctx->out_wmark ));
}

static void
tkdedu_during_frag( tkdedu_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    /* Shared boilerplate: empty check, size check, wksp check, chunk→gaddr */
    if (!stk_validate_frag(sz, PAYMENT_MSG_SIZE, ctx->wksp))
        return;
    PaymentMessage const * msg_in = stk_chunk_to_gaddr(ctx->wksp, chunk);

    /* Copy input to output buffer */
    memcpy(ctx->output_msg, msg_in, sizeof(PaymentMessage));
    ctx->output_msg->pipeline_hops += 1;

    /* Dedup check: skip for malformed_drop (tknorm already rejected it) */
    if (ctx->output_msg->decision != (uint8_t)POLICY_MALFORMED_DROP) {
        /* Linear scan for duplicate */
        int is_dup = 0;
        for (uint64_t i = 0; i < ctx->seen_count; i++) {
            if (ctx->seen_keys[i] == ctx->output_msg->raw.idempotency_key &&
                ctx->seen_hashes[i] == ctx->output_msg->event_hash) {
                is_dup = 1;
                break;
            }
        }

        if (is_dup) {
            ctx->output_msg->duplicate = 1;
            ctx->duplicates += 1;
        } else {
            /* Remember this (key, hash) pair */
            ctx->seen_keys[ctx->seen_count] = ctx->output_msg->raw.idempotency_key;
            ctx->seen_hashes[ctx->seen_count] = ctx->output_msg->event_hash;
            ctx->seen_count += 1;
        }
    }

    /* Shared boilerplate: event-count gating */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->processed);

    /* Mark output ready */
    ctx->output_ready = 1;
    ctx->output_sz = PAYMENT_MSG_SIZE;

    /* Shared boilerplate: progress publishing */
    stk_publish_progress(ctx->cnc, ctx->processed);

    ctx->processed += 1;
}

static void
tkdedu_after_credit( tkdedu_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    (void)opt_poll_in;

    if (ctx->output_ready) {
        ulong out_chunk = ctx->out_chunk;
        void * dst = fd_chunk_to_laddr(ctx->out_wksp, out_chunk);
        memcpy(dst, ctx->output_msg, ctx->output_sz);

        /* Publish to tkpoly: (stem, out_idx, sig, chunk, sz, ctl, tsorig, tspub) */
        fd_stem_publish(stem, 0UL, 0UL, out_chunk, ctx->output_sz, 0UL, 0UL, 0UL);
        ctx->out_chunk = fd_dcache_compact_next(
            out_chunk,
            ctx->output_sz,
            ctx->out_chunk0,
            ctx->out_wmark
        );
        ctx->output_ready = 0;
    }

    *charge_busy = 0;
}

/* ─── Run entry point ─── */

static void
tkdedu_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkdedu_ctx_t * ctx = (tkdedu_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKDEDU_CTX_ALIGN );

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if (FD_UNLIKELY(cnc_obj_id == ULONG_MAX))
        FD_LOG_ERR(( "tkdedu: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkdedu_run(topo, tile);  /* stem_run loop */

    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_DEDU_RUN = {
    .name                     = TILE_ID_TKDEDU,
    .keep_host_networking     = 0,
    .allow_connect            = 0,
    .allow_renameat           = 0,
    .rlimit_file_cnt          = 0,
    .rlimit_address_space     = 0,
    .rlimit_data              = 0,
    .rlimit_nproc             = 0,
    .for_tpool                = 0,
    .max_event_sz             = NULL,
    .populate_allowed_seccomp = NULL,
    .populate_allowed_fds     = NULL,
    .scratch_align            = tkdedu_scratch_align,
    .scratch_footprint        = tkdedu_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tkdedu_privileged_init,
    .unprivileged_init        = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tkdedu_unprivileged_init,
    .run                      = (void (*)(fd_topo_t *, fd_topo_tile_t *))tkdedu_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

fd_topo_run_tile_t const *
tk_get_dedu_run_tile( void ) {
    return &TK_DEDU_RUN;
}

/* Wrapper for topob.c: query scratch footprint without needing a
   fd_topo_tile_t pointer. Delegates to TK_DEDU_RUN.scratch_footprint
   to avoid conflicting with the STEM-generated macro function. */
ulong
tkdedu_tile_scratch_footprint( void ) {
    return TK_DEDU_RUN.scratch_footprint( NULL );
}

/* Field accessors for integration/test_tkdedu_integration.zig.
   These avoid Zig-C struct layout mismatch by reading individual fields. */
char const *
tk_get_dedu_run_name( void ) {
    return TK_DEDU_RUN.name;
}

void *
tk_get_dedu_run_run( void ) {
    return (void *)TK_DEDU_RUN.run;
}

void *
tk_get_dedu_run_scratch_align( void ) {
    return (void *)TK_DEDU_RUN.scratch_align;
}

void *
tk_get_dedu_run_scratch_footprint( void ) {
    return (void *)TK_DEDU_RUN.scratch_footprint;
}

void *
tk_get_dedu_run_privileged_init( void ) {
    return (void *)TK_DEDU_RUN.privileged_init;
}

void *
tk_get_dedu_run_unprivileged_init( void ) {
    return (void *)TK_DEDU_RUN.unprivileged_init;
}
