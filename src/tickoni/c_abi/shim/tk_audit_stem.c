/* tk_audit_stem.c — tkaudt fd_stem tile shim.
 *
 * Implements the tkaudt audit sink tile on top of Firedancer's
 * fd_stem-based run loop (stem_run).  Receives PaymentMessage fragments
 * from tkpoly via a single input link, builds append-only hash-chained
 * audit records, and tracks idle ticks for shutdown.
 *
 * Follows the same template-inclusion pattern as fd_metric_tile.c:
 *   1. Define all STEM_CALLBACK_* macros for tk_audit_ctx_t
 *   2. Include fd_stem.c so stem_run is compiled with the correct
 *      context type (tk_audit_ctx_t), not fd_metric_ctx_t
 *   3. Use the locally-compiled (static) stem_run in TK_AUDIT_RUN
 *
 * IMPORTANT: stem_run MUST be compiled here with tk_audit_ctx_t as
 * CONTEXT_TYPE, otherwise the SHOULD_SHUTDOWN callback reads ctx->cnc
 * from the wrong memory offset and never detects HALT.
 */

#if FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS

#define _GNU_SOURCE

#include "../../../util/fd_util.h"
#include "../../../util/pod/fd_pod_format.h"
#include "../../../tango/dcache/fd_dcache.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "../../../disco/topo/fd_topo.h"
#include "../topo_run/tk_audit_stem.h"

/* Local declaration for topo object lookup (implemented in topob.c,
   declared in tk_metric_tile.h — we avoid including that header to
   prevent the extern stem_run declaration from colliding with our
   static stem_run compiled from fd_stem.c). */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type );

/* ---------------------------------------------------------------------
   PaymentMessage layout — mirrors the Zig struct in runtime.zig.
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

#include "audit_schema.h"

/* ---------------------------------------------------------------------
   tk_audit_ctx_t — tkaudt stem tile context in scratch space.
   --------------------------------------------------------------------- */

typedef struct {
  ulong     audited;
  ulong     max_latency_hops;
  ulong     consecutive_empty;
  int       input_exhausted;
  int       done;
  void      *cnc;
  fd_wksp_t *wksp;    /* input workspace pointer (set in unprivileged_init) */
  ulong     audit_count;
  ulong     prev_hash;
  AuditEvent scratch_event;
  ulong     event_count;
} tk_audit_ctx_t;

/* TKAUDT_CTX_ALIGN is defined in tk_audit_stem.h — don't redefine */
#define TKAUDT_IDLE_THRESHOLD 1000UL
#define TKAUDT_AUDIT_CAPACITY 16384UL

/* ---------------------------------------------------------------------
   Scratch helpers — footprint and alignment.
   --------------------------------------------------------------------- */

ulong
tk_audit_scratch_align( void ) {
  return TKAUDT_CTX_ALIGN;
}

ulong
tk_audit_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
  (void)tile;
  ulong l = FD_LAYOUT_INIT;
  l = FD_LAYOUT_APPEND( l, TKAUDT_CTX_ALIGN, sizeof(tk_audit_ctx_t) );
  l = FD_LAYOUT_APPEND( l, alignof(AuditEvent), TKAUDT_AUDIT_CAPACITY * sizeof(AuditEvent) );
  return FD_LAYOUT_FINI( l, TKAUDT_CTX_ALIGN );
}

/* ---------------------------------------------------------------------
   tk_audit_privileged_init — initialize ctx fields.
   --------------------------------------------------------------------- */

