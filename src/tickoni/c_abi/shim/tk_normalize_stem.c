/* tk_normalize_stem.c — Stem fd_stem tile for tknorm.

   Tile behavior:
   - DURING_FRAG: read PaymentMessage from input dcache, validate framing
     (currency=USD, amount_cents>0, not malformed), compute stable
     event hash, stamp decision/decided_by, track counters, set output_ready
   - AFTER_CREDIT: if output_ready, publish to output dcache via
     fd_stem_publish, reset output_ready
   - SHOULD_SHUTDOWN: CNC HALT + idle threshold + event_count exhaustion

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
   tknorm_ctx_t MUST be defined BEFORE STEM_CALLBACK_CONTEXT_TYPE
   so fd_stem.c sees a complete type when it expands.
*/
typedef struct {
    /* Counters */
    uint64_t normalized;
    uint64_t invalid;

    /* Output state (set in during_frag, consumed in after_credit) */
    int      output_ready;
    uint64_t output_sz;
    uint64_t output_chunk;

    /* Idle threshold tracking */
    long     idle_ticks;

    /* CNC reference for shutdown detection */
    void     *cnc;

    /* Tile pointer */
    fd_topo_tile_t const *tile;

    /* Workspace pointer for dcache writes */
    void *wksp;

    /* Scratch-allocated output PaymentMessage buffer */
    PaymentMessage *output_msg;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;

    /* Output dcache allocation state */
    void *   out_wksp;
    ulong    out_chunk0;
    ulong    out_wmark;
    ulong    out_chunk;
} tknorm_ctx_t;

#define TKNORM_CTX_ALIGN alignof(tknorm_ctx_t)
#define TKNORM_OUTPUT_CAPACITY 1

/* Forward declarations */
static void tknorm_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tknorm_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tknorm_during_frag( tknorm_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                 ulong chunk, ulong sz, ulong ctl );
static void tknorm_after_credit( tknorm_ctx_t * ctx, fd_stem_context_t * stem,
                                 int * opt_poll_in, int * charge_busy );
static void tknorm_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Generate a norm-specific static stem specialization. */
#define STEM_NAME                         tknorm
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tknorm_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKNORM_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG         tknorm_during_frag
#define STEM_CALLBACK_AFTER_CREDIT        tknorm_after_credit
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->idle_ticks > 10000L ) || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/metrics/fd_metrics.h"
#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_CREDIT
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── FNV-1a 64-bit hash — matches runtime.zig:stableEventHash exactly ───
   The Zig code uses AUDIT_INITIAL_HASH (0ULL) as seed, NOT the
   standard FNV offset basis.  Field order: idempotency_key(u64),
   account_id(u32), amount_cents(i64→u64 bitcast), currency(3 bytes). */
static uint64_t
tknorm_stable_event_hash( RawPayment const * raw ) {
    uint64_t h = 0ULL;  /* AUDIT_INITIAL_HASH == 0 in audit_consts.h */

    /* Hash idempotency_key (u64, byte by byte, little-endian) */
    { uint64_t x = raw->idempotency_key; for (int i = 0; i < 8; i++) { h ^= (x & 0xff); h *= 0x100000001b3ULL; x >>= 8; } }

    /* Hash account_id (u32, byte by byte, little-endian) */
    { uint32_t x = raw->account_id; for (int i = 0; i < 4; i++) { h ^= (x & 0xff); h *= 0x100000001b3ULL; x >>= 8; } }

    /* Hash amount_cents (i64 → u64 bitcast, byte by byte, little-endian) */
    { uint64_t x = (uint64_t)(int64_t)raw->amount_cents; for (int i = 0; i < 8; i++) { h ^= (x & 0xff); h *= 0x100000001b3ULL; x >>= 8; } }

    /* Hash currency (3 bytes) */
    for (int i = 0; i < 3; i++) { h ^= raw->currency[i]; h *= 0x100000001b3ULL; }

    return h;
}

/* ─── Scratch footprint ─── */

static ulong
tknorm_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tknorm_ctx_t), TKNORM_CTX_ALIGN );
    /* output_msg follows aligned context */
    footprint = fd_ulong_align_up( footprint, alignof(PaymentMessage) );
    footprint += sizeof(PaymentMessage) * TKNORM_OUTPUT_CAPACITY;
    return footprint;
}

/* ─── Callbacks ─── */

static void
tknorm_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = STK_GET_CTX(tknorm_ctx_t, scratch, TKNORM_CTX_ALIGN);

    ctx->normalized = 0;
    ctx->invalid = 0;
    ctx->output_ready = 0;
    ctx->idle_ticks = 0;
    ctx->cnc = NULL;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;
    ctx->out_wksp = NULL;
    ctx->out_chunk0 = 0;
    ctx->out_wmark = 0;
    ctx->out_chunk = 0;

    /* Derive workspace pointer from input mcache */
    ctx->wksp = stk_derive_wksp(topo, tile, 0);

    /* Point output_msg at scratch block after context */
    ulong ctx_end = fd_ulong_align_up( (ulong)ctx + sizeof(tknorm_ctx_t), alignof(PaymentMessage) );
    ctx->output_msg = (PaymentMessage *)ctx_end;

    /* Read event_count from environment */
    {
        const char *env = getenv("TKNORM_EVENT_COUNT");
        if (env) {
            ctx->event_count = strtoull(env, NULL, 10);
            FD_LOG_NOTICE(( "tknorm: event_count=%lu from env", (unsigned long)ctx->event_count ));
        }
    }

    FD_LOG_NOTICE(( "tknorm: privileged init ctx=%p output=%p wksp=%p",
                    ctx, ctx->output_msg, ctx->wksp ));
}

