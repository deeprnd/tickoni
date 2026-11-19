/* tk_audit_stem.c — Stem fd_stem tile for tkaudt.

   Phase 1: wire the stem tile, verify it runs without crashing.
   Phase 3.2: build real audit events with hash chain (in-progress).

   Stem tile behavior, per the fd_stem callback contract in stem_helpers.h:
   - DURING_FRAG: validate framing and build the AuditEvent into the next,
     still-uncommitted ring slot, leaving seq/prev_hash/record_hash unset.
     Commits nothing: audit_count and prev_hash are untouched, so a fragment
     fd_stem later abandons as an overrun leaves only an unobserved slot that
     the next fragment overwrites.
   - AFTER_FRAG: stamp seq and prev_hash, compute record_hash via SipHash1-3,
     advance the hash chain and audit_count, bump counters, publish progress,
     apply the event gate.  tkaudt is a sink (out_cnt == 0), so AFTER_FRAG
     ends without a publish.
   - AFTER_CREDIT: not defined — tkaudt has no fragment-independent work.
   - SHOULD_SHUTDOWN: exit on the supervisor's CNC HALT signal
*/

#define _GNU_SOURCE

#include "firedancer.h"
#include "audit_schema.h"
#include "tickoni/c_abi/shim/stem_helpers.h"

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

    /* Staging flag: set by DURING_FRAG once the record is built into the
       uncommitted ring slot, cleared by AFTER_FRAG once it is committed. */
    int32_t  stage_valid;
} tk_audit_ctx_t;

#define TKAUDT_CTX_ALIGN alignof(tk_audit_ctx_t)
#define TKAUDT_AUDIT_CAPACITY 16384

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
static void tk_audit_after_frag( tk_audit_ctx_t * ctx, ulong in_idx, ulong seq, ulong sig,
                                  ulong sz, ulong tsorig, ulong tspub, fd_stem_context_t * stem );
static void tk_audit_run( fd_topo_t * topo, fd_topo_tile_t * tile );

/* Generate an audit-specific static stem specialization. */
#define STEM_NAME         tkaudt
#define STEM_BURST        (1UL)
#define STEM_LAZY         ((long)10e6)
#define STEM_CALLBACK_CONTEXT_TYPE  tk_audit_ctx_t
#define STEM_CALLBACK_CONTEXT_ALIGN TKAUDT_CTX_ALIGN
#define STEM_CALLBACK_DURING_FRAG   tk_audit_during_frag
#define STEM_CALLBACK_AFTER_FRAG    tk_audit_after_frag
#define STEM_CALLBACK_SHOULD_SHUTDOWN(ctx) \
  ( (ctx)->input_exhausted || \
    ( (ctx)->cnc && fd_cnc_signal_query( (fd_cnc_t *)(ctx)->cnc ) == FD_CNC_SIGNAL_HALT ) )

#include "../../../disco/metrics/fd_metrics.h"
#include "../../../disco/stem/fd_stem.c"

#undef STEM_NAME
#undef STEM_CALLBACK_CONTEXT_TYPE
#undef STEM_CALLBACK_CONTEXT_ALIGN
#undef STEM_CALLBACK_DURING_FRAG
#undef STEM_CALLBACK_AFTER_FRAG
#undef STEM_CALLBACK_SHOULD_SHUTDOWN

/* ─── Scratch footprint and alignment ─── */

/* Alignment of the whole tile scratch object: the context and the audit-record
   ring both live in this one block, which tk_audit_scratch_footprint_tile()
   lays out from offset 0, so the object's base must satisfy the strictest of
   them.  Derived from the context struct rather than restated as a literal —
   this is the single definition of tkaudt's scratch alignment, and topob.c
   reads it back through tk_audit_scratch_align(). */
