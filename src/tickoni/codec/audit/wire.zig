const schema = @import("audit_schema");

pub const status_ok: c_int = 0;
pub const status_no_space: c_int = 1;
pub const status_invalid_protobuf: c_int = 2;
pub const status_invalid_json: c_int = 3;
pub const status_invalid_field: c_int = 4;

pub const Header = extern struct {
    schema_version: u16,
    run_id: u64,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    logical_actor_id: u64,
    policy_version: [32]u8,
    capability_envelope_id_le: [16]u8,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
    // Runtime metadata: identifies the exact build/tier/manifest that produced
    // this event. Carried through audit and replay so the entire lineage is
    // verifiable.
    version: [64]u8,
    platform_tier: [64]u8,
    isolation_tier: [64]u8,
    release_digest: [64]u8,
    demo_manifest_id: [64]u8,
};

pub const SourceEventPayload = extern struct {
    source_system: [16]u8,
    event_type: [32]u8,
    raw_hash: u64,
};

pub const NormalizationPayload = extern struct {
    source_event_hash: u64,
    normalized_hash: u64,
    canonical_event_type: [32]u8,
};

pub const PolicyDecisionPayload = extern struct {
    outcome: u8,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const ModelCallPayload = extern struct {
    model_id: [32]u8,
    prompt_hash: u64,
    response_hash: u64,
    token_estimate: u32,
    retry_count: u8,
    actor_role: [16]u8,
    workflow: [16]u8,
    policy_decision_id: u64,
    replay_substitution_id: u64,
};

pub const FinancialAdapterCallPayload = extern struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    replay_substitution_id: u32,
};

pub const ProposalPayload = extern struct {
    proposal_type: [32]u8,
    proposal_hash: u64,
    approval_state: u8,
};

pub const DestinationCheckPayload = extern struct {
    destination_type: [16]u8,
    allowlist_version: u32,
    outcome: u8,
};

pub const LimitCheckPayload = extern struct {
    limit_type: u8,
    value: i64,
    limit: i64,
    outcome: u8,
};

pub const ApprovalRequiredPayload = extern struct {
    action_class: [32]u8,
    approval_path: [32]u8,
    proposal_hash: u64,
};

