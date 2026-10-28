/* tk_normalize_stem.c — Tickoni's tknorm normalize tile, fd_stem-based.
 *
 * Consumes payment events from tkings (1-in), validates framing,
 * computes stable event hash, and publishes normalized events to
 * tkdedu (1-out).
 *
 * Callback mapping from current while(pop()) loop:
 *   DURING_FRAG  ←  while(pop()) body (consume → validFraming → stableEventHash → push)
 *   AFTER_CREDIT ←  push to tkdedu output link
 *   BEFORE_CREDIT ← idle tick tracking (consecutive_empty counter)
 *   SHOULD_SHUTDOWN ← work_done (consecutive_empty >= threshold) or HALT
 *
 * Design notes:
 *   • Each tile's C shim is self-contained: defines STEM_CALLBACK_* macros,
 *     includes fd_stem.c, and produces a TKNORM_RUN fd_topo_run_tile_t.
 *   • Fragment passthrough: tknorm reads the raw fragment from input dcache,
 *     validates it, and writes to output dcache. Same memory layout
 *     as the PaymentMessage struct defined inline here.
 *   • The fragment format matches tk_audit_stem.c's PaymentMessage —
 *     tknorm receives the same fragment shape that tkings emits.
 *   • Backpressure: stem handles via cr_avail. tknorm doesn't check
 *     queue depth — stem won't call AFTER_CREDIT if no credits available.
 */

#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS

#define _GNU_SOURCE

#include "../../../util/fd_util.h"
#include "../../../tango/dcache/fd_dcache.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "../../../disco/topo/fd_topo.h"
#include "../topo_run/tk_norm_stem.h"
#include "../shim/audit_schema.h"  /* PolicyOutcome, TILE_ID_TKNORM */

/* Local declaration for topo object lookup (implemented in topob.c,
   declared in tk_metric_tile.h — we avoid including that header to
   prevent the extern stem_run declaration from colliding with our
   static stem_run compiled from fd_stem.c). */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id,
                                    char const * obj_type );

/* ---------------------------------------------------------------------
   PaymentMessage layout — mirrors tk_audit_stem.c's definition.
   tknorm receives the same fragment shape that tkings emits.
   Must match the Zig binary layout exactly.
   --------------------------------------------------------------------- */

typedef struct {
  ulong  source_offset;
  ulong  idempotency_key;
  uint   account_id;
  long   amount_cents;
  uchar  currency[3];
  uchar  malformed;
  uchar  _pad[5];
} RawPayment;

typedef struct {
  RawPayment raw;
  ulong  event_hash;
  uchar  pipeline_hops;
  uchar  duplicate;
  uchar  decision;
  uchar  decided_by[6];
} PaymentMessage;

#define PAYMENT_MSG_SIZE (sizeof(PaymentMessage))

/* ---------------------------------------------------------------------
   tknorm_ctx_t — tknorm stem tile context in scratch space.
   --------------------------------------------------------------------- */

typedef struct {
    /* Counters */
    uint64_t events_processed;
    uint64_t malformed_count;
    uint64_t normalized_count;

    /* Fragment I/O state */
    int output_ready;     /* Set in DURING_FRAG, cleared in AFTER_CREDIT */
    uint8_t  output_buf[PAYMENT_MSG_SIZE];  /* Output fragment buffer */

    /* Idle / shutdown */
    uint64_t consecutive_empty;
    int input_exhausted;  /* Set when consecutive_empty exceeds threshold */

    /* CNC & workspace pointers */
    void * cnc;           /* CNC pointer — joined in unprivileged_init */
    fd_wksp_t * in_wksp;  /* Input workspace — set in unprivileged_init */
    fd_wksp_t * out_wksp; /* Output workspace — set in unprivileged_init */

    /* Output dcache chunk management */
    ulong out_chunk;      /* Next available output chunk offset */
    ulong out_chunk0;     /* First valid output chunk index */
    ulong out_wmark;      /* Output dcache watermark */
} tknorm_ctx_t;

/* ---------------------------------------------------------------------
   tknorm_during_frag — consume, validate, hash, prepare output
   Signature: (ctx, in_idx, seq, sig, chunk, sz, ctl)
   chunk is a dcache chunk offset — resolve via fd_chunk_to_laddr.
   wksp comes from ctx->in_wksp (set up in unprivileged_init).
   --------------------------------------------------------------------- */

#ifndef STEM_CALLBACK_DURING_FRAG
#define STEM_CALLBACK_DURING_FRAG tknorm_during_frag
#endif

