/* tk_dedu_stem.c — Stem fd_stem tile for tkdedu.

   Follows the fd_stem callback contract in stem_helpers.h:
   - DURING_FRAG: validate framing, copy the PaymentMessage out of the input
     dcache into the staging buffer, increment pipeline_hops, set stage_valid.
     Stages only — no dedupe write, no counters, no progress, no publish.
   - AFTER_FRAG: skip dedup for malformed_drop, linear scan
     seen_keys/seen_hashes, mark duplicate or insert, write the staged message
     to the pre-computed output dcache slot, publish via fd_stem_publish,
     advance chunk, bump counters, publish progress, apply the event gate.
   - AFTER_CREDIT: not defined — tkdedu has no fragment-independent work.
   - SHOULD_SHUTDOWN: CNC HALT + event_count exhaustion

   Uses stem_helpers.h for shared boilerplate:
   STK_GET_CTX, stk_derive_wksp, STK_UNPRIV_INIT,
   stk_validate_frag, stk_chunk_to_gaddr, STK_EVENT_EXHAUSTED,
   stk_publish_counter
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

/* ─── Context ───
   tkdedu_ctx_t MUST be defined BEFORE STEM_CALLBACK_CONTEXT_TYPE
   so fd_stem.c sees a complete type when it expands.
*/
typedef struct {
    /* Counters */
    uint64_t duplicates;
    uint64_t processed;

    /* Dedup state — scratch-allocated arrays.  seen_cap is the reserved
       entry count that drives every scratch offset; it is NOT the
       shutdown-gating event_count below (which may legitimately be 0). */
    uint64_t seen_count;
    uint64_t seen_cap;
    uint64_t *seen_keys;
    uint64_t *seen_hashes;

    /* Staging state (written in during_frag, committed in after_frag) */
    int      stage_valid;
    uint64_t stage_sz;

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
static void tkdedu_after_frag( tkdedu_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkdedu_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define TKDEDU_CTX_ALIGN alignof(tkdedu_ctx_t)
#define TKDEDU_OUTPUT_CAPACITY 1

/* Generate a dedu-specific static stem specialization. */
#define STEM_NAME                         tkdedu
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkdedu_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKDEDU_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tkdedu_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkdedu_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint and alignment ───

   STEM_CALLBACK generates STEM_(scratch_footprint)( ulong in_cnt, ... ) and
   STEM_(scratch_align)( void ), but both describe fd_stem's own stack scratch
   (the in[]/cr_avail[]/event-map block, aligned to FD_STEM_SCRATCH_ALIGN) —
   not this tile's scratch object.  TK_DEDU_RUN must describe the tile object,
   so we provide tile-specific variants (scratch_align_tile,
   scratch_footprint_tile) plus no-argument wrappers (tile_scratch_align,
   tile_scratch_footprint) for topob.c, which never needs the full
   fd_topo_tile_t definition.
*/

/* Alignment of the whole tile scratch object: the context, the dedupe
   arrays and the output PaymentMessage all live in this one block, and
   tkdedu_scratch_footprint_tile() lays them out from offset 0, so the
   object's base must satisfy the strictest of them.  Derived from the
   context struct rather than restated as a literal — this is the single
   definition of tkdedu's scratch alignment, and topob.c reads it back
   through tkdedu_tile_scratch_align(). */
static ulong
tkdedu_scratch_align_tile( void ) {
    return TKDEDU_CTX_ALIGN;
}

/* ─── Dedupe table size: explicit runtime layout parameter ───

   The dedupe table size is a runtime value, so it has to reach BOTH
   tkdedu_scratch_footprint_tile() — which the supervisor and every
   child call while deriving the workspace layout — and
   tkdedu_privileged_init().  It travels in TopologySpec and is pushed in
   here by topo_build.build() before any footprint query, so the layout
   the supervisor computes and the layout each child re-derives are
   identical by construction.

   This was previously read from the TKDEDU_EVENT_COUNT environment
   variable in both places, which made workspace object offsets depend on
   process environment: a child whose environment differed from the
   supervisor's reserved a different footprint, shifting every object
   after tkdedu's and corrupting its view of the workspace. */
#define TKDEDU_DEFAULT_EVENT_COUNT 10000UL

static ulong tkdedu_event_count_param = 0UL;

void
tkdedu_set_event_count( ulong event_count ) {
    tkdedu_event_count_param = event_count;
}

/* Single resolution point for the reserved entry count.  The footprint
   reservation and privileged_init's pointer arithmetic MUST agree, or
   seen_hashes and output_msg land outside the reserved block. */
static ulong
tkdedu_layout_event_count( void ) {
    return tkdedu_event_count_param ? tkdedu_event_count_param
                                    : TKDEDU_DEFAULT_EVENT_COUNT;
}

static ulong
tkdedu_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    /* Context + alignment */
    ulong footprint = fd_ulong_align_up( sizeof(tkdedu_ctx_t), TKDEDU_CTX_ALIGN );

    /* Dedup arrays: seen_cap entries each. */
    ulong event_count = tkdedu_layout_event_count();

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
    ctx->seen_cap = 0;
    ctx->stage_valid = 0;
    ctx->cnc = NULL;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;
    ctx->out_wksp = NULL;
    ctx->out_chunk0 = 0;
    ctx->out_wmark = 0;
    ctx->out_chunk = 0;

    /* Derive workspace pointer from input mcache */
    ctx->wksp = stk_derive_wksp(topo, tile, 0);

    /* Shutdown gating count, as set by topo_build.build() from
       TopologySpec.  0 means "no event-count gate"; the tile then stops
       on CNC HALT only. */
    ctx->event_count = tkdedu_event_count_param;

    /* Reserved table size.  This, never ctx->event_count, drives every
       scratch offset below, so the layout is byte-identical to the one
       tkdedu_scratch_footprint_tile() reserved even when the gating
       count is 0. */
    ctx->seen_cap = tkdedu_layout_event_count();

    FD_LOG_NOTICE(( "tkdedu: event_count=%lu seen_cap=%lu",
                    (unsigned long)ctx->event_count, (unsigned long)ctx->seen_cap ));

    /* Allocate dedup arrays from scratch */
    ulong arr_align = fd_ulong_align_up( (ulong)ctx + sizeof(tkdedu_ctx_t), alignof(uint64_t) );
    uint64_t * arr = (uint64_t *)arr_align;
    ctx->seen_keys = arr;
    ctx->seen_hashes = arr + ctx->seen_cap;

    /* Point output_msg at scratch block after arrays */
    ulong out_align = fd_ulong_align_up( (ulong)arr + sizeof(uint64_t) * ctx->seen_cap * 2,
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

    /* Compute output dcache workspace fields for the after_frag publish.
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

    /* Clear first: fd_stem may skip AFTER_FRAG for this fragment (reading
       overrun), and a stale stage_valid would let the next AFTER_FRAG publish
       an abandoned message. */
    ctx->stage_valid = 0;

    /* Shared boilerplate: empty check, size check, wksp check, chunk→gaddr */
    if (!stk_validate_frag(sz, PAYMENT_MSG_SIZE, ctx->wksp))
        return;
    PaymentMessage const * msg_in = stk_chunk_to_gaddr(ctx->wksp, chunk);

    /* Stage the input.  Everything below this point is a pure function of
       the staged copy; the dedupe table, counters and publish are committed
       in AFTER_FRAG, after fd_stem has confirmed the fragment was intact. */
    memcpy(ctx->output_msg, msg_in, sizeof(PaymentMessage));
    ctx->output_msg->pipeline_hops += 1;

    ctx->stage_valid = 1;
    ctx->stage_sz = PAYMENT_MSG_SIZE;
}

/* AFTER_FRAG is the commit point: the first callback fd_stem reaches after
   its post-DURING_FRAG overrun re-check, so the only place the staged message
   is known to be intact.  It is also the only publish path — publishing in
   AFTER_CREDIT would drop the final event, because SHOULD_SHUTDOWN is
   evaluated at the top of the stem loop and the event gate below fires on the
   same iteration that stages that event. */
static void
tkdedu_after_frag( tkdedu_ctx_t *      ctx,
                   ulong               in_idx,
                   ulong               seq,
                   ulong               sig,
                   ulong               sz,
                   ulong               tsorig,
                   ulong               tspub,
                   fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub;

    if (!ctx->stage_valid)
        return;
    ctx->stage_valid = 0;

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
        } else if (FD_UNLIKELY( ctx->seen_count >= ctx->seen_cap )) {
            /* Fail closed: writing past seen_cap would corrupt the
               scratch that follows the reserved dedupe table. */
            FD_LOG_ERR(( "tkdedu: dedupe table full at %lu entries",
                         (unsigned long)ctx->seen_cap ));
        } else {
            /* Remember this (key, hash) pair */
            ctx->seen_keys[ctx->seen_count] = ctx->output_msg->raw.idempotency_key;
            ctx->seen_hashes[ctx->seen_count] = ctx->output_msg->event_hash;
            ctx->seen_count += 1;
        }
    }

    /* Publish the staged message, duplicate flag included. */
    ulong out_chunk = ctx->out_chunk;
    void * dst = fd_chunk_to_laddr(ctx->out_wksp, out_chunk);
    memcpy(dst, ctx->output_msg, ctx->stage_sz);

    /* (stem, out_idx, sig, chunk, sz, ctl, tsorig, tspub) */
    fd_stem_publish(stem, 0UL, 0UL, out_chunk, ctx->stage_sz, 0UL, 0UL, 0UL);
    ctx->out_chunk = fd_dcache_compact_next(
        out_chunk,
        ctx->stage_sz,
        ctx->out_chunk0,
        ctx->out_wmark
    );

    ctx->processed += 1;

    /* Shared boilerplate: counter publishing.  ctx->processed is the
       shutdown gate's input, not a counter the supervisor exposes. */
    stk_publish_counter(ctx->cnc, 0UL, ctx->duplicates);

    /* Shared boilerplate: event-count gating.  Checked against the
       post-increment count so the gate fires on the Nth fragment and the
       tile self-exits, rather than waiting for an (N+1)th that never
       arrives and only stopping on CNC HALT. */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->processed);
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
    .scratch_align            = tkdedu_scratch_align_tile,
    .scratch_footprint        = tkdedu_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tkdedu_privileged_init,
    .unprivileged_init        = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tkdedu_unprivileged_init,
    .run                      = (void (*)(fd_topo_t *, fd_topo_tile_t *))tkdedu_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_dedu,
    TK_DEDU_RUN,
    tkdedu_tile_scratch_align,
    tkdedu_tile_scratch_footprint
)
