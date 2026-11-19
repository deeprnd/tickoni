/* tk_policy_stem.c — Stem fd_stem tile for tkpoly.
 *
 * Follows the fd_stem callback contract in stem_helpers.h:
 * - DURING_FRAG: validate framing and copy the PaymentMessage out of the
 *   input dcache into the staged copy. Stages only — no decision, no
 *   counters, no progress, no publish.
 * - AFTER_FRAG: increment hops, apply the preserved branch order
 *   (malformed > duplicate > high-amount, signed), stamp tkpoly attribution
 *   for owned decisions, publish once to the precomputed output chunk, bump
 *   allowed/denied and processed, publish both CNC slots, then apply the
 *   event gate.
 * - AFTER_CREDIT: not defined — tkpoly has no fragment-independent work.
 * - SHOULD_SHUTDOWN: event_count exhaustion + CNC HALT.
 *
 * Uses stem_helpers.h for shared boilerplate.
 */

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"
#include "tickoni/c_abi/topo_run/tk_policy_stem.h"

#include "disco/topo/fd_topo.h"
#include "util/wksp/fd_wksp.h"
#include "util/fd_util.h"

#include <string.h>
#include <stddef.h>

/* ─── Context ───
 * tkpoly_ctx_t must be defined before STEM_CALLBACK_CONTEXT_TYPE.
 */
typedef struct {
    /* Counters */
    uint64_t processed;
    uint64_t allowed;
    uint64_t denied;

    /* Staging state (written in during_frag, committed in after_frag) */
    int      stage_valid;
    ulong    stage_sz;
    PaymentMessage staged_message;

    /* Output dcache allocation state (computed in unprivileged_init) */
    void *   out_wksp;
    ulong    out_chunk0;
    ulong    out_wmark;
    ulong    out_chunk;

    /* CNC reference for shutdown detection */
    void     *cnc;

    /* Workspace pointer for input dcache reads */
    void *wksp;

    /* Input dcache compact chunk bounds, workspace-relative: a valid
       fragment's chunk index lies in [in_chunk0, in_wmark]. */
    ulong    in_chunk0;
    ulong    in_wmark;

    /* Explicit behavior configuration copied at initialization. */
    int64_t policy_limit_cents;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;
} tkpoly_ctx_t;

/* Forward declarations */
static void tkpoly_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkpoly_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tkpoly_during_frag( tkpoly_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                 ulong chunk, ulong sz, ulong ctl );
static void tkpoly_after_frag( tkpoly_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tkpoly_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

#define TKPOLY_CTX_ALIGN alignof(tkpoly_ctx_t)
/* Generate a policy-specific static stem specialization. */
#define STEM_NAME                         tkpoly
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tkpoly_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKPOLY_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG         tkpoly_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tkpoly_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint and alignment ─── */

static ulong
tkpoly_scratch_align_tile( void ) {
    return TKPOLY_CTX_ALIGN;
}

static ulong
tkpoly_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    /* Context */
    ulong footprint = fd_ulong_align_up( sizeof(tkpoly_ctx_t), TKPOLY_CTX_ALIGN );

    return footprint;
}

/* ─── Fixed-width behavior configuration ─── */

static uint64_t tkpoly_event_count_param;
static int64_t   tkpoly_policy_limit_param;
static int       tkpoly_policy_limit_configured;

void
tkpoly_set_event_count( uint64_t event_count ) {
    tkpoly_event_count_param = event_count;
}

void
tkpoly_set_policy_limit_cents( int64_t policy_limit_cents ) {
    tkpoly_policy_limit_param = policy_limit_cents;
    tkpoly_policy_limit_configured = 1;
}

/* ─── Pure policy helper ───
 *
 * Branch precedence: malformed > duplicate > high-amount.
 * High-amount check: signed comparison amount_cents > policy_limit_cents,
 * matching the Zig decide() function exactly.
 */

uint8_t
tkpoly_policy_helper( uint8_t  decision,
                      int      is_duplicate,
                      int64_t  amount_cents,
                      int64_t  policy_limit_cents ) {
    if (decision == POLICY_MALFORMED_DROP)
        return POLICY_MALFORMED_DROP;
    if (is_duplicate)
        return POLICY_DUPLICATE_DROP;
    if (amount_cents > policy_limit_cents)
        return POLICY_DENY;
    return POLICY_ALLOW;
}

/* ─── Scratch-base counter readers ─── */

ulong
tkpolicy_ctx_processed( void * scratch ) {
    tkpoly_ctx_t * ctx = (tkpoly_ctx_t *)scratch;
    return ctx->processed;
}