static void
tknorm_during_frag( tknorm_ctx_t * ctx,
                    ulong          in_idx,
                    ulong          seq,
                    ulong          sig,
                    ulong          chunk,
                    ulong          sz,
                    uint           ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    /* 1. Enforce fragment size */
    if (sz != PAYMENT_MSG_SIZE) return;

    /* 2. Decode PaymentMessage from fragment chunk.
     *    ctx->in_wksp is set in unprivileged_init from the input link's workspace. */
    void * chunk_laddr = fd_chunk_to_laddr( ctx->in_wksp, chunk );
    PaymentMessage const * msg = (PaymentMessage const *)chunk_laddr;

    /* 3. Copy fragment to scratch for modification */
    PaymentMessage * out = (PaymentMessage *)ctx->output_buf;
    *out = *msg;

    /* 4. Validate framing — inline check matching Zig runtime.validFraming:
     *    - currency must be 3 ASCII uppercase letters (A-Z)
     *    - account_id must be > 0 */
    int valid = 1;
    for (int i = 0; i < 3; i++) {
        char c = out->raw.currency[i];
        if (c < 'A' || c > 'Z') { valid = 0; break; }
    }
    if (out->raw.account_id == 0) valid = 0;

    if (valid == 0) {
        /* Malformed: set decision using canonical value from audit_schema.h */
        out->decision = POLICY_MALFORMED_DROP;
        memcpy(out->decided_by, TILE_ID_TKNORM, 6);
        ctx->malformed_count++;
    } else {
        /* 5. Compute stable event hash — inline FNV-1a placeholder.
         *    Same inputs as Zig stableEventHash: (source_offset,
         *    idempotency_key, account_id, amount_cents).
         *    TODO: replace with exact Zig hash once verified. */
        ulong h = 0xcbf29ce484222325ULL;  /* FNV offset basis */
        h = (h ^ out->raw.source_offset) * 0x100000001b3ULL;
        h = (h ^ out->raw.idempotency_key) * 0x100000001b3ULL;
        h = (h ^ out->raw.account_id) * 0x100000001b3ULL;
        ulong amt = (ulong)(long)out->raw.amount_cents;
        h = (h ^ amt) * 0x100000001b3ULL;
        out->event_hash = h;
    }

    /* 6. Increment pipeline_hops */
    out->pipeline_hops += 1;

    /* 7. Mark output as ready — publish in AFTER_CREDIT */
    ctx->output_ready = 1;
    ctx->events_processed++;
    if (valid) ctx->normalized_count++;
    ctx->consecutive_empty = 0;
}

#define TK_NORM_IDLE_THRESHOLD 10000UL  /* Ticks before input_exhausted */

/* ---------------------------------------------------------------------
   Scratch helpers — footprint and alignment.
   --------------------------------------------------------------------- */

ulong
tk_norm_scratch_align( void ) {
    return TK_NORM_CTX_ALIGN;
}

ulong
tk_norm_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong l = FD_LAYOUT_INIT;
    l = FD_LAYOUT_APPEND( l, TK_NORM_CTX_ALIGN, sizeof(tknorm_ctx_t) );
    l = FD_LAYOUT_APPEND( l, alignof(PaymentMessage), PAYMENT_MSG_SIZE );
    return FD_LAYOUT_FINI( l, TK_NORM_CTX_ALIGN );
}

/* ---------------------------------------------------------------------
   tknorm_privileged_init — initialize ctx fields.
   --------------------------------------------------------------------- */

static void
tknorm_privileged_init( fd_topo_t const *      topo,
                        fd_topo_tile_t const * tile ) {
    (void)topo;
    FD_LOG_NOTICE(( "tknorm_stem: tknorm_privileged_init ENTER tile_id=%lu", tile->id ));

    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = (tknorm_ctx_t *)fd_ulong_align_up(
        (ulong)scratch, TK_NORM_CTX_ALIGN );

    ctx->events_processed = 0;
    ctx->malformed_count = 0;
    ctx->normalized_count = 0;
    ctx->output_ready = 0;
    ctx->consecutive_empty = 0;
    ctx->input_exhausted = 0;
    ctx->cnc = NULL;
    ctx->in_wksp = NULL;
    ctx->out_wksp = NULL;
    ctx->out_chunk = 0;
    ctx->out_chunk0 = 0;
    ctx->out_wmark = 0;

    FD_LOG_NOTICE(( "tknorm_stem: tknorm_privileged_init EXIT tile_id=%lu", tile->id ));
}

/* ---------------------------------------------------------------------
   tknorm_unprivileged_init — find CNC, set ctx->cnc; join input wksp.
   --------------------------------------------------------------------- */

