/* tk_audit_stem.c — Stem fd_stem tile for tkaudt.

   Phase 1: wire the stem tile, verify it runs without crashing.
   Phase 3.2: build real audit events with hash chain (in-progress).

   Stem tile behavior:
   - DURING_FRAG: build AuditEvent from PaymentMessage, compute record_hash
     via SipHash1-3, store in scratch ring buffer, update prev_hash chain
   - SHOULD_SHUTDOWN: exit on the supervisor's CNC HALT signal
*/

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"

#include "../../../disco/topo/fd_topo.h"
#include "../../../ballet/siphash13/fd_siphash13.h"
#include "../../../util/wksp/fd_wksp.h"

#include <string.h>
#include <stddef.h>
#include <stdlib.h>

/* Fixed header values — not carried in PaymentMessage but needed for
   the audit record and its hash chain. */
#define AUDIT_RUN_ID        1ULL
#define AUDIT_LOGICAL_ACTOR 0ULL
#define AUDIT_POLICY_VER    "v1"

/* We need access to the topo helper function.
   tk_topo_run_tile.c declares tk_topo_find_tile_obj as an extern. */
extern ulong tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type );

/* ─── Context ───

   tk_audit_ctx_t MUST be defined BEFORE the STEM_CALLBACK_CONTEXT_TYPE
   macro expansion in fd_stem.c. fd_stem.c uses this type to declare
   'ctx' in its stem_run function, so it must be a complete type at
   the point of the #include. */
typedef struct {
    /* Audit state */
    uint64_t audited;           /* Total fragments processed */

    /* CNC reference for shutdown detection and progress reporting */
    void     *cnc;

    /* Scratch-allocated audit records ring buffer */
    uint64_t audit_count;
    uint64_t prev_hash;

    /* Tile pointer for allow_shutdown */
    fd_topo_tile_t const *tile;

    /* Scratch-allocated audit record ring buffer pointer.
       Points into scratch space (computed in privileged_init). */
    AuditEvent *audit_records;

    /* Workspace pointer for chunk-to-laddr conversion in DURING_FRAG.
       Set in privileged_init from the tile's workspace ID. */
    void *wksp;

    /* Event count gating (Phase 3.4).
       Set from TKAUDT_EVENT_COUNT env var. Tile exits when
       audited >= event_count, regardless of idle ticks. */
    uint64_t event_count;
    int32_t  input_exhausted;
} tk_audit_ctx_t;

#define TKAUDT_CTX_ALIGN alignof(tk_audit_ctx_t)
#define TKAUDT_AUDIT_CAPACITY 16384

/* Audit hash seed — initial prev_hash value. */
#define AUDIT_SEED 0xDEADBEEF

/* Forward declarations for Firedancer callback typedefs (2 params each).
   All callback functions MUST be static — they are used by the
   STEM_CALLBACK_* macros which fd_stem.c expands into calls within
   stem_run. If they were non-static, fd_stem.c's implicit declaration
   would conflict with these static definitions.

   DURING_FRAG needs a forward declaration because fd_stem.c calls it
   before the static definition below. privileged_init/unprivileged_init do
   not need forward declarations for the template; Firedancer infrastructure
   calls them directly. */