pub const DenialPayload = extern struct {
    action_class: [32]u8,
    reason_code: u32,
    failed_scope_dim: [32]u8,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const TelemetryCheckpointPayload = extern struct {
    metric_set_hash: u64,
    source_offset_watermark: u64,
};

pub const ReplayResultPayload = extern struct {
    capsule_id: u64,
    divergences: u64,
    first_divergent_seq: u64,
};

pub const DeduplicationPayload = extern struct {
    idempotency_key: u64,
    is_duplicate: u8,
};

pub const CaseCreationPayload = extern struct {
    basket_id: u64,
    instrument_count: u8,
    rejected_count: u8,
    total_allocated_cents: i64,
};

pub const Payload = extern union {
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

pub const Event = extern struct {
    header: Header,
    record_type: u8,
    payload: Payload,
};

pub fn toWireEvent(event: schema.AuditEvent) Event {
    return .{
        .header = .{
            .schema_version = event.header.schema_version,
            .run_id = event.header.run_id,
            .seq = event.header.seq,
            .source_offset = event.header.source_offset,
            .tile_id = event.header.tile_id,
            .logical_actor_id = event.header.logical_actor_id,
            .policy_version = event.header.policy_version,
            .capability_envelope_id_le = @bitCast(event.header.capability_envelope_id),
            .timestamp_ns = event.header.timestamp_ns,
            .prev_hash = event.header.prev_hash,
            .record_hash = event.header.record_hash,
            .version = event.header.version,
            .platform_tier = event.header.platform_tier,
            .isolation_tier = event.header.isolation_tier,
            .release_digest = event.header.release_digest,
            .demo_manifest_id = event.header.demo_manifest_id,
        },
        .record_type = @backingInt(std.meta.activeTag(event.payload)),
        .payload = toWirePayload(event.payload),
    };
}

pub fn fromWireEvent(
    codec: anytype,
    event: Event,
) !schema.AuditEvent {
    try codec.checkSchemaVersion(event.header.schema_version);
    const record_type = try codec.parseRecordType(event.record_type);
    const payload = try fromWirePayload(record_type, event.payload);
    return .{
        .header = .{
            .schema_version = event.header.schema_version,
            .run_id = event.header.run_id,
            .seq = event.header.seq,
            .source_offset = event.header.source_offset,
            .tile_id = event.header.tile_id,
            .logical_actor_id = event.header.logical_actor_id,
            .policy_version = event.header.policy_version,
            .capability_envelope_id = @bitCast(event.header.capability_envelope_id_le),
            .timestamp_ns = event.header.timestamp_ns,
            .prev_hash = event.header.prev_hash,
            .record_hash = event.header.record_hash,
            .version = event.header.version,
            .platform_tier = event.header.platform_tier,
            .isolation_tier = event.header.isolation_tier,
            .release_digest = event.header.release_digest,
            .demo_manifest_id = event.header.demo_manifest_id,
        },
        .payload = payload,
    };
}

fn toWirePayload(payload: schema.AuditEvent.Payload) Payload {
    return switch (payload) {
        .source_event => |p| .{ .source_event = .{
            .source_system = p.source_system,
            .event_type = p.event_type,
            .raw_hash = p.raw_hash,
        } },
        .normalization => |p| .{ .normalization = .{
            .source_event_hash = p.source_event_hash,
            .normalized_hash = p.normalized_hash,
            .canonical_event_type = p.canonical_event_type,
        } },
        .policy_decision => |p| .{ .policy_decision = .{
            .outcome = @backingInt(p.outcome),
            .rule_id = p.rule_id,
            .failed_scope_dim = p.failed_scope_dim,
            .source_event_hash = p.source_event_hash,
            .catalog_schema_version = p.catalog_schema_version,
            .taxonomy_id = p.taxonomy_id,
            .taxonomy_version = p.taxonomy_version,
            .classification_code = p.classification_code,
        } },
        .model_call => |p| .{ .model_call = .{
            .model_id = p.model_id,
            .prompt_hash = p.prompt_hash,
            .response_hash = p.response_hash,
            .token_estimate = p.token_estimate,
            .retry_count = p.retry_count,
            .actor_role = p.actor_role,
            .workflow = p.workflow,
            .policy_decision_id = p.policy_decision_id,
            .replay_substitution_id = p.replay_substitution_id,
        } },
        .financial_adapter_call => |p| .{ .financial_adapter_call = .{
            .adapter_id = p.adapter_id,
            .request_hash = p.request_hash,
            .response_hash = p.response_hash,
            .replay_substitution_id = p.replay_substitution_id,
        } },
        .proposal => |p| .{ .proposal = .{
            .proposal_type = p.proposal_type,
            .proposal_hash = p.proposal_hash,
            .approval_state = p.approval_state,
        } },
        .destination_check => |p| .{ .destination_check = .{
            .destination_type = p.destination_type,
            .allowlist_version = p.allowlist_version,
            .outcome = @backingInt(p.outcome),
        } },
        .limit_check => |p| .{ .limit_check = .{
            .limit_type = @backingInt(p.limit_type),
            .value = p.value,
            .limit = p.limit,
            .outcome = @backingInt(p.outcome),
        } },
        .approval_required => |p| .{ .approval_required = .{
            .action_class = p.action_class,
            .approval_path = p.approval_path,
            .proposal_hash = p.proposal_hash,
        } },
        .denial => |p| .{ .denial = .{
            .action_class = p.action_class,
            .reason_code = p.reason_code,
            .failed_scope_dim = p.failed_scope_dim,
            .catalog_schema_version = p.catalog_schema_version,
            .taxonomy_id = p.taxonomy_id,
            .taxonomy_version = p.taxonomy_version,
            .classification_code = p.classification_code,
        } },
        .telemetry_checkpoint => |p| .{ .telemetry_checkpoint = .{
            .metric_set_hash = p.metric_set_hash,
            .source_offset_watermark = p.source_offset_watermark,
        } },
        .replay_result => |p| .{ .replay_result = .{
            .capsule_id = p.capsule_id,
            .divergences = p.divergences,
            .first_divergent_seq = p.first_divergent_seq,
        } },
        .deduplication => |p| .{ .deduplication = .{
            .idempotency_key = p.idempotency_key,
            .is_duplicate = @intFromBool(p.is_duplicate),
        } },
        .case_creation => |p| .{ .case_creation = .{
            .basket_id = p.basket_id,
            .instrument_count = p.instrument_count,
            .rejected_count = p.rejected_count,
            .total_allocated_cents = p.total_allocated_cents,
        } },
    };
}

fn fromWirePayload(record_type: schema.RecordType, payload: Payload) !schema.AuditEvent.Payload {
    return switch (record_type) {
        .source_event => .{ .source_event = .{
            .source_system = payload.source_event.source_system,
            .event_type = payload.source_event.event_type,
            .raw_hash = payload.source_event.raw_hash,
        } },
        .normalization => .{ .normalization = .{
            .source_event_hash = payload.normalization.source_event_hash,
            .normalized_hash = payload.normalization.normalized_hash,
            .canonical_event_type = payload.normalization.canonical_event_type,
        } },
        .policy_decision => .{ .policy_decision = .{
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.policy_decision.outcome),
            .rule_id = payload.policy_decision.rule_id,
            .failed_scope_dim = payload.policy_decision.failed_scope_dim,
            .source_event_hash = payload.policy_decision.source_event_hash,
            .catalog_schema_version = payload.policy_decision.catalog_schema_version,
            .taxonomy_id = payload.policy_decision.taxonomy_id,
            .taxonomy_version = payload.policy_decision.taxonomy_version,
            .classification_code = payload.policy_decision.classification_code,
        } },
        .model_call => .{ .model_call = .{
            .model_id = payload.model_call.model_id,
            .prompt_hash = payload.model_call.prompt_hash,
            .response_hash = payload.model_call.response_hash,
            .token_estimate = payload.model_call.token_estimate,
            .retry_count = payload.model_call.retry_count,
            .actor_role = payload.model_call.actor_role,
            .workflow = payload.model_call.workflow,
            .policy_decision_id = payload.model_call.policy_decision_id,
            .replay_substitution_id = payload.model_call.replay_substitution_id,
        } },
        .financial_adapter_call => .{ .financial_adapter_call = .{
            .adapter_id = payload.financial_adapter_call.adapter_id,
            .request_hash = payload.financial_adapter_call.request_hash,
            .response_hash = payload.financial_adapter_call.response_hash,
            .replay_substitution_id = payload.financial_adapter_call.replay_substitution_id,
        } },
        .proposal => .{ .proposal = .{
            .proposal_type = payload.proposal.proposal_type,
            .proposal_hash = payload.proposal.proposal_hash,
            .approval_state = payload.proposal.approval_state,
        } },
        .destination_check => .{ .destination_check = .{
            .destination_type = payload.destination_check.destination_type,
            .allowlist_version = payload.destination_check.allowlist_version,
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.destination_check.outcome),
        } },
        .limit_check => .{ .limit_check = .{
            .limit_type = try parseEnumByValue(schema.LimitType, payload.limit_check.limit_type),
            .value = payload.limit_check.value,
            .limit = payload.limit_check.limit,
            .outcome = try parseEnumByValue(schema.PolicyOutcome, payload.limit_check.outcome),
        } },
        .approval_required => .{ .approval_required = .{
            .action_class = payload.approval_required.action_class,
            .approval_path = payload.approval_required.approval_path,
            .proposal_hash = payload.approval_required.proposal_hash,
        } },
        .denial => .{ .denial = .{
            .action_class = payload.denial.action_class,
            .reason_code = payload.denial.reason_code,
            .failed_scope_dim = payload.denial.failed_scope_dim,
            .catalog_schema_version = payload.denial.catalog_schema_version,
            .taxonomy_id = payload.denial.taxonomy_id,
            .taxonomy_version = payload.denial.taxonomy_version,
            .classification_code = payload.denial.classification_code,
        } },
        .telemetry_checkpoint => .{ .telemetry_checkpoint = .{
            .metric_set_hash = payload.telemetry_checkpoint.metric_set_hash,
            .source_offset_watermark = payload.telemetry_checkpoint.source_offset_watermark,
        } },
        .replay_result => .{ .replay_result = .{
            .capsule_id = payload.replay_result.capsule_id,
            .divergences = payload.replay_result.divergences,
            .first_divergent_seq = payload.replay_result.first_divergent_seq,
        } },
        .deduplication => .{ .deduplication = .{
            .idempotency_key = payload.deduplication.idempotency_key,
            .is_duplicate = switch (payload.deduplication.is_duplicate) {
                0 => false,
                1 => true,
                else => return error.UnknownEnumValue,
            },
        } },
        .case_creation => .{ .case_creation = .{
            .basket_id = payload.case_creation.basket_id,
            .instrument_count = payload.case_creation.instrument_count,
            .rejected_count = payload.case_creation.rejected_count,
            .total_allocated_cents = payload.case_creation.total_allocated_cents,
        } },
    };
}