static void
tknorm_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = STK_GET_CTX(tknorm_ctx_t, scratch, TKNORM_CTX_ALIGN);

    /* Shared boilerplate: find CNC and set ctx->cnc */
    STK_UNPRIV_INIT(topo, tile, ctx);

    if (FD_UNLIKELY(tile->out_cnt != 1UL))
        FD_LOG_ERR(( "tknorm: expected exactly one output link, found %lu", tile->out_cnt ));
    fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[0]];
    if (FD_UNLIKELY(!out_link->dcache || out_link->mtu < PAYMENT_MSG_SIZE))
        FD_LOG_ERR(( "tknorm: invalid output dcache or mtu %lu", out_link->mtu ));
    ctx->out_wksp = fd_topo_obj_wksp_base(topo, out_link->dcache_obj_id);
    if (FD_UNLIKELY(!ctx->out_wksp))
        FD_LOG_ERR(( "tknorm: output workspace is not joined" ));
    ctx->out_chunk0 = fd_dcache_compact_chunk0(ctx->out_wksp, out_link->dcache);
    ctx->out_wmark = fd_dcache_compact_wmark(ctx->out_wksp, out_link->dcache, out_link->mtu);
    ctx->out_chunk = ctx->out_chunk0;

    FD_LOG_NOTICE(( "tknorm: unprivileged init tile_id=%lu cnc=%p out_chunk0=%lu out_wmark=%lu",
                    tile->id, ctx->cnc, ctx->out_chunk0, ctx->out_wmark ));
}

static void
tknorm_during_frag( tknorm_ctx_t * ctx,
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

    /* Validate framing: currency must be "USD", amount_cents > 0, not malformed */
    int valid = 1;
    if (msg_in->raw.malformed) valid = 0;
    if (memcmp(&msg_in->raw.currency, "USD", 3) != 0) valid = 0;
    if (msg_in->raw.amount_cents <= 0) valid = 0;

    /* Compute stable event hash */
    ctx->output_msg->event_hash = tknorm_stable_event_hash(&msg_in->raw);

    /* Stamp pipeline_hops */
    ctx->output_msg->pipeline_hops += 1;

    if (!valid) {
        ctx->output_msg->decision = (uint8_t)POLICY_MALFORMED_DROP;
        memcpy(ctx->output_msg->decided_by, TILE_ID_TKNORM, sizeof(TILE_ID_TKNORM));
        ctx->invalid += 1;
    } else {
        ctx->output_msg->decision = (uint8_t)POLICY_ALLOW;
        memcpy(ctx->output_msg->decided_by, TILE_ID_TKNORM, sizeof(TILE_ID_TKNORM));
        ctx->normalized += 1;
    }

    /* Shared boilerplate: event-count gating */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->normalized + ctx->invalid);

    /* Mark output ready */
    ctx->output_ready = 1;
    ctx->output_sz = PAYMENT_MSG_SIZE;
    /* Chunk offset will be set in after_credit when we allocate from output dcache */

    /* Shared boilerplate: progress publishing */
    stk_publish_progress(ctx->cnc, ctx->normalized + ctx->invalid);
}

static void
tknorm_after_credit( tknorm_ctx_t *    ctx,
                     fd_stem_context_t * stem,
                     int *               opt_poll_in,
                     int *               charge_busy ) {
    (void)opt_poll_in;

    if (ctx->output_ready) {
        ulong out_chunk = ctx->out_chunk;
        void * dst = fd_chunk_to_laddr(ctx->out_wksp, out_chunk);
        memcpy(dst, ctx->output_msg, ctx->output_sz);

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
tknorm_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = (tknorm_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKNORM_CTX_ALIGN );

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if (FD_UNLIKELY(cnc_obj_id == ULONG_MAX))
        FD_LOG_ERR(( "tknorm: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tknorm_run( topo, tile );  /* stem_run loop */
    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_NORM_RUN = {
    .name                     = TILE_ID_TKNORM,
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
    .scratch_align            = tknorm_scratch_align,
    .scratch_footprint        = tknorm_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tknorm_privileged_init,
    .unprivileged_init        = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tknorm_unprivileged_init,
    .run                      = (void (*)(fd_topo_t *, fd_topo_tile_t *))tknorm_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

fd_topo_run_tile_t const *
tk_get_norm_run_tile( void ) {
    return &TK_NORM_RUN;
}

/* Wrapper for topob.c: query scratch footprint without needing a
   fd_topo_tile_t pointer. Delegates to TK_NORM_RUN.scratch_footprint
   to avoid conflicting with the STEM-generated macro function. */
ulong
tknorm_tile_scratch_footprint( void ) {
    return TK_NORM_RUN.scratch_footprint( NULL );
}

/* Field accessors for integration/test_tknorm_integration.zig.
   These avoid Zig-C struct layout mismatch by reading individual fields. */
char const *
tk_get_norm_run_name( void ) {
    return TK_NORM_RUN.name;
}

void *
tk_get_norm_run_run( void ) {
    return (void *)TK_NORM_RUN.run;
}

void *
tk_get_norm_run_scratch_align( void ) {
    return (void *)TK_NORM_RUN.scratch_align;
}

void *
tk_get_norm_run_scratch_footprint( void ) {
    return (void *)TK_NORM_RUN.scratch_footprint;
}

void *
tk_get_norm_run_privileged_init( void ) {
    return (void *)TK_NORM_RUN.privileged_init;
}

void *
tk_get_norm_run_unprivileged_init( void ) {
    return (void *)TK_NORM_RUN.unprivileged_init;
}