static void
tk_audit_privileged_init( fd_topo_t const *      topo,
                          fd_topo_tile_t const * tile ) {
  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_privileged_init ENTER tile_id=%lu", tile->id ));

  void * scratch = (void *)fd_topo_obj_laddr( topo, tile->tile_obj_id );
  tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up(
    (ulong)scratch, TKAUDT_CTX_ALIGN );

  ctx->audited = 0;
  ctx->max_latency_hops = 0;
  ctx->consecutive_empty = 0;
  ctx->input_exhausted = 0;
  ctx->done = 0;
  ctx->cnc = NULL;
  ctx->audit_count = 0;
  ctx->prev_hash = AUDIT_SEED;
  /* No default event_count — audit tile is a consumer, not a producer.
     Shutdown is driven by input_exhausted (idle ticks) or CNC HALT.
     event_count is set by the supervisor writing to CNC app region
     before tile startup, or remains 0 (unbounded) if absent. */
  ctx->event_count = 0UL;

  (void)topo;

  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_privileged_init EXIT tile_id=%lu", tile->id ));
}

/* ---------------------------------------------------------------------
   tk_audit_unprivileged_init — find CNC, set ctx->cnc.
   --------------------------------------------------------------------- */

static void
tk_audit_unprivileged_init( fd_topo_t const *      topo,
                            fd_topo_tile_t const * tile ) {
  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_unprivileged_init ENTER tile_id=%lu tile_obj_id=%lu",
                  tile->id, tile->tile_obj_id ));

  void * scratch = (void *)fd_topo_obj_laddr( topo, tile->tile_obj_id );
  tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up(
    (ulong)scratch, TKAUDT_CTX_ALIGN );

  /* Look up input workspace from the first input link. */
  if( tile->in_cnt > 0 ) {
    fd_topo_link_t const * link = &topo->links[ tile->in_link_id[ 0 ] ];
    fd_topo_wksp_t const * link_wksp = &topo->workspaces[ topo->objs[ link->dcache_obj_id ].wksp_id ];
    ctx->wksp = link_wksp->wksp;
    FD_LOG_NOTICE(( "tk_audit_stem: input wksp=%p joined, tile_id=%lu", (void *)ctx->wksp, tile->id ));
  }

  ulong cnc_obj_id = tk_topo_find_tile_obj( (fd_topo_t const *)topo, tile->id, "cnc" );
  if( cnc_obj_id != ULONG_MAX ) {
    void * cnc_laddr = (void *)fd_topo_obj_laddr( (fd_topo_t const *)topo, cnc_obj_id );
    ctx->cnc = cnc_laddr;
    FD_LOG_NOTICE(( "tk_audit_stem: CNC joined, tile_id=%lu", tile->id ));

    /* Read event_count from CNC app region if set (idx=7, supervisor-provided). */
    ulong * app = (ulong *)fd_cnc_app_laddr( (fd_cnc_t *)cnc_laddr );
    if( app && app[7] > 0 ) {
      ctx->event_count = app[7];
      FD_LOG_NOTICE(( "tk_audit_stem: event_count=%lu from CNC", ctx->event_count ));
    }
  } else {
    FD_LOG_NOTICE(( "tk_audit_stem: CNC not found for tile_id=%lu", tile->id ));
  }

  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_unprivileged_init EXIT tile_id=%lu", tile->id ));
}

/* ---------------------------------------------------------------------
   tk_audit_during_frag — consume PaymentMessage, build audit record.
   Signature: (ctx, in_idx, seq, sig, chunk, sz, ctl)
   chunk is a dcache chunk offset — resolve via fd_chunk_to_laddr.
   wksp comes from ctx->wksp (set up in unprivileged_init).
   --------------------------------------------------------------------- */

#ifndef STEM_CALLBACK_DURING_FRAG
#define STEM_CALLBACK_DURING_FRAG tk_audit_during_frag
#endif