static ulong
tk_audit_scratch_align_tile( void ) {
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

/* ─── Event count setter (set by topo_build.build() before topology queries) ─── */

static ulong tkaudit_event_count_param = 0UL;

void
tkaudit_set_event_count( ulong event_count ) {
    tkaudit_event_count_param = event_count;
}

/* ─── Callbacks ───

   privileged_init / unprivileged_init match the Firedancer typedef
   (fd_topo_run_tile_t.privileged_init and .unprivileged_init).
   They take 2 params: (fd_topo_t const *, fd_topo_tile_t const *).

   ctx is retrieved from scratch via fd_topo_obj_laddr(topo, tile->tile_obj_id).
   This matches the tk_metric_tile.c pattern exactly.
*/

/* The record array sits directly after the context in the tile's scratch
   object.  This is the single definition of that offset: privileged_init uses
   it to set ctx->audit_records, and the test accessors below use it to find
   the array from a scratch base.  They cannot share ctx->audit_records —
   that pointer is an address in the tile process, and the supervisor maps the
   same workspace at a different base, so a cross-process read must recompute
   the offset from its own scratch pointer. */
static inline AuditEvent *
tk_audit_records_of( tk_audit_ctx_t * ctx ) {
    return (AuditEvent *)fd_ulong_align_up( (ulong)ctx + sizeof(tk_audit_ctx_t),
                                            alignof(AuditEvent) );
}

static void
tk_audit_privileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);

    /* Scratch is already zeroed by Firedancer. Initialize explicitly. */
    ctx->audited = 0;
    ctx->cnc = NULL;
    ctx->audit_count = 0;
    ctx->prev_hash = AUDIT_INITIAL_HASH;
    ctx->tile = tile;
    ctx->event_count = 0;
    ctx->input_exhausted = 0;
    ctx->stage_valid = 0;

    /* Event count for shutdown gating (Phase 3.4).
       Set by topo_build.build() via tkaudit_set_event_count() —
       same C-param pattern as tkdedu to avoid the env var anti-pattern:
       getenv() in privileged_init reads each child's own environment,
       which can differ from the supervisor's. */
    ctx->event_count = tkaudit_event_count_param;

    /* Point audit_records at the scratch block that follows the context.
       This is the same memory region reserved by scratch_footprint_tile. */
    ctx->audit_records = tk_audit_records_of( ctx );

    /* Derive workspace pointer from the tile's input link mcache. */
    ctx->wksp = stk_derive_wksp(topo, tile, 0);

    FD_LOG_NOTICE(( "tkaudt: privileged init ctx=%p records=%p wksp=%p count=%lu",
                    ctx, ctx->audit_records, ctx->wksp, (unsigned long)TKAUDT_AUDIT_CAPACITY ));
}

static void
tk_audit_unprivileged_init( fd_topo_t const * topo, fd_topo_tile_t const * tile ) {
    (void)topo;
    (void)tile;

    /* ctx lives in scratch. MUST match stem_run's alignment. */
    void * scratch = fd_topo_obj_laddr( (fd_topo_t *)topo, tile->tile_obj_id );
    tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);

    /* Find the CNC for this tile and set ctx->cnc for shutdown detection. */
    STK_UNPRIV_INIT(topo, tile, ctx);

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
     logical_actor_id, policy_version, capability_envelope_id (u64),
     prev_hash, version, platform_tier, isolation_tier,
     release_digest, manifest_id, record_type, payload fields