static void tk_audit_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tk_audit_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile );
static void tk_audit_during_frag( tk_audit_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                   ulong chunk, ulong sz, ulong ctl );
static void tk_audit_run( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Generate an audit-specific static stem specialization. */
#define STEM_NAME         tkaudt
#define STEM_BURST        (1UL)
#define STEM_LAZY         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE  tk_audit_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKAUDT_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG   tk_audit_during_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "../../../disco/metrics/fd_metrics.h"
#include "../../../disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint ─── */

static ulong
tk_audit_scratch_align( void ) {
    return TKAUDT_CTX_ALIGN;
}

static ulong
tk_audit_scratch_footprint_tile( fd_topo_tile_t const * tile ) {
    (void)tile;
    ulong footprint = fd_ulong_align_up( sizeof(tk_audit_ctx_t), TKAUDT_CTX_ALIGN );
    /* audit_records follows the aligned context in the same scratch object. */
    footprint = fd_ulong_align_up( footprint, alignof(AuditEvent) );
    footprint += sizeof(AuditEvent) * TKAUDT_AUDIT_CAPACITY;
    return footprint;
}

/* No-argument wrapper — delegates to tk_audit_scratch_footprint_tile( NULL ).
   Provides a thin accessor for topob.c so it never needs the full
   fd_topo_run_tile_t definition. */
ulong
tk_audit_scratch_footprint( void ) {
    return tk_audit_scratch_footprint_tile( NULL );
}

/* ─── Callbacks ───

   privileged_init / unprivileged_init match the Firedancer typedef
   (fd_topo_run_tile_t.privileged_init and .unprivileged_init).
   They take 2 params: (fd_topo_t const *, fd_topo_tile_t const *).

   ctx is retrieved from scratch via fd_topo_obj_laddr(topo, tile->tile_obj_id).
   This matches the tk_metric_tile.c pattern exactly.
*/

static void
tk_audit_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* Scratch is already zeroed by Firedancer. Initialize explicitly. */
    ctx->audited = 0;
    ctx->cnc = NULL;
    ctx->audit_count = 0;
    ctx->prev_hash = AUDIT_SEED;
    ctx->tile = tile;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;

    /* Read event_count from environment (Phase 3.4).
       Supervisor passes TKAUDT_EVENT_COUNT so the tile can exit
       promptly after processing all events, without idle-threshold wait. */
    {
        const char *env = getenv("TKAUDT_EVENT_COUNT");
        if (env) {
            ctx->event_count = strtoull(env, NULL, 10);
            FD_LOG_NOTICE(( "tkaudt: event_count=%lu from env", (unsigned long)ctx->event_count ));
        }
    }

    /* Point audit_records at the scratch block that follows the context.
       This is the same memory region reserved by scratch_footprint_tile. */
    ulong ctx_end = fd_ulong_align_up( (ulong)ctx + sizeof(tk_audit_ctx_t), alignof(AuditEvent) );
    ctx->audit_records = (AuditEvent *)ctx_end;

    /* Derive workspace pointer from the tile's input link mcache.
       The mcache is set by fd_topo_fill_tile as a real local address
       in this tile process. fd_wksp_containing(mcache) returns the
       correct workspace pointer for THIS process. */
    ulong in_link_id = tile->in_link_id[0];
    fd_topo_link_t const * link = &topo->links[ in_link_id ];
    void * mcache = fd_topo_obj_laddr( (fd_topo_t *)topo, link->mcache_obj_id );
    ctx->wksp = (void *)fd_wksp_containing( mcache );

    FD_LOG_NOTICE(( "tkaudt: privileged init ctx=%p records=%p wksp=%p count=%lu",
                    ctx, ctx->audit_records, ctx->wksp, (unsigned long)TKAUDT_AUDIT_CAPACITY ));
}

static void
tk_audit_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    /* ctx lives in scratch. MUST match stem_run's alignment. */
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* Find the CNC for this tile and set ctx->cnc for shutdown detection. */
    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, (ulong)tile->id, "cnc" );
    if( cnc_obj_id != ULONG_MAX ) {
        void * cnc_laddr = fd_topo_obj_laddr( (fd_topo_t *)topo, cnc_obj_id );
        ctx->cnc = cnc_laddr;
        FD_LOG_NOTICE(( "tkaudt: stem tile unprivileged init found CNC obj_id=%lu", cnc_obj_id ));
    }
    FD_LOG_NOTICE(( "tkaudt: stem tile unprivileged init, tile_id=%lu cnc=%p",
                    tile->id, ctx->cnc ));
}

