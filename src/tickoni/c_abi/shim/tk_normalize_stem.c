/* tk_normalize_stem.c — Stem fd_stem tile for tknorm.

   Follows the fd_stem callback contract in stem_helpers.h:
   - DURING_FRAG: copy the TkEvent out of the input dcache into the staging
     buffer, validate the kind's fields (payment: currency=USD,
     amount_cents>0, not malformed; agent request: wire versions, request
     type and prompt reference), compute the canonical event hash, stamp
     decision/decided_by, set stage_valid.  Stages only — no counters, no
     progress, no publish.
   - AFTER_FRAG: bump the normalized/invalid counters from the staged
     decision, publish to the output dcache via fd_stem_publish, publish
     progress, publish the diagnostic fragment to tkdiag when the topology
     wires one (stem_diag.h), apply the event gate.
   - AFTER_CREDIT: not defined — tknorm has no fragment-independent work.
   - SHOULD_SHUTDOWN: CNC HALT + idle threshold + event_count exhaustion

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
#include <stdlib.h>

/* ─── Context ───
   tknorm_ctx_t MUST be defined BEFORE STEM_CALLBACK_CONTEXT_TYPE
   so fd_stem.c sees a complete type when it expands.
*/
typedef struct {
    /* Counters */
    uint64_t normalized;
    uint64_t invalid;

    /* Staging state (written in during_frag, committed in after_frag) */
    int      stage_valid;
    uint64_t stage_sz;

    /* Pre-existing unused field; left in place to keep the scratch layout
       and this struct's shape unchanged. */
    uint64_t output_chunk;

    /* Idle threshold tracking */
    long     idle_ticks;

    /* CNC reference for shutdown detection */
    void     *cnc;

    /* Tile pointer */
    fd_topo_tile_t const *tile;

    /* Workspace pointer for dcache writes */
    stk_link_in_t in;     /* the pipeline input */

    /* Scratch-allocated output TkEvent buffer */
    TkEvent *output_msg;

    /* Event count gating */
    uint64_t event_count;
    int      input_exhausted;

    /* Output dcache allocation state */
    stk_link_out_t out;   /* the pipeline output */

    /* Optional diagnostic link to tkdiag (stem_diag.h) */
    stk_diag_out_t diag;
} tknorm_ctx_t;

#define TKNORM_CTX_ALIGN alignof(tknorm_ctx_t)
#define TKNORM_OUTPUT_CAPACITY 1