*/
static uint64_t
tk_audit_compute_record_hash( AuditEvent * event ) {
    fd_siphash13_t  sip[1];

    fd_siphash13_init( sip, AUDIT_HASH_K0, AUDIT_HASH_K1 );

    /* Header fields — these map 1:1 to wire.Header fields (the C
       AuditHeader is the wire header). capability_envelope_id is a u64 in
       that header and codec/audit/hash.zig hashes its 8 bytes, so C does the
       same.  An earlier version hashed a 16-byte zero-extended layout that no
       longer exists on the wire, which made every C record hash differ from
       the Zig codec's (owner-approved correction; see the tkmodl migration
       plan). */
    fd_siphash13_append( sip, (uchar *)&event->header.schema_version, sizeof(event->header.schema_version) );
    fd_siphash13_append( sip, (uchar *)&event->header.run_id,          sizeof(event->header.run_id) );
    fd_siphash13_append( sip, (uchar *)&event->header.seq,             sizeof(event->header.seq) );
    fd_siphash13_append( sip, (uchar *)&event->header.source_offset,   sizeof(event->header.source_offset) );
    fd_siphash13_append( sip, event->header.tile_id,                   sizeof(event->header.tile_id) );
    fd_siphash13_append( sip, (uchar *)&event->header.logical_actor_id,sizeof(event->header.logical_actor_id) );
    fd_siphash13_append( sip, event->header.policy_version,            sizeof(event->header.policy_version) );
    fd_siphash13_append( sip, (uchar *)&event->header.capability_envelope_id,
                         sizeof(event->header.capability_envelope_id) );
    fd_siphash13_append( sip, (uchar *)&event->header.prev_hash,       sizeof(event->header.prev_hash) );
    fd_siphash13_append( sip, event->header.version,                   sizeof(event->header.version) );
    fd_siphash13_append( sip, event->header.platform_tier,             sizeof(event->header.platform_tier) );
    fd_siphash13_append( sip, event->header.isolation_tier,            sizeof(event->header.isolation_tier) );
    fd_siphash13_append( sip, event->header.release_digest,            sizeof(event->header.release_digest) );
    fd_siphash13_append( sip, event->header.manifest_id,               sizeof(event->header.manifest_id) );

    /* Discriminant — matches wire.Event.record_type (u8). */
    fd_siphash13_append( sip, (uchar *)&event->record_type, sizeof(event->record_type) );

    switch( event->record_type ) {
    case RECORD_MODEL_CALL: {
        /* Matches hash.zig case 3 (wire.ModelCallPayload field order). */
        WireModelCallPayload const * p = &event->model_call;
        fd_siphash13_append( sip, p->model_id,                  sizeof(p->model_id) );
        fd_siphash13_append( sip, (uchar *)&p->prompt_hash,     sizeof(p->prompt_hash) );
        fd_siphash13_append( sip, (uchar *)&p->response_hash,   sizeof(p->response_hash) );
        fd_siphash13_append( sip, (uchar *)&p->token_estimate,  sizeof(p->token_estimate) );
        fd_siphash13_append( sip, (uchar *)&p->retry_count,     sizeof(p->retry_count) );
        fd_siphash13_append( sip, p->actor_role,                sizeof(p->actor_role) );
        fd_siphash13_append( sip, p->workflow,                  sizeof(p->workflow) );
        fd_siphash13_append( sip, (uchar *)&p->policy_decision_id,    sizeof(p->policy_decision_id) );
        fd_siphash13_append( sip, (uchar *)&p->replay_substitution_id, sizeof(p->replay_substitution_id) );
        break;
    }
    case RECORD_DENIAL: {
        /* Matches hash.zig case 9 (wire.DenialPayload field order). */
        WireDenialPayload const * p = &event->denial;
        fd_siphash13_append( sip, p->action_class,                 sizeof(p->action_class) );
        fd_siphash13_append( sip, (uchar *)&p->reason_code,        sizeof(p->reason_code) );
        fd_siphash13_append( sip, p->failed_scope_dim,             sizeof(p->failed_scope_dim) );
        fd_siphash13_append( sip, (uchar *)&p->catalog_schema_version, sizeof(p->catalog_schema_version) );
        fd_siphash13_append( sip, p->taxonomy_id,                  sizeof(p->taxonomy_id) );
        fd_siphash13_append( sip, (uchar *)&p->taxonomy_version,   sizeof(p->taxonomy_version) );
        fd_siphash13_append( sip, p->classification_code,          sizeof(p->classification_code) );
        break;
    }
    default: {
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
        break;
    }
    }

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
    (void)in_idx; (void)seq; (void)ctl;

    /* Clear first: fd_stem may skip AFTER_FRAG for this fragment (reading
       overrun), and a stale stage_valid would let the next AFTER_FRAG commit
       a record built from an abandoned fragment. */
    ctx->stage_valid = 0;

    /* The audit link's sig says what record it carries.  Anything other than
       the payment-pipeline sig or a tkmodl record sig is not a record this
       tile knows how to audit: reject it rather than guess. */
    int is_model = ( sig==TK_LINK_SIG_MODEL_CALL || sig==TK_LINK_SIG_MODEL_DENIAL );
    if( FD_UNLIKELY( !is_model && sig!=TK_LINK_SIG_PAYMENT ) )
        return;

    /* Shared boilerplate: empty check, size check, wksp check, chunk→gaddr */
    if( !stk_validate_frag(sz, is_model ? sizeof(ModelAuditMsg) : PAYMENT_MSG_SIZE, ctx->wksp) )
        return;

    /* Bounds-check the staging target before writing to it. */
    if( ctx->audit_count >= TKAUDT_AUDIT_CAPACITY ) {
        FD_LOG_WARNING(( "tkaudt: audit ring buffer full at %lu", ctx->audit_count ));
        return;
    }

    /* Build into the next ring slot, which is still uncommitted: audit_count
       has not advanced, so nothing — not the Zig test harness, not a later
       record's chain — observes this slot yet.  seq, prev_hash and
       record_hash are deliberately left for AFTER_FRAG, so the chain is read
       and advanced in one place. */
    AuditEvent * event = &ctx->audit_records[ctx->audit_count];
    memset( event, 0, sizeof(*event) );

    event->header.schema_version  = AUDIT_SCHEMA_VERSION;
    event->header.run_id          = AUDIT_RUN_ID;
    event->header.logical_actor_id = AUDIT_LOGICAL_ACTOR;
    event->header.timestamp_ns    = 0;
    /* version, platform_tier, isolation_tier, release_digest and manifest_id
       stay zero from the memset above. */

    if( is_model ) {
        ModelAuditMsg const * msg = stk_chunk_to_gaddr(ctx->wksp, chunk);
        ModelAuditMsg m;
        memcpy( &m, msg, sizeof(m) );   /* one copy: validate and build from it */
        if( m.version!=TKMODL_WIRE_VERSION ||
            (ulong)m.record_type!=sig )
            return;

        event->header.run_id          = m.run_id;
        event->header.source_offset   = m.request_id;
        memcpy( event->header.tile_id, TILE_ID_TKMODL, sizeof(event->header.tile_id) );
        memcpy( event->header.policy_version, m.policy_version,
                sizeof(event->header.policy_version) );
        event->header.capability_envelope_id = m.capability_envelope_hash;
        event->record_type = m.record_type;
        if( m.record_type==RECORD_MODEL_CALL )
            event->model_call = m.payload.model_call;
        else
            event->denial = m.payload.denial;
        ctx->stage_valid = 1;
        return;
    }

    PaymentMessage const * msg = stk_chunk_to_gaddr(ctx->wksp, chunk);

    /* Populate header from available sources.
       PaymentMessage provides: source_offset, event_hash,
       decision, decided_by, pipeline_hops.
       Fixed constants provide: run_id, logical_actor, policy_version. */
    event->header.source_offset   = msg->raw.source_offset;
    memcpy( event->header.tile_id, msg->decided_by, sizeof(msg->decided_by) );
    memcpy( event->header.policy_version, AUDIT_POLICY_VER,
            sizeof(AUDIT_POLICY_VER) );
    event->header.capability_envelope_id = 0; /* stub: no envelope */

    /* Populate payload — this is a policy_decision record. */
    event->record_type       = RECORD_POLICY_DECISION;
    event->policy_decision.outcome         = (PolicyOutcome)msg->decision;
    event->policy_decision.rule_id         = 0; /* stub */
    event->policy_decision.source_event_hash = msg->event_hash;
    /* failed_scope_dim, taxonomy_id, etc. are zeroed by memset above. */

    ctx->stage_valid = 1;
}