static void
tk_audit_during_frag( tk_audit_ctx_t * ctx,
                      ulong            in_idx,
                      ulong            seq,
                      ulong            sig,
                      ulong            chunk,
                      ulong            sz,
                      uint             ctl ) {
  (void)in_idx; (void)seq; (void)sig; (void)ctl;

  /* 1. Enforce event_count limit (skip if unbounded — event_count == 0) */
  if( ctx->event_count > 0 && ctx->audited >= ctx->event_count ) return;

  /* 2. Validate fragment size */
  if( sz != PAYMENT_MSG_SIZE ) return;

  /* 2. Decode PaymentMessage from fragment chunk.
     ctx->wksp is set in unprivileged_init from the input link's workspace.
     Use fd_chunk_to_laddr to resolve chunk offset. */
  void * chunk_laddr = fd_chunk_to_laddr( ctx->wksp, chunk );
  PaymentMessage const * msg = (PaymentMessage const *)chunk_laddr;

  /* 3. Update max_latency_hops */
  ulong hops = ((ulong)msg->pipeline_hops + 1);
  if( hops > ctx->max_latency_hops )
    ctx->max_latency_hops = hops;

  /* 4. Build audit event (hash-chained) */
  AuditEvent * ev = &ctx->scratch_event;
  memset( ev, 0, sizeof(AuditEvent) );

  ev->header.schema_version = AUDIT_SCHEMA_VERSION;
  ev->header.run_id = 0;
  ev->header.seq = ctx->audit_count;
  ev->header.source_offset = msg->raw.source_offset;
  memcpy( ev->header.tile_id, msg->decided_by, 6 );
  ev->header.logical_actor_id = 0;
  ev->header.timestamp_ns = 0;
  ev->header.prev_hash = ctx->prev_hash;

  ev->policy_decision.outcome = (PolicyOutcome)msg->decision;
  ev->policy_decision.rule_id = 0;
  ev->policy_decision.source_event_hash = msg->event_hash;

  /* Compute record_hash */
  {
    ulong h = AUDIT_SEED;
    h = (h ^ ev->header.seq) * 0x100000001b3ULL;
    h = (h ^ ev->header.source_offset) * 0x100000001b3ULL;
    h = (h ^ ev->header.prev_hash) * 0x100000001b3ULL;
    h = (h ^ (ulong)ev->policy_decision.outcome) * 0x100000001b3ULL;
    h = (h ^ ev->policy_decision.source_event_hash) * 0x100000001b3ULL;
    ev->header.record_hash = h;
  }

  /* 5. Write to audit array in scratch */
  if( ctx->audit_count < TKAUDT_AUDIT_CAPACITY ) {
    AuditEvent * records = (AuditEvent *)(
      (ulong)ctx + sizeof(tk_audit_ctx_t)
    );
    records[ ctx->audit_count ] = *ev;
    ctx->prev_hash = ev->header.record_hash;
    ctx->audit_count += 1;
    ctx->audited += 1;
    ctx->consecutive_empty = 0;
  } else {
    FD_LOG_NOTICE(( "tk_audit_stem: audit log full at count=%lu", ctx->audit_count ));
  }
}

/* ---------------------------------------------------------------------
   tk_audit_before_credit — idle tracking, no output links.
   Signature: (ctx, stem, charge_busy)
   --------------------------------------------------------------------- */

#ifndef STEM_CALLBACK_BEFORE_CREDIT
#define STEM_CALLBACK_BEFORE_CREDIT tk_audit_before_credit
#endif

static void
tk_audit_before_credit( tk_audit_ctx_t * ctx,
                        fd_stem_context_t * stem,
                        int * charge_busy ) {
  ctx->consecutive_empty += 1;
  /* If we already processed all events, exit immediately — don't wait
     for idle ticks. This lets tests and bounded runs complete promptly. */
  if( ctx->event_count > 0 && ctx->audited >= ctx->event_count ) {
    ctx->input_exhausted = 1;
    FD_LOG_NOTICE(( "tk_audit_stem: done after %lu events (limit=%lu)",
                    ctx->audited, ctx->event_count ));
  } else if( ctx->consecutive_empty >= TKAUDT_IDLE_THRESHOLD ) {
    ctx->input_exhausted = 1;
    FD_LOG_NOTICE(( "tk_audit_stem: input_exhausted after %lu idle ticks",
                    ctx->consecutive_empty ));
  }
  *charge_busy = 0;
  (void)stem;
}