ulong
tkpolicy_ctx_allowed( void * scratch ) {
    tkpoly_ctx_t * ctx = (tkpoly_ctx_t *)scratch;
    return ctx->allowed;
}

ulong
tkpolicy_ctx_denied( void * scratch ) {
    tkpoly_ctx_t * ctx = (tkpoly_ctx_t *)scratch;
    return ctx->denied;
}

/* ─── Callbacks ─── */

static void
tkpoly_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkpoly_ctx_t * ctx = STK_GET_CTX(tkpoly_ctx_t, scratch, TKPOLY_CTX_ALIGN);

    ctx->processed = 0;
    ctx->allowed = 0;
    ctx->denied = 0;
    ctx->stage_valid = 0;
    ctx->cnc = NULL;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;
    ctx->in_chunk0 = 0;
    ctx->in_wmark = 0;
    if (FD_UNLIKELY(!tkpoly_policy_limit_configured))
        FD_LOG_ERR(( "tkpoly: policy limit was not configured" ));
    ctx->policy_limit_cents = tkpoly_policy_limit_param;
    ctx->out_wksp = NULL;
    ctx->out_chunk0 = 0;
    ctx->out_wmark = 0;
    ctx->out_chunk = 0;
    ctx->wksp = NULL;

    ctx->wksp = stk_derive_wksp(topo, tile, 0);

    ctx->event_count = tkpoly_event_count_param;

    FD_LOG_NOTICE(( "tkpoly: privileged init ctx=%p wksp=%p", ctx, ctx->wksp ));
}

static void
tkpoly_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkpoly_ctx_t * ctx = STK_GET_CTX(tkpoly_ctx_t, scratch, TKPOLY_CTX_ALIGN);

    STK_UNPRIV_INIT(topo, tile, ctx);
    if (FD_UNLIKELY(!ctx->cnc))
        FD_LOG_ERR(( "tkpoly: CNC object not found for tile %lu", tile->id ));

    /* Cardinality first: tkpoly consumes tkdedu's output and produces
       tkaudt's input, so anything other than exactly one link each way is a
       topology the policy contract does not describe.  Validate before
       indexing the link arrays. */
    if (FD_UNLIKELY(tile->in_cnt != 1UL))
        FD_LOG_ERR(( "tkpoly: expected exactly one input link, found %lu", tile->in_cnt ));
    if (FD_UNLIKELY(tile->out_cnt != 1UL))
        FD_LOG_ERR(( "tkpoly: expected exactly one output link, found %lu", tile->out_cnt ));

    /* The input workspace was derived in privileged_init from the input
       mcache; a missing join there means every fragment would be silently
       rejected by stk_validate_frag, so fail startup instead. */
    if (FD_UNLIKELY(!ctx->wksp))
        FD_LOG_ERR(( "tkpoly: input workspace is not joined" ));
    fd_topo_link_t const * in_link = &topo->links[tile->in_link_id[0]];
    if (FD_UNLIKELY(!in_link->dcache || in_link->mtu < PAYMENT_MSG_SIZE))
        FD_LOG_ERR(( "tkpoly: invalid input dcache or mtu %lu", in_link->mtu ));

    /* Compact chunk bounds for the input dcache, indexed relative to the
       same workspace base that during_frag converts chunks against.  A
       fragment's chunk index is workspace-relative, not a 0..depth ring
       slot, so the link depth is not a bound on it. */
    ctx->in_chunk0 = fd_dcache_compact_chunk0(ctx->wksp, in_link->dcache);
    ctx->in_wmark  = fd_dcache_compact_wmark(ctx->wksp, in_link->dcache, in_link->mtu);

    /* Compute the output dcache workspace fields once, so the per-fragment
       path is one copy plus one publish.  Matches the tkdedu/tknorm pattern. */
    fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[0]];
    if (FD_UNLIKELY(!out_link->dcache || out_link->mtu < PAYMENT_MSG_SIZE))
        FD_LOG_ERR(( "tkpoly: invalid output dcache or mtu %lu", out_link->mtu ));
    ctx->out_wksp = fd_topo_obj_wksp_base(topo, out_link->dcache_obj_id);
    if (FD_UNLIKELY(!ctx->out_wksp))
        FD_LOG_ERR(( "tkpoly: output workspace is not joined" ));
    ctx->out_chunk0 = fd_dcache_compact_chunk0(ctx->out_wksp, out_link->dcache);
    ctx->out_wmark = fd_dcache_compact_wmark(ctx->out_wksp, out_link->dcache, out_link->mtu);
    ctx->out_chunk = ctx->out_chunk0;

    FD_LOG_NOTICE(( "tkpoly: unprivileged init tile_id=%lu cnc=%p in_chunk0=%lu in_wmark=%lu out_chunk0=%lu out_wmark=%lu",
                    tile->id, ctx->cnc, ctx->in_chunk0, ctx->in_wmark,
                    ctx->out_chunk0, ctx->out_wmark ));
}