/* AFTER_FRAG is the commit point: the first callback fd_stem reaches after
   its post-DURING_FRAG overrun re-check, so the only place the staged record
   is known to have been built from an intact fragment.  Appending and
   advancing prev_hash here is what keeps the chain over authenticated events
   only — an append-only hash chain cannot withdraw a record built from a torn
   read.  tkaudt is a sink, so there is no publish. */
static void
tk_audit_after_frag( tk_audit_ctx_t *    ctx,
                     ulong               in_idx,
                     ulong               seq,
                     ulong               sig,
                     ulong               sz,
                     ulong               tsorig,
                     ulong               tspub,
                     fd_stem_context_t * stem ) {
    (void)in_idx; (void)seq; (void)sig; (void)sz; (void)tsorig; (void)tspub; (void)stem;

    if( !ctx->stage_valid )
        return;
    ctx->stage_valid = 0;

    AuditEvent * event = &ctx->audit_records[ctx->audit_count];

    /* Chain position and chain link, read and advanced together. */
    event->header.seq       = ctx->audit_count;
    event->header.prev_hash = ctx->prev_hash;

    event->header.record_hash = tk_audit_compute_record_hash( event );
    ctx->prev_hash            = event->header.record_hash;

    /* Commit: the slot becomes observable only once audit_count advances. */
    ctx->audit_count += 1;
    ctx->audited += 1;

    /* Event-count gating: checked against the post-increment count so the
       gate fires on the Nth fragment and the tile exits promptly. */
    STK_EVENT_EXHAUSTED(ctx, ctx->event_count, ctx->audited);

    /* Publish progress to CNC app[0] for supervisor snapshots. */
    stk_publish_counter(ctx->cnc, 0UL, ctx->audited);
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
    tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);

    /* The stem shutdown callback reads the tile CNC. */
    ulong cnc_obj_id = tk_topo_find_tile_obj( topo, tile->id, "cnc" );
    if( FD_UNLIKELY( cnc_obj_id==ULONG_MAX ) )
        FD_LOG_ERR(( "tkaudt: CNC object not found for tile %lu", tile->id ));
    ctx->cnc = fd_topo_obj_laddr( topo, cnc_obj_id );

    /* Run the stem loop.  Stem exits when SHOULD_SHUTDOWN returns true. */
    tkaudt_run( topo, tile );

    /* Signal to Firedancer dispatch (fd_topo_run_tile / tk_topo_run_tile)
       that the tile exited cleanly. The dispatch resets allow_shutdown=0
       before calling run(), then checks it after — crash if still 0. */
    tile->allow_shutdown = 1;
}

