/// Canonical audit schema shared across replay, tiles, and codec boundaries.
///
/// Audit records are cross-tile contracts and part of replay compatibility.
/// Keep the typed schema here; codecs in src/tickoni/codec/ provide concrete
/// binary, protobuf, JSONL, and hash encodings over this schema.
pub const audit_schema_version: u16 = 2;

pub const PolicyOutcome = enum(u8) {
    allow,
    deny,
    require_approval,
    malformed_drop,
    duplicate_drop,
    escalate,
    require_more_evidence,
};

pub const LimitType = enum(u8) {
    amount,
    frequency,
    holding_period,
    per_day,
    per_month,
};

pub const RecordType = enum(u8) {
    source_event = 0,
    normalization = 1,
    policy_decision = 2,
    model_call = 3,
    financial_adapter_call = 4,
    proposal = 5,
    destination_check = 6,
    limit_check = 7,
    approval_required = 8,
    denial = 9,
    telemetry_checkpoint = 10,
    replay_result = 11,
    deduplication = 12,
    case_creation = 13,
};

pub const SourceEventPayload = struct {
    source_system: [16]u8,
    event_type: [32]u8,
    raw_hash: u64,
};

pub const NormalizationPayload = struct {
    source_event_hash: u64,
    normalized_hash: u64,
    canonical_event_type: [32]u8,
};

pub const PolicyDecisionPayload = extern struct {
    outcome: PolicyOutcome,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
    // Classification evidence: zero/empty when this decision is not a
    // classification-scope decision (e.g. affordability or restricted-
    // instrument denials).
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const ModelCallPayload = struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
    // Governed tkmodl context carried through the binary/protobuf audit codec.
    actor_role: [16]u8,
    workflow: [16]u8,
    policy_decision_id: u64,
    replay_substitution_id: u64,
};

pub const FinancialAdapterCallPayload = struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    // Replay-substitution reference for this adapter call's captured
    // response. Kept u32 (unlike ModelCallPayload's u64 field of the same
    // name) so this rename does not shift the record's SipHash byte layout
    // and invalidate existing hash-chained audit fixtures.
    replay_substitution_id: u32,
};

pub const ProposalPayload = struct {
    proposal_type: [32]u8,
    proposal_hash: u64,
    approval_state: u8,
};

pub const DestinationCheckPayload = struct {
    destination_type: [16]u8,
    allowlist_version: u32,
    outcome: PolicyOutcome,
};

pub const LimitCheckPayload = struct {
    limit_type: LimitType,
    value: i64,
    limit: i64,
    outcome: PolicyOutcome,
};

pub const ApprovalRequiredPayload = struct {
    action_class: [32]u8,
    approval_path: [32]u8,
    proposal_hash: u64,
};

pub const DenialPayload = struct {
    action_class: [32]u8,
    reason_code: u32,
    failed_scope_dim: [32]u8,
    // Classification evidence: zero/empty when this denial is not a
    // classification-scope decision.
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const TelemetryCheckpointPayload = struct {
    metric_set_hash: u64,
    source_offset_watermark: u64,
};

pub const ReplayResultPayload = struct {
    capsule_id: u64,
    divergences: u64,
    first_divergent_seq: u64,
};

pub const DeduplicationPayload = struct {
    idempotency_key: u64,
    is_duplicate: bool,
};

pub const CaseCreationPayload = struct {
    basket_id: u64,
    instrument_count: u8,
    rejected_count: u8,
    total_allocated_cents: i64,
};

pub const Header = extern struct {
    schema_version: u16,
    run_id: u64,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    logical_actor_id: u64,
    policy_version: [32]u8,
    capability_envelope_id: [16]u8,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
    // Runtime metadata: identifies the exact build/tier/manifest that produced
    // this event. Carried through audit and replay so the entire lineage is
    // verifiable.
    version: [64]u8, // semver string, null-terminated
    platform_tier: [64]u8, // e.g. "linux_full", "macos_retail"
    isolation_tier: [64]u8, // e.g. "retail", "full"
    release_digest: [64]u8, // git SHA or build digest
    manifest_id: [64]u8, // which manifest was loaded (empty if none)
};

pub const AuditEvent = struct {
    header: Header,
    payload: Payload,

    pub const Payload = union(RecordType) {
        source_event: SourceEventPayload,
        normalization: NormalizationPayload,
        policy_decision: PolicyDecisionPayload,
        model_call: ModelCallPayload,
        financial_adapter_call: FinancialAdapterCallPayload,
        proposal: ProposalPayload,
        destination_check: DestinationCheckPayload,
        limit_check: LimitCheckPayload,
        approval_required: ApprovalRequiredPayload,
        denial: DenialPayload,
        telemetry_checkpoint: TelemetryCheckpointPayload,
        replay_result: ReplayResultPayload,
        deduplication: DeduplicationPayload,
        case_creation: CaseCreationPayload,
    };
};