static void
tkpoly_during_frag( tkpoly_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    ulong          ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    ctx->stage_valid = 0;

    if (!stk_validate_frag(sz, PAYMENT_MSG_SIZE, ctx->wksp))
        return;

    /* Chunk bounds: must be [in_chunk0, in_wmark].  Prevents out-of-bounds
       reads from the input dcache when fd_stem delivers a corrupted or
       replayed chunk index. */
    if (FD_UNLIKELY(chunk < ctx->in_chunk0 || chunk > ctx->in_wmark))
        return;

    PaymentMessage const * msg_in = stk_chunk_to_gaddr(ctx->wksp, chunk);

    /* Stage the input message */
    memcpy(&ctx->staged_message, msg_in, sizeof(PaymentMessage));
    ctx->stage_valid = 1;
    ctx->stage_sz = sizeof(PaymentMessage);
}

static void
tkpoly_after_frag( tkpoly_ctx_t *      ctx,
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

    PaymentMessage * msg = &ctx->staged_message;

    /* One hop per consumed event, counted on the commit path so an
       abandoned speculative read never inflates it. */
    msg->pipeline_hops += 1;

    uint8_t const outcome = tkpoly_policy_helper(
        msg->decision,
        (int)msg->duplicate,
        msg->raw.amount_cents,
        ctx->policy_limit_cents
    );

    /* The helper returns MALFORMED_DROP only for an incoming malformed_drop,
       which tknorm already decided and attributed.  Preserving both is the
       point: a malformed source fact still has to reach tkaudt carrying the
       producer that rejected it. */
    if (outcome != (uint8_t)POLICY_MALFORMED_DROP) {
        msg->decision = outcome;
        /* Exactly the six tile-id bytes.  TILE_ID_TKPOLY is a string
           literal, so sizeof() would also copy its terminator one byte past
           the field. */
        memcpy(msg->decided_by, TILE_ID_TKPOLY, sizeof(msg->decided_by));

        if (outcome == (uint8_t)POLICY_DENY)
            ctx->denied += 1;
        else if (outcome == (uint8_t)POLICY_ALLOW)
            ctx->allowed += 1;
        /* DUPLICATE_DROP is owned by tkpoly but is neither allowed nor
           denied; tkdedu already counted it. */
    }

    /* Publish the decided message.  A financial rejection is still a valid
       transport message, so every committed event is forwarded — allow, deny,
       duplicate and malformed alike. */
    ulong out_chunk = ctx->out_chunk;
    void * dst = fd_chunk_to_laddr(ctx->out_wksp, out_chunk);
    memcpy(dst, msg, ctx->stage_sz);

    /* (stem, out_idx, sig, chunk, sz, ctl, tsorig, tspub) */
    fd_stem_publish(stem, 0UL, 0UL, out_chunk, ctx->stage_sz, 0UL, 0UL, 0UL);
    ctx->out_chunk = fd_dcache_compact_next(
        out_chunk,
        ctx->stage_sz,
        ctx->out_chunk0,
        ctx->out_wmark
    );

    ctx->processed += 1;

    /* CNC slot schema from tile_registry.zig: app[0]=allowed, app[1]=denied. */
    stk_publish_counter(ctx->cnc, 0UL, ctx->allowed);
    stk_publish_counter(ctx->cnc, 1UL, ctx->denied);

    /* Gate on processed, never allowed+denied: duplicate and malformed events
       count toward completion too, so the tile self-exits on the Nth
       committed message instead of waiting for an (N+1)th that never comes. */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->processed);
}

/* ─── Run entry point ─── */

static void
tkpoly_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tkpoly_ctx_t * ctx = (tkpoly_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKPOLY_CTX_ALIGN );

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if (FD_UNLIKELY(cnc_obj_id == ULONG_MAX))
        FD_LOG_ERR(( "tkpoly: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkpoly_run(topo, tile);  /* stem_run loop */

    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_POLICY_RUN = {
    .name                     = TILE_ID_TKPOLY,
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
    .scratch_align            = tkpoly_scratch_align_tile,
    .scratch_footprint        = tkpoly_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tkpoly_privileged_init,
    .unprivileged_init        = tkpoly_unprivileged_init,
    .run                      = tkpoly_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_policy,
    TK_POLICY_RUN,
    tkpoly_tile_scratch_align,
    tkpoly_tile_scratch_footprint
)