/* ─── fd_topo_run_tile_t ─── */

fd_topo_run_tile_t TK_AUDIT_RUN = {
    .name                     = TILE_ID_TKAUDT,
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
    .scratch_align            = tk_audit_scratch_align_tile,
    .scratch_footprint        = tk_audit_scratch_footprint_tile,
    .loose_footprint          = NULL,
    .privileged_init          = tk_audit_privileged_init,
    .unprivileged_init        = tk_audit_unprivileged_init,
    .run                      = tk_audit_run,
    .rlimit_file_cnt_fn       = NULL,
};

STK_DEFINE_RUN_TILE_ACCESSORS(
    tk_get_audit,
    TK_AUDIT_RUN,
    tk_audit_scratch_align,
    tk_audit_scratch_footprint
)

/* ─── Audit record accessors for tests ───

   These keep the Zig side free of any tk_audit_ctx_t or AuditEvent layout
   knowledge: this file owns its scratch layout and exposes individual
   fields, so no Zig struct mirrors a C struct.  Same approach as
   tk_dedu_stem.c and tk_normalize_stem.c.

   The accessors abort on an out-of-range index instead of returning a
   sentinel, because 0 is a legitimate value for seq and prev_hash and a
   silent sentinel would turn a harness bug into a passing assertion. */

/* Committed record count.  Records beyond this index exist in scratch but
   are uncommitted staging slots — see the DURING_FRAG/AFTER_FRAG split. */
ulong
tk_audit_record_count( void * scratch ) {
    tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);
    return ctx->audit_count;
}

static AuditEvent const *
tk_audit_record_at( void * scratch, ulong idx ) {
    tk_audit_ctx_t * ctx = STK_GET_CTX(tk_audit_ctx_t, scratch, TKAUDT_CTX_ALIGN);
    if( FD_UNLIKELY( idx>=ctx->audit_count ) )
        FD_LOG_ERR(( "tkaudt: audit record index %lu out of range (committed %lu)",
                     idx, ctx->audit_count ));
    /* Recompute from the caller's scratch base, not ctx->audit_records: the
       supervisor reads this from a different process, where the tile's stored
       pointer does not resolve. */
    return &tk_audit_records_of( ctx )[idx];
}

ulong
tk_audit_record_seq( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->header.seq;
}

ulong
tk_audit_record_prev_hash( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->header.prev_hash;
}

ulong
tk_audit_record_hash( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->header.record_hash;
}

uint
tk_audit_record_schema_version( void * scratch, ulong idx ) {
    return (uint)tk_audit_record_at( scratch, idx )->header.schema_version;
}

/* ─── Policy-decision field accessors ───

   These expose individual fields of a committed policy-decision record
   to the Zig test harness (and any supervisor-side inspection).  The C
   side owns tk_audit_ctx_t / AuditEvent layout; nothing on this side
   mirrors either struct.  Accessors recompute the record array offset
   from their scratch pointer, so they work cross-process.

   Matching Zig wrappers live in c_abi/audit.zig. */