/* Forward declarations */
static void tknorm_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tknorm_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tknorm_during_frag( tknorm_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                 ulong chunk, ulong sz, ulong ctl );
static void tknorm_after_frag( tknorm_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tknorm_run_entry( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Generate a norm-specific static stem specialization. */
#define STEM_NAME                         tknorm
#define STEM_BURST                        (1UL)
#define STEM_LAZY                         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE        tknorm_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN       TKNORM_CTX_ALIGN
#define STEM_CALLBACK_DURING_HOUSEKEEPING(ctx) stk_cnc_liveness( (ctx)->cnc )
#define STEM_CALLBACK_DURING_FRAG         tknorm_during_frag
#define STEM_CALLBACK_AFTER_FRAG          tknorm_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->idle_ticks > 10000L ) || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "disco/metrics/fd_metrics.h"
#include "disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_HOUSEKEEPING
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Canonical event hash: FNV-1a 64-bit, seed AUDIT_INITIAL_HASH (0) ───

   Payment: matches runtime.zig:stableEventHash exactly.  Field order:
   idempotency_key(u64), account_id(u32), amount_cents(i64->u64 bitcast),
   currency(3 bytes), each little-endian byte by byte.

   Agent request: the kind byte, idempotency_key(u64), then the bytes of the
   request with every field that is not request content zeroed -- the
   per-request identities other tiles stamp (scope.run_id, scope.trace_id,
   scope.request_id, scope.prompt_hash) and all padding.  Two requests for the
   same work hash the same whatever trace they belong to, so tkdedu's
   (idempotency_key, event_hash) rule holds for both kinds. */
static inline void
tknorm_fnv_u64( uint64_t * h, uint64_t x, int n ) {
    for( int i=0; i<n; i++ ) { *h ^= (x & 0xff); *h *= 0x100000001b3ULL; x >>= 8; }
}

static inline void
tknorm_fnv_bytes( uint64_t * h, uint8_t const * p, ulong n ) {
    for( ulong i=0UL; i<n; i++ ) { *h ^= p[i]; *h *= 0x100000001b3ULL; }
}

static uint64_t
tknorm_event_hash( TkEvent const * ev ) {
    uint64_t h = 0ULL;  /* AUDIT_INITIAL_HASH == 0 in audit_consts.h */
    if( ev->kind==TK_EVENT_KIND_AGENT_REQUEST ) {
        TkAgentRequestMsg canon = ev->body.agent_request;
        canon._pad             = 0U;
        canon.prompt_ref._pad  = 0U;
        canon.scope._pad0      = 0U;
        canon.scope.run_id     = 0UL;
        memset( canon.scope.trace_id, 0, sizeof(canon.scope.trace_id) );
        canon.scope.request_id = 0UL;
        canon.scope.prompt_hash = 0UL;
        uint8_t kind = ev->kind;
        tknorm_fnv_bytes( &h, &kind, 1UL );
        tknorm_fnv_u64( &h, ev->idempotency_key, 8 );
        tknorm_fnv_bytes( &h, (uint8_t const *)&canon, sizeof(canon) );
        return h;
    }
    TkEventPayment const * p = &ev->body.payment;
    tknorm_fnv_u64( &h, ev->idempotency_key, 8 );
    tknorm_fnv_u64( &h, (uint64_t)p->account_id, 4 );
    tknorm_fnv_u64( &h, (uint64_t)p->amount_cents, 8 );
    tknorm_fnv_bytes( &h, p->currency, 3UL );
    return h;
}

/* The kind's own fields.  tkings has already checked the envelope. */
static int
tknorm_event_valid( TkEvent const * ev ) {
    if( ev->kind==TK_EVENT_KIND_PAYMENT ) {
        TkEventPayment const * p = &ev->body.payment;
        if( p->malformed )                        return 0;
        if( memcmp( p->currency, "USD", 3 )!=0 )  return 0;
        if( p->amount_cents<=0 )                  return 0;
        return 1;
    }
    if( ev->kind==TK_EVENT_KIND_AGENT_REQUEST ) {
        TkAgentRequestMsg const * r = &ev->body.agent_request;
        if( r->version!=TK_AGENT_WIRE_VERSION )                                 return 0;
        if( r->scope.version!=TKMODL_WIRE_VERSION )                            return 0;
        if( r->request_type!=TK_AGENT_REQ_CHAT && r->request_type!=TK_AGENT_REQ_EMBEDDING ) return 0;
        if( r->prompt_ref.prompt_len==0U ||
            r->prompt_ref.prompt_len>(uint32_t)TKAGNT_PROMPT_MAX_BYTES )       return 0;
        return 1;
    }
    return 0;
}

/* ─── Exported wrappers for FFI unit tests ─── */
uint64_t
tknorm_event_hash_compute( TkEvent const * ev ) {
    return tknorm_event_hash( ev );
}

int
tknorm_event_valid_compute( TkEvent const * ev ) {
    return tknorm_event_valid( ev );
}

/* ─── Scratch footprint and alignment ───

   STEM_CALLBACK generates STEM_(scratch_footprint)( ulong in_cnt, ... ) and
   STEM_(scratch_align)( void ), but both describe fd_stem's own stack scratch
   (the in[]/cr_avail[]/event-map block, aligned to FD_STEM_SCRATCH_ALIGN) —
   not this tile's scratch object.  TK_NORM_RUN must describe the tile object,
   so the tile-specific variants below are what it points at. */

/* Alignment of the whole tile scratch object: the context and the output
   TkEvent both live in this one block, which
   tknorm_scratch_footprint_tile() lays out from offset 0, so the object's
   base must satisfy the strictest of them.  Derived from the context struct
   rather than restated as a literal — this is the single definition of
   tknorm's scratch alignment, and topob.c reads it back through
   tknorm_tile_scratch_align(). */
static ulong
tknorm_scratch_align_tile( void ) {
    return fd_ulong_max( TKNORM_CTX_ALIGN, alignof(TkEvent) );
}

static ulong
tknorm_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tknorm_ctx_t), TKNORM_CTX_ALIGN );
    /* output_msg follows aligned context */
    footprint = fd_ulong_align_up( footprint, alignof(TkEvent) );
    footprint += sizeof(TkEvent) * TKNORM_OUTPUT_CAPACITY;
    return footprint;
}

/* ─── Event count setter (set by topo_build.build() before topology queries) ─── */

static ulong tknorm_event_count_param = 0UL;

void
tknorm_set_event_count( ulong event_count ) {
    tknorm_event_count_param = event_count;
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
    ctx->stage_valid = 0;
    ctx->idle_ticks = 0;
    ctx->cnc = NULL;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;

    /* Point output_msg at scratch block after context */
    ulong ctx_end = fd_ulong_align_up( (ulong)ctx + sizeof(tknorm_ctx_t), alignof(TkEvent) );
    ctx->output_msg = (TkEvent *)ctx_end;

    /* Event count for shutdown gating.
       Set by topo_build.build() via tknorm_set_event_count() —
       same C-param pattern as tkdedu to avoid the env var anti-pattern:
       getenv() in privileged_init reads each child's own environment,
       which can differ from the supervisor's. */
    ctx->event_count = tknorm_event_count_param;

    FD_LOG_NOTICE(( "tknorm: privileged init ctx=%p output=%p",
                    ctx, ctx->output_msg ));
}