fn parseEnumByValue(comptime T: type, value: anytype) error{ UnknownRecordType, UnknownEnumValue }!T {
    const e = @typeInfo(T).@"enum";
    inline for (e.field_names, e.field_values) |name, field_value| {
        if (field_value == value) return @field(T, name);
    }
    if (T == schema.RecordType) return error.UnknownRecordType;
    return error.UnknownEnumValue;
}

const std = @import("std");

// Mechanical sync check between the canonical Zig schema (audit.zig) and the
// wire codec's extern-struct mirror of it, so adding/removing/renaming a
// payload field in one without the other fails the build instead of silently
// drifting — see finding 32 in
// doc/strategy/roadmap/backlog/audits/tech_debt.md. Does not cover the
// .proto file, hash.zig's SipHash coverage, or jsonl.zig's field list, since
// those aren't reachable via Zig reflection; this is the prerequisite piece
// finding 32 itself calls out ("mechanically-check the four representations
// against one source of truth").
test "schema and wire Payload variants stay field-name and order synchronized" {
    comptime {
        const schema_fields = std.meta.fields(schema.AuditEvent.Payload);
        const wire_fields = std.meta.fields(Payload);
        if (schema_fields.len != wire_fields.len) {
            @compileError("schema.AuditEvent.Payload and wire.Payload have a different number of record-type variants");
        }
        for (schema_fields, wire_fields) |sf, wf| {
            if (!std.mem.eql(u8, sf.name, wf.name)) {
                @compileError("schema.AuditEvent.Payload and wire.Payload variant order/names diverge: " ++ sf.name ++ " vs " ++ wf.name);
            }
            const schema_variant_fields = std.meta.fields(sf.type);
            const wire_variant_fields = std.meta.fields(wf.type);
            if (schema_variant_fields.len != wire_variant_fields.len) {
                @compileError("schema and wire payload field count diverges for variant " ++ sf.name);
            }
            for (schema_variant_fields, wire_variant_fields) |svf, wvf| {
                if (!std.mem.eql(u8, svf.name, wvf.name)) {
                    @compileError("schema and wire payload field name diverges for variant " ++ sf.name ++ ": " ++ svf.name ++ " vs " ++ wvf.name);
                }
            }
        }
    }
}