ulong
tk_audit_record_source_offset( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->header.source_offset;
}

uint
tk_audit_record_outcome( void * scratch, ulong idx ) {
    return (uint)tk_audit_record_at( scratch, idx )->policy_decision.outcome;
}

void
tk_audit_record_decided_by( void * scratch, ulong idx, uint8_t * dst ) {
    memcpy( dst, tk_audit_record_at( scratch, idx )->header.tile_id, 6 );
}

ulong
tk_audit_record_source_event_hash( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->policy_decision.source_event_hash;
}

/* ─── Model-call / denial record accessors ───

   Same contract as the policy-decision accessors above: copy out of a
   committed record, recompute the array offset from the caller's scratch
   base, never return a child-process pointer.  Reading a variant that the
   record does not hold is a harness bug, so each accessor aborts on a
   record-type mismatch rather than reinterpreting union bytes. */

uint
tk_audit_record_type( void * scratch, ulong idx ) {
    return (uint)tk_audit_record_at( scratch, idx )->record_type;
}

ulong
tk_audit_record_capability_envelope( void * scratch, ulong idx ) {
    return tk_audit_record_at( scratch, idx )->header.capability_envelope_id;
}

static WireModelCallPayload const *
tk_audit_model_call_at( void * scratch, ulong idx ) {
    AuditEvent const * e = tk_audit_record_at( scratch, idx );
    if( FD_UNLIKELY( e->record_type!=RECORD_MODEL_CALL ) )
        FD_LOG_ERR(( "tkaudt: record %lu is type %u, not model_call", idx, (uint)e->record_type ));
    return &e->model_call;
}

static WireDenialPayload const *
tk_audit_denial_at( void * scratch, ulong idx ) {
    AuditEvent const * e = tk_audit_record_at( scratch, idx );
    if( FD_UNLIKELY( e->record_type!=RECORD_DENIAL ) )
        FD_LOG_ERR(( "tkaudt: record %lu is type %u, not denial", idx, (uint)e->record_type ));
    return &e->denial;
}

void
tk_audit_record_model_id( void * scratch, ulong idx, uint8_t * dst ) {
    memcpy( dst, tk_audit_model_call_at( scratch, idx )->model_id, TKMODL_MODEL_ID_LEN );
}

ulong
tk_audit_record_model_prompt_hash( void * scratch, ulong idx ) {
    return tk_audit_model_call_at( scratch, idx )->prompt_hash;
}

ulong
tk_audit_record_model_response_hash( void * scratch, ulong idx ) {
    return tk_audit_model_call_at( scratch, idx )->response_hash;
}

uint
tk_audit_record_model_token_estimate( void * scratch, ulong idx ) {
    return (uint)tk_audit_model_call_at( scratch, idx )->token_estimate;
}

ulong
tk_audit_record_model_policy_decision_id( void * scratch, ulong idx ) {
    return tk_audit_model_call_at( scratch, idx )->policy_decision_id;
}

ulong
tk_audit_record_model_replay_substitution_id( void * scratch, ulong idx ) {
    return tk_audit_model_call_at( scratch, idx )->replay_substitution_id;
}

uint
tk_audit_record_denial_reason_code( void * scratch, ulong idx ) {
    return (uint)tk_audit_denial_at( scratch, idx )->reason_code;
}

void
tk_audit_record_denial_failed_scope_dim( void * scratch, ulong idx, uint8_t * dst ) {
    memcpy( dst, tk_audit_denial_at( scratch, idx )->failed_scope_dim, TKMODL_SCOPE_DIM_LEN );
}

/* Copy a committed record out whole, for cross-implementation hash checks.
   `dst_sz` must equal sizeof(AuditEvent) — a mismatch means the caller's
   translate-c layout drifted from this file's, so abort rather than copy a
   truncated or over-long record. */
void
tk_audit_record_copy( void * scratch, ulong idx, void * dst, ulong dst_sz ) {
    if( FD_UNLIKELY( dst_sz!=sizeof(AuditEvent) ) )
        FD_LOG_ERR(( "tkaudt: record copy size %lu != AuditEvent size %lu", dst_sz, (ulong)sizeof(AuditEvent) ));
    memcpy( dst, tk_audit_record_at( scratch, idx ), sizeof(AuditEvent) );
}