static void
tknorm_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = STK_GET_CTX(tknorm_ctx_t, scratch, TKNORM_CTX_ALIGN);

    /* Shared boilerplate: find CNC and set ctx->cnc */
    STK_UNPRIV_INIT(topo, tile, ctx);

    /* One pipeline output (index 0), plus the optional diagnostic link last. */
    stk_diag_out_init(&ctx->diag, topo, tile, 1UL);
    stk_link_in_init (&ctx->in,  topo, tile, 0UL, (ulong)TK_EVENT_SIZE);
    stk_link_out_init(&ctx->out, topo, tile, 0UL, (ulong)TK_EVENT_SIZE);

    FD_LOG_NOTICE(( "tknorm: unprivileged init tile_id=%lu cnc=%p out_chunk0=%lu out_wmark=%lu",
                    tile->id, ctx->cnc, ctx->out.chunk0, ctx->out.wmark ));
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
       the staged copy; counters, progress and the publish are committed in
       AFTER_FRAG, after fd_stem has confirmed the fragment was intact. */
    memcpy(ctx->output_msg, msg_in, sizeof(TkEvent));

    int valid = tknorm_event_valid(ctx->output_msg);
    ctx->output_msg->event_hash = tknorm_event_hash(ctx->output_msg);

    /* Stamp pipeline_hops */
    ctx->output_msg->pipeline_hops += 1;

    /* Stamp the verdict.  AFTER_FRAG reads it back off the staged message to
       pick the counter, so no separate ctx flag is needed. */
    ctx->output_msg->decision = valid ? (uint8_t)POLICY_ALLOW
                                     : (uint8_t)POLICY_MALFORMED_DROP;
    memcpy(ctx->output_msg->decided_by, TILE_ID_TKNORM, sizeof(ctx->output_msg->decided_by));

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
tknorm_after_frag( tknorm_ctx_t *      ctx,
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

    if (ctx->output_msg->decision == (uint8_t)POLICY_MALFORMED_DROP) ctx->invalid += 1;
    else                                                             ctx->normalized += 1;

    /* Publish the staged message. */
    stk_link_out_publish(&ctx->out, stem, 0UL, TK_LINK_SIG_EVENT, ctx->output_msg, ctx->stage_sz);

    /* Publish the two registry-owned counters (tile_registry.zig maps
       app[0]=normalized, app[1]=invalid for tknorm). */
    stk_publish_counter(ctx->cnc, 0UL, ctx->normalized);
    stk_publish_counter(ctx->cnc, 1UL, ctx->invalid);

    /* Diagnostic fragment: the cumulative counters just committed.  It goes to
       an unreliable link, so it draws no credit and STEM_BURST stays 1. */
    stk_diag_publish(&ctx->diag, stem, in_idx, seq, ctx->normalized + ctx->invalid, ctx->invalid, 0UL);

    /* Shared boilerplate: event-count gating, checked against the
       post-increment total so the gate fires on the Nth fragment. */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->normalized + ctx->invalid);
}

/* ─── Run entry point ─── */

static void
tknorm_run_entry( fd_topo_t *      topo,
                  fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = (tknorm_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKNORM_CTX_ALIGN );

    FD_LOG_DEBUG(( "tknorm: run entry ctx=%p tile=%s:%lu", (void*)ctx, tile->name, tile->id ));

    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if (FD_UNLIKELY(cnc_obj_id == ULONG_MAX))
        FD_LOG_ERR(( "tknorm: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    tknorm_run( topo, tile );  /* stem_run loop */
    tile->allow_shutdown = 1;

    FD_LOG_DEBUG(( "tknorm: run exit ctx=%p normalized=%lu invalid=%lu",
                   (void*)ctx, ctx->normalized, ctx->invalid ));
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
    .scratch_align            = tknorm_scratch_align_tile,
    .scratch_footprint        = tknorm_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tknorm_privileged_init,
    .unprivileged_init        = (void (*)(fd_topo_t const *, fd_topo_tile_t const *))tknorm_unprivileged_init,
    .run                      = (void (*)(fd_topo_t *, fd_topo_tile_t *))tknorm_run_entry,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_norm,
    TK_NORM_RUN,
    tknorm_tile_scratch_align,
    tknorm_tile_scratch_footprint
)