/* ---------------------------------------------------------------------
   stem_run — generated via the fd_stem template.

   stem_run is compiled here with tk_audit_ctx_t as CONTEXT_TYPE.
   We do NOT override STEM_EXPORT, so it defaults to static (via the
   #ifndef in fd_stem.c).  This keeps stem_run internal to the tk_audit
   translation unit — only tk_audit_run() can call it.  tk_metric_tile.c
   exports its own stem_run compiled with fd_metric_ctx_t; the two
   symbols do not collide because only one is externally visible.
   --------------------------------------------------------------------- */

#define STEM_BURST (1UL)
#define STEM_LAZY ((long)10e6)

#define STEM_CALLBACK_CONTEXT_TYPE  tk_audit_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKAUDT_CTX_ALIGN

#define STEM_CALLBACK_BEFORE_CREDIT tk_audit_before_credit
#define STEM_CALLBACK_DURING_FRAG tk_audit_during_frag

/* Check CNC for HALT — matches the tk_metric pattern. */
#define STEM_CALLBACK_SHOULD_SHUTDOWN( ctx ) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "../../../disco/stem/fd_stem.c"

/* Clear STEM_EXPORT after the include so subsequent STEM instantiations
   (e.g. verify tile) see no STEM_EXPORT and use their own #ifndef
   STEM_EXPORT / #define STEM_EXPORT static blocks to default to static.
   This prevents duplicate stem_run symbols. */
#undef STEM_EXPORT

/* ---------------------------------------------------------------------
   tk_audit_run — calls stem_run directly.

   We set ctx->cnc before calling stem_run so stem_run's
   STEM_CALLBACK_SHOULD_SHUTDOWN can detect HALT from the supervisor.
   --------------------------------------------------------------------- */

static void
tk_audit_run( fd_topo_t *      topo,
              fd_topo_tile_t * tile ) {
  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_run ENTER tile_id=%lu", tile->id ));

  void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
  tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up(
    (ulong)scratch, TKAUDT_CTX_ALIGN );

  /* Find CNC and set ctx->cnc */
  ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
  if( cnc_obj_id != ULONG_MAX ) {
    void * cnc_laddr = fd_topo_obj_laddr( topo, cnc_obj_id );
    ctx->cnc = cnc_laddr;
    FD_LOG_NOTICE(( "tk_audit_stem: CNC joined in run, tile_id=%lu", tile->id ));

    /* Write event_count to CNC app region if set by supervisor (non-zero).
       When event_count == 0 (unset), the supervisor wrote the correct value
       to CNC app region before spawning; when event_count > 0, it was
       read from CNC in unprivileged_init. In both cases, the value is
       already in CNC — no write-back needed. */
  }

  stem_run( topo, tile );

  /* Write final audited count to CNC app counter (direct app region write) */
  if( ctx->cnc ) {
    ulong * app = (ulong *)fd_cnc_app_laddr( (fd_cnc_t *)ctx->cnc );
    if( app ) {
      app[0] = ctx->audited;
    }
  }

  FD_LOG_NOTICE(( "tk_audit_stem: tk_audit_run EXIT tile_id=%lu, audited=%lu",
                  tile->id, ctx->audited ));
}

/* ---------------------------------------------------------------------
   TK_AUDIT_RUN — the fd_topo_run_tile_t that Tickoni dispatches.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t TK_AUDIT_RUN = {
  .name                     = "tkaudt",
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
  .scratch_align            = tk_audit_scratch_align,
  .scratch_footprint        = tk_audit_scratch_footprint_tile,
  .loose_footprint          = NULL,
  .privileged_init          = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_audit_privileged_init,
  .unprivileged_init        = (void (*)( fd_topo_t const *, fd_topo_tile_t const * ))tk_audit_unprivileged_init,
  .run                      = tk_audit_run,
  .rlimit_file_cnt_fn       = NULL,
};

/* ---------------------------------------------------------------------
   tk_get_audit_run_tile — returns &TK_AUDIT_RUN.
   --------------------------------------------------------------------- */

fd_topo_run_tile_t *
tk_get_audit_run_tile( void ) {
  return &TK_AUDIT_RUN;
}

#endif /* FD_HAS_LINUX */