/* ─── Record hash ───

   Computes the record_hash for an AuditEvent using SipHash1-3 over the
   same field sequence as Zig's computeWireRecordHash.  The hash does NOT
   include timestamp_ns — it is deliberately excluded so that replay
   substitution (which zero-fills timestamp_ns) does not break the chain.

   Field order (must match hash.zig exactly):
     schema_version, run_id, seq, source_offset, tile_id,
     logical_actor_id, policy_version, capability_envelope_id_le,
     prev_hash, version, platform_tier, isolation_tier,
     release_digest, manifest_id, record_type, payload fields
*/
static uint64_t
tk_audit_compute_record_hash( AuditEvent * event ) {
    fd_siphash13_t  sip[1];

    fd_siphash13_init( sip, 0x0000544455414B55ULL, 2ULL );

    /* Header fields — these map 1:1 to wire.Header fields.
       capability_envelope_id_le: the C struct stores a u64, wire stores
       a [16]u8 LE.  For the stub we hash the u64 as-is (identity for
       values < 2^64, zero-extended on the wire side). */
    fd_siphash13_append( sip, (uchar *)&event->header.schema_version, sizeof(event->header.schema_version) );
    fd_siphash13_append( sip, (uchar *)&event->header.run_id,          sizeof(event->header.run_id) );
    fd_siphash13_append( sip, (uchar *)&event->header.seq,             sizeof(event->header.seq) );
    fd_siphash13_append( sip, (uchar *)&event->header.source_offset,   sizeof(event->header.source_offset) );
    fd_siphash13_append( sip, event->header.tile_id,                   sizeof(event->header.tile_id) );
    fd_siphash13_append( sip, (uchar *)&event->header.logical_actor_id,sizeof(event->header.logical_actor_id) );
    fd_siphash13_append( sip, event->header.policy_version,            sizeof(event->header.policy_version) );
    /* capability_envelope_id_le — C stores u64, wire stores [16]u8.
       Hash the full 16-byte wire layout by treating the u64 as 8 bytes
       of LE and 8 zero bytes (wire zero-extends the u128 -> [16]u8). */
    {
        uint8_t le16[16];
        ulong   cap_id = event->header.capability_envelope_id;
        memcpy( le16, &cap_id, 8 );
        memset( le16 + 8, 0, 8 );
        fd_siphash13_append( sip, le16, sizeof(le16) );
    }
    fd_siphash13_append( sip, (uchar *)&event->header.prev_hash,       sizeof(event->header.prev_hash) );
    fd_siphash13_append( sip, event->header.version,                   sizeof(event->header.version) );
    fd_siphash13_append( sip, event->header.platform_tier,             sizeof(event->header.platform_tier) );
    fd_siphash13_append( sip, event->header.isolation_tier,            sizeof(event->header.isolation_tier) );
    fd_siphash13_append( sip, event->header.release_digest,            sizeof(event->header.release_digest) );
    fd_siphash13_append( sip, event->header.manifest_id,               sizeof(event->header.manifest_id) );

    /* Discriminant — matches wire.Event.record_type (u8). */
    fd_siphash13_append( sip, (uchar *)&event->record_type, sizeof(event->record_type) );

    /* Payload for policy_decision (record_type == 2).
       Matches wire.PolicyDecisionPayload field order:
         outcome(u8), rule_id(u32), failed_scope_dim(32),
         source_event_hash(u64), catalog_schema_version(u32),
         taxonomy_id(32), taxonomy_version(u32),
         classification_code(32).  Hash outcome as u8 (backing size
       of PolicyOutcome enum) to match wire.PolicyDecisionPayload. */
    uint8_t outcome_u8 = (uint8_t)event->policy_decision.outcome;

    fd_siphash13_append( sip, &outcome_u8, sizeof(outcome_u8) );
    fd_siphash13_append( sip, (uchar *)&event->policy_decision.rule_id,
                         sizeof(event->policy_decision.rule_id) );
    fd_siphash13_append( sip, event->policy_decision.failed_scope_dim,
                         sizeof(event->policy_decision.failed_scope_dim) );
    fd_siphash13_append( sip, (uchar *)&event->policy_decision.source_event_hash,
                         sizeof(event->policy_decision.source_event_hash) );
    fd_siphash13_append( sip, (uchar *)&event->policy_decision.catalog_schema_version,
                         sizeof(event->policy_decision.catalog_schema_version) );
    fd_siphash13_append( sip, event->policy_decision.taxonomy_id,
                         sizeof(event->policy_decision.taxonomy_id) );
    fd_siphash13_append( sip, (uchar *)&event->policy_decision.taxonomy_version,
                         sizeof(event->policy_decision.taxonomy_version) );
    fd_siphash13_append( sip, event->policy_decision.classification_code,
                         sizeof(event->policy_decision.classification_code) );

    return fd_siphash13_fini( sip );
}

