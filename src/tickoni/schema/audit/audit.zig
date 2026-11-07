/// Canonical audit schema shared across replay, tiles, and codec boundaries.
///
/// Audit records are cross-tile contracts and part of replay compatibility.
/// Keep the typed schema here; codecs in src/tickoni/codec/ provide concrete
/// binary, protobuf, JSONL, and hash encodings over this schema.
const std = @import("std");
pub const c_schema = @import("audit_mod");

pub const audit_schema_version: u16 = c_schema.AUDIT_SCHEMA_VERSION;

// ─── Enums (Zig-only — no C interop needed) ───

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

// ─── Layout assertion helper ───

/// Check that two struct types have matching layout.
/// Uses `@offsetOf` to verify field offsets at compile time (Zig 0.18+).
fn layoutsMatch(comptime C: type, comptime Z: type, comptime field: []const u8) bool {
    if (@sizeOf(C) != @sizeOf(Z)) return false;
    const c_off = @offsetOf(C, field);
    const z_off = @offsetOf(Z, field);
    if (c_off != z_off) return false;
    return true;
}

// ─── Structs from C schema (single authoritative source via translate-c) ───

/// Re-export of AuditHeader from audit_schema.h.
/// Layout alignment is enforced by the static_assert below.
pub const Header = c_schema.AuditHeader;

comptime {
    std.debug.assert(layoutsMatch(c_schema.AuditHeader, Header, "schema_version"));
}

// Re-export PolicyDecisionPayload from C schema.
pub const PolicyDecisionPayload = c_schema.PolicyDecisionPayload;

comptime {
    std.debug.assert(layoutsMatch(c_schema.PolicyDecisionPayload, PolicyDecisionPayload, "outcome"));
}

// ─── Zig-only payload structs (no C counterpart) ───

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

// ─── Zig AuditEvent (union-based, no C counterpart) ───

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
