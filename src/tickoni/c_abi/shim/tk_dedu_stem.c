/* tk_dedu_stem.c — Stem fd_stem tile for tkdedu.

   Follows the fd_stem callback contract in stem_helpers.h:
   - DURING_FRAG: validate framing, copy the TkEvent out of the input
     dcache into the staging buffer, increment pipeline_hops, set stage_valid.
     Stages only — no dedupe write, no counters, no progress, no publish.
   - AFTER_FRAG: skip dedup for malformed_drop, linear scan
     seen_keys/seen_hashes, mark duplicate or insert, write the staged message
     to the pre-computed output dcache slot, publish via fd_stem_publish,
     advance chunk, bump counters, publish progress, publish the diagnostic
     fragment to tkdiag when the topology wires one (stem_diag.h), apply the
     event gate.
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
#include "tickoni/c_abi/shim/stem_diag.h"

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
    stk_link_out_t out;   /* the pipeline output */

    /* CNC reference for shutdown detection */
    void     *cnc;

    /* Tile pointer */
    fd_topo_tile_t const *tile;

    /* Workspace pointer for input dcache reads */
    stk_link_in_t in;     /* the pipeline input */

    /* Scratch-allocated output TkEvent buffer */
    TkEvent *output_msg;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;

    /* Optional diagnostic link to tkdiag (stem_diag.h) */
    stk_diag_out_t diag;
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
   arrays and the output TkEvent all live in this one block, and
   tkdedu_scratch_footprint_tile() lays them out from offset 0, so the
   object's base must satisfy the strictest of them.  Derived from the
   context struct rather than restated as a literal — this is the single
   definition of tkdedu's scratch alignment, and topob.c reads it back
   through tkdedu_tile_scratch_align(). */
static ulong
tkdedu_scratch_align_tile( void ) {
    return fd_ulong_max( TKDEDU_CTX_ALIGN, alignof(TkEvent) );
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
    footprint = fd_ulong_align_up( footprint, alignof(TkEvent) );
    footprint += sizeof(TkEvent) * TKDEDU_OUTPUT_CAPACITY;

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
                                          alignof(TkEvent) );
    ctx->output_msg = (TkEvent *)out_align;

    FD_LOG_NOTICE(( "tkdedu: privileged init ctx=%p seen_keys=%p seen_hashes=%p output=%p",
                    ctx, ctx->seen_keys, ctx->seen_hashes, ctx->output_msg ));
}

static void
tkdedu_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tkdedu_ctx_t * ctx = STK_GET_CTX(tkdedu_ctx_t, scratch, TKDEDU_CTX_ALIGN);

    /* Shared boilerplate: find CNC and set ctx->cnc */
    STK_UNPRIV_INIT(topo, tile, ctx);

    /* One pipeline output (index 0), plus the optional diagnostic link last. */
    stk_diag_out_init(&ctx->diag, topo, tile, 1UL);
    stk_link_in_init (&ctx->in,  topo, tile, 0UL, (ulong)TK_EVENT_SIZE);
    stk_link_out_init(&ctx->out, topo, tile, 0UL, (ulong)TK_EVENT_SIZE);

    FD_LOG_NOTICE(( "tkdedu: unprivileged init tile_id=%lu cnc=%p out_chunk0=%lu out_wmark=%lu",
                    tile->id, ctx->cnc, ctx->out.chunk0, ctx->out.wmark ));
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
    if (!stk_validate_frag(sz, TK_EVENT_SIZE, ctx->in.wksp))
        return;
    if (FD_UNLIKELY(!stk_link_in_contains(&ctx->in, chunk)))
        return;
    TkEvent const * msg_in = stk_link_in_laddr(&ctx->in, chunk);

    /* Stage the input.  Everything below this point is a pure function of
       the staged copy; the dedupe table, counters and publish are committed
       in AFTER_FRAG, after fd_stem has confirmed the fragment was intact. */
    memcpy(ctx->output_msg, msg_in, sizeof(TkEvent));
    ctx->output_msg->pipeline_hops += 1;

    ctx->stage_valid = 1;
    ctx->stage_sz = TK_EVENT_SIZE;
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
    (void)sig; (void)sz; (void)tsorig; (void)tspub;

    if (!ctx->stage_valid)
        return;
    ctx->stage_valid = 0;

    /* Dedup check: skip for malformed_drop (tknorm already rejected it) */
    if (ctx->output_msg->decision != (uint8_t)POLICY_MALFORMED_DROP) {
        /* Linear scan for duplicate */
        int is_dup = 0;
        for (uint64_t i = 0; i < ctx->seen_count; i++) {
            if (ctx->seen_keys[i] == ctx->output_msg->idempotency_key &&
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
               scratch that follows the reserved dedupe table.  This is a fatal
               fault the tile detects itself, so it says so to tkdiag with a
               final fragment before it aborts (a tile killed from outside
               cannot; tkdiag sees that from the process). */
            stk_diag_fault(&ctx->diag);
            stk_diag_publish(&ctx->diag, stem, in_idx, seq, ctx->processed, ctx->duplicates, 0UL);
            FD_LOG_ERR(( "tkdedu: dedupe table full at %lu entries",
                         (unsigned long)ctx->seen_cap ));
        } else {
            /* Remember this (key, hash) pair */
            ctx->seen_keys[ctx->seen_count] = ctx->output_msg->idempotency_key;
            ctx->seen_hashes[ctx->seen_count] = ctx->output_msg->event_hash;
            ctx->seen_count += 1;
        }
    }

    /* Publish the staged message, duplicate flag included. */
    stk_link_out_publish(&ctx->out, stem, 0UL, TK_LINK_SIG_EVENT, ctx->output_msg, ctx->stage_sz);

    ctx->processed += 1;

    /* Shared boilerplate: counter publishing.  ctx->processed is the
       shutdown gate's input, not a counter the supervisor exposes. */
    stk_publish_counter(ctx->cnc, 0UL, ctx->duplicates);

    /* Diagnostic fragment: the cumulative counters just committed.  It goes to
       an unreliable link, so it draws no credit and STEM_BURST stays 1. */
    stk_diag_publish(&ctx->diag, stem, in_idx, seq, ctx->processed, ctx->duplicates, 0UL);

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

    FD_LOG_DEBUG(( "tkdedu: run entry ctx=%p tile=%s:%lu", (void*)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if (FD_UNLIKELY(cnc_obj_id == ULONG_MAX))
        FD_LOG_ERR(( "tkdedu: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tkdedu_run(topo, tile);  /* stem_run loop */

    tile->allow_shutdown = 1;
    FD_LOG_DEBUG(( "tkdedu: run exit ctx=%p processed=%lu duplicates=%lu",
                   (void*)ctx, ctx->processed, ctx->duplicates ));
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