static void
tknorm_unprivileged_init( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile ) {
    (void)topo;
    FD_LOG_NOTICE(( "tknorm_stem: tknorm_unprivileged_init ENTER tile_id=%lu tile_obj_id=%lu",
                    tile->id, tile->tile_obj_id ));

    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = (tknorm_ctx_t *)fd_ulong_align_up(
        (ulong)scratch, TK_NORM_CTX_ALIGN );

    /* Look up input workspace from the first input link. */
    if (tile->in_cnt > 0) {
        fd_topo_link_t const * link = &topo->links[tile->in_link_id[0]];
        fd_topo_wksp_t const * link_wksp = &topo->workspaces[topo->objs[link->dcache_obj_id].wksp_id];
        ctx->in_wksp = link_wksp->wksp;
        FD_LOG_NOTICE(( "tknorm_stem: in wksp=%p joined, tile_id=%lu", (void *)ctx->in_wksp, tile->id ));
    }

    /* Look up output workspace and set up dcache chunk management. */
    if (tile->out_cnt > 0) {
        fd_topo_link_t const * out_link = &topo->links[tile->out_link_id[0]];
        fd_topo_wksp_t const * out_wksp_info = &topo->workspaces[topo->objs[out_link->dcache_obj_id].wksp_id];
        ctx->out_wksp = out_wksp_info->wksp;
        ulong dcache_base = (ulong)fd_topo_obj_laddr( topo, out_link->dcache_obj_id );
        ctx->out_chunk0 = fd_dcache_compact_chunk0( NULL, (void *)dcache_base );
        ctx->out_wmark = fd_dcache_compact_wmark( NULL, (void *)dcache_base, PAYMENT_MSG_SIZE );
        ctx->out_chunk = ctx->out_chunk0;
        FD_LOG_NOTICE(( "tknorm_stem: out wksp=%p dcache=%p chunk0=%lu wmark=%lu tile_id=%lu",
                        (void *)ctx->out_wksp, (void *)dcache_base,
                        ctx->out_chunk0, ctx->out_wmark, tile->id ));
    }

    ulong cnc_obj_id = tk_topo_find_tile_obj( (fd_topo_t const *)topo, tile->id, "cnc" );
    if (cnc_obj_id != ULONG_MAX) {
        ctx->cnc = fd_cnc_join( fd_topo_obj_laddr( (fd_topo_t const *)topo, cnc_obj_id ) );
        if (ctx->cnc) {
            FD_LOG_NOTICE(( "tknorm_stem: CNC joined, tile_id=%lu", tile->id ));
        } else {
            FD_LOG_NOTICE(( "tknorm_stem: CNC join failed for tile_id=%lu", tile->id ));
        }
    }

    FD_LOG_NOTICE(( "tknorm_stem: tknorm_unprivileged_init EXIT tile_id=%lu", tile->id ));
}

/* ---------------------------------------------------------------------
   tknorm_after_credit — publish to tkdedu output link.
   Signature: (ctx, stem, poll_in, charge_busy)
   poll_in is int* (flow control), not fd_stem_tile_in_t*.
   --------------------------------------------------------------------- */

#ifndef STEM_CALLBACK_AFTER_CREDIT
#define STEM_CALLBACK_AFTER_CREDIT tknorm_after_credit
#endif

static void
tknorm_after_credit( tknorm_ctx_t *      ctx,
                     fd_stem_context_t * stem,
                     int *               poll_in,
                     int *               charge_busy ) {
    (void)stem; (void)poll_in;
    /* If output fragment is ready from during_frag, publish now.
     * Otherwise this is just a credit-check tick. */
    if (ctx->output_ready && ctx->out_wksp && ctx->out_chunk) {
        /* Compute the next output chunk offset using fd_dcache_compact_next. */
        ulong chunk = fd_dcache_compact_next( ctx->out_chunk,
                                              PAYMENT_MSG_SIZE,
                                              ctx->out_chunk0,
                                              ctx->out_wmark );

        /* Write the modified fragment to the output dcache. */
        void * out_laddr = fd_chunk_to_laddr( ctx->out_wksp, chunk );
        memcpy( out_laddr, ctx->output_buf, PAYMENT_MSG_SIZE );

        /* Publish to output link index 0 (tkdedu).
         * fd_stem_publish takes a chunk OFFSET (not a pointer),
         * stem_run handles backpressure via cr_avail. */
        fd_stem_publish( stem,
                         0,                           /* output link index */
                         PAYMENT_MSG_SIZE,            /* sig */
                         chunk,                       /* chunk offset */
                         PAYMENT_MSG_SIZE,            /* sz */
                         0, 0, 0 );                   /* ctl, tsorig, tspub */

        /* Advance to next chunk for next publication. */
        ctx->out_chunk = chunk;
        ctx->output_ready = 0;
    }
    *charge_busy = 0;
}