static void
tk_audit_during_frag( tk_audit_ctx_t * ctx,
                      ulong            in_idx,
                      ulong            seq,
                      ulong            sig,
                      ulong            chunk,
                      ulong            sz,
                      ulong            ctl ) {
    (void)in_idx; (void)seq; (void)sig; (void)ctl;

    /* fd_stem validates that the fragment fits the input link MTU before
       invoking this callback. */
    if( FD_UNLIKELY( !sz ) ) {
        FD_LOG_WARNING(( "tkaudt: empty fragment" ));
        return;
    }

    /* Validate fragment size */
    if( FD_UNLIKELY( sz != PAYMENT_MSG_SIZE ) ) {
        FD_LOG_WARNING(( "tkaudt: fragment size %zu != expected %u", sz, (unsigned)PAYMENT_MSG_SIZE ));
        return;
    }

    /* `chunk` is a Firedancer compact chunk index, not a workspace gaddr.
       The process-mode producer stores `gaddr / FD_CHUNK_ALIGN` in the
       mcache, so restore the gaddr before resolving it in this process. */
    if( FD_UNLIKELY( !ctx->wksp ) ) {
        FD_LOG_WARNING(( "tkaudt: wksp not initialized" ));
        return;
    }
    PaymentMessage const * msg = (PaymentMessage const *)fd_wksp_laddr_fast( ctx->wksp, chunk * FD_CHUNK_ALIGN );

    /* Build AuditEvent in the next scratch slot. */
    if( ctx->audit_count >= TKAUDT_AUDIT_CAPACITY ) {
        FD_LOG_WARNING(( "tkaudt: audit ring buffer full at %lu", ctx->audit_count ));
        return;
    }
    AuditEvent * event = &ctx->audit_records[ctx->audit_count];
    memset( event, 0, sizeof(*event) );

    /* Populate header from available sources.
       PaymentMessage provides: source_offset, event_hash,
       decision, decided_by, pipeline_hops.
       Fixed constants provide: run_id, logical_actor, policy_version.
       header.seq is set from audit_count for ordering. */
    event->header.schema_version  = AUDIT_SCHEMA_VERSION;
    event->header.run_id          = AUDIT_RUN_ID;
    event->header.seq             = ctx->audit_count;
    event->header.source_offset   = msg->raw.source_offset;
    memcpy( event->header.tile_id, msg->decided_by, sizeof(msg->decided_by) );
    event->header.logical_actor_id = AUDIT_LOGICAL_ACTOR;
    memcpy( event->header.policy_version, AUDIT_POLICY_VER,
            sizeof(AUDIT_POLICY_VER) );
    event->header.capability_envelope_id = 0; /* stub: no envelope */
    event->header.timestamp_ns       = 0;
    event->header.prev_hash          = ctx->prev_hash;
    event->header.record_hash        = 0; /* set after hash computation */
    memset( event->header.version,       0, sizeof(event->header.version) );
    memset( event->header.platform_tier, 0, sizeof(event->header.platform_tier) );
    memset( event->header.isolation_tier, 0, sizeof(event->header.isolation_tier) );
    memset( event->header.release_digest, 0, sizeof(event->header.release_digest) );
    memset( event->header.manifest_id,   0, sizeof(event->header.manifest_id) );

    /* Populate payload — this is a policy_decision record. */
    event->record_type       = RECORD_POLICY_DECISION;
    memset( &event->policy_decision, 0, sizeof(event->policy_decision) );
    event->policy_decision.outcome         = (PolicyOutcome)msg->decision;
    event->policy_decision.rule_id         = 0; /* stub */
    event->policy_decision.source_event_hash = msg->event_hash;
    /* failed_scope_dim, taxonomy_id, etc. are zeroed by memset above. */

    /* Compute record_hash and update chain. */
    event->header.record_hash = tk_audit_compute_record_hash( event );
    ctx->prev_hash            = event->header.record_hash;

    /* Advance counter. */
    ctx->audit_count += 1;
    ctx->audited += 1;

    /* Event-count gating (Phase 3.4): exit promptly after processing
       all expected events. When event_count is 0 (env not set), skip. */
    if( ctx->event_count && ctx->audited >= ctx->event_count ) {
        ctx->input_exhausted = 1;
    }

    /* Publish progress to CNC app[0] for supervisor snapshots. */
    if( ctx->cnc ) {
        ulong * app = (ulong *)fd_cnc_app_laddr( (fd_cnc_t *)ctx->cnc );
        if( app ) app[0] = ctx->audited;
    }
}

/* ─── Run entry point ───

   This is the tk_audit_run callback. Firedancer infrastructure calls
   privileged_init, then unprivileged_init, then this run function.

   Pattern from tk_metric_tile.c:
   1. Find scratch space via fd_topo_obj_laddr(topo, tile->tile_obj_id)
   2. Cast to ctx type
   3. Find CNC object and set ctx->cnc (for shutdown detection)
   4. Enter the audit-specific tkaudt_run loop
*/

static void
tk_audit_run( fd_topo_t *      topo,
              fd_topo_tile_t * tile ) {
    void * scratch = fd_topo_obj_laddr( topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = (tk_audit_ctx_t *)fd_ulong_align_up( (ulong)scratch, TKAUDT_CTX_ALIGN );

    /* The stem shutdown callback reads the tile CNC. */
    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id==ULONG_MAX ) )
        FD_LOG_ERR(( "tkaudt: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    /* Run the stem loop.  Stem exits when SHOULD_SHUTDOWN returns true. */
    tkaudt_run( topo, tile );
}

/* ─── fd_topo_run_tile_t ─── */

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
    .privileged_init          = tk_audit_privileged_init,
    .unprivileged_init        = tk_audit_unprivileged_init,
    .run                      = tk_audit_run,
    .rlimit_file_cnt_fn       = NULL,
};

fd_topo_run_tile_t const *
tk_get_audit_run_tile( void ) {
    return &TK_AUDIT_RUN;
}