/* ---------------------------------------------------------------------
   tknorm_before_credit — idle tick tracking, HALT check.
   Signature: (ctx, stem, charge_busy)
   --------------------------------------------------------------------- */

#ifndef STEM_CALLBACK_BEFORE_CREDIT
#define STEM_CALLBACK_BEFORE_CREDIT tknorm_before_credit
#endif

static void
tknorm_before_credit( tknorm_ctx_t *      ctx,
                      fd_stem_context_t * stem,
                      int *               charge_busy ) {
    (void)stem;
    ctx->consecutive_empty++;
    /* If idle threshold exceeded, mark input_exhausted so
     * SHOULD_SHUTDOWN can exit. */
    if (ctx->consecutive_empty >= TK_NORM_IDLE_THRESHOLD) {
        ctx->input_exhausted = 1;
        FD_LOG_NOTICE(( "tknorm_stem: input_exhausted after %lu idle ticks",
                        ctx->consecutive_empty ));
    }
    *charge_busy = 0;
}

/* ---------------------------------------------------------------------
   stem_run — generated via the fd_stem template.
   stem_run is compiled here with tknorm_ctx_t as CONTEXT_TYPE.
   We do NOT override STEM_EXPORT, so it defaults to static.
   This keeps stem_run internal to the tknorm translation unit.
   --------------------------------------------------------------------- */

#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6)

#define STEM_CALLBACK_CONTEXT_TYPE  tknorm_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TK_NORM_CTX_ALIGN

#define STEM_CALLBACK_BEFORE_CREDIT tknorm_before_credit
#define STEM_CALLBACK_DURING_FRAG tknorm_during_frag
#define STEM_CALLBACK_AFTER_CREDIT tknorm_after_credit

/* SHOULD_SHUTDOWN as a macro — matches tk_audit_stem.c pattern.
   Checks both input_exhausted (idle threshold) and CNC HALT. */
#define STEM_CALLBACK_SHOULD_SHUTDOWN( ctx ) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "../../../disco/stem/fd_stem.c"

/* Clear STEM_EXPORT after the include so subsequent STEM instantiations
   (e.g. verify tile) see no STEM_EXPORT and use their own #ifndef
   STEM_EXPORT / #define STEM_EXPORT static blocks to default to static. */
#undef STEM_EXPORT

/* ---------------------------------------------------------------------
   tknorm_run — calls stem_run directly.
   We set ctx->cnc and ctx->wksp before calling stem_run.
   --------------------------------------------------------------------- */

static void
tknorm_run( fd_topo_t *      topo,
            fd_topo_tile_t * tile ) {
    FD_LOG_NOTICE(( "tknorm_stem: tknorm_run ENTER tile_id=%lu", tile->id ));

    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tknorm_ctx_t * ctx = (tknorm_ctx_t *)fd_ulong_align_up(
        (ulong)scratch, TK_NORM_CTX_ALIGN );

    /* CNC already joined in unprivileged_init — nothing to do here. */

    stem_run( topo, tile );

    FD_LOG_NOTICE(( "tknorm_stem: tknorm_run EXIT tile_id=%lu, processed=%lu, malformed=%lu, normalized=%lu",
                    tile->id, ctx->events_processed, ctx->malformed_count, ctx->normalized_count ));
}

/* ---------------------------------------------------------------------
   TKNORM_RUN — the fd_topo_run_tile_t that Tickoni dispatches.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t TKNORM_RUN = {
  .name                     = "tknorm",
  .keep_host_networking     = 0,
  .allow_connect            = 0,
  .allow_renameat           = 0,
  .rlimit_file_cnt          = 5UL,
  .rlimit_address_space     = 0,
  .rlimit_data              = 0,
  .rlimit_nproc             = 0,
  .for_tpool                = 0,
  .max_event_sz             = NULL,
  .populate_allowed_seccomp = NULL,
  .populate_allowed_fds     = NULL,
  .scratch_align            = tk_norm_scratch_align,
  .scratch_footprint        = tk_norm_scratch_footprint_tile,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tknorm_privileged_init,
  .unprivileged_init        = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tknorm_unprivileged_init,
  .run                      = tknorm_run,
  .rlimit_file_cnt_fn       = NULL,
};

/* ---------------------------------------------------------------------
   tk_get_normalize_run_tile — returns &TKNORM_RUN.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t *
tk_get_normalize_run_tile( void ) {
    return &TKNORM_RUN;
}

#endif /* FD_HAS_LINUX */
