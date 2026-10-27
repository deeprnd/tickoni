const schema = @import("audit_schema");

pub const status_ok: c_int = 0;
pub const status_no_space: c_int = 1;
pub const status_invalid_protobuf: c_int = 2;
pub const status_invalid_json: c_int = 3;
pub const status_invalid_field: c_int = 4;

pub const WireHeader = extern struct {
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
    manifest_id: [64]u8,
};

pub const WireSourceEventPayload = extern struct {
    source_system: [16]u8,
    event_type: [32]u8,
    raw_hash: u64,
};

pub const WireNormalizationPayload = extern struct {
    source_event_hash: u64,
    normalized_hash: u64,
    canonical_event_type: [32]u8,
};

pub const WirePolicyDecisionPayload = extern struct {
    outcome: u8,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const WireModelCallPayload = extern struct {
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

pub const WireFinancialAdapterCallPayload = extern struct {
    adapter_id: [16]u8,
    request_hash: u64,
    response_hash: u64,
    replay_substitution_id: u32,
};

pub const WireProposalPayload = extern struct {
    proposal_type: [32]u8,
    proposal_hash: u64,
    approval_state: u8,
};

pub const WireDestinationCheckPayload = extern struct {
    destination_type: [16]u8,
    allowlist_version: u32,
    outcome: u8,
};

pub const WireLimitCheckPayload = extern struct {
    limit_type: u8,
    value: i64,
    limit: i64,
    outcome: u8,
};

pub const WireApprovalRequiredPayload = extern struct {
    action_class: [32]u8,
    approval_path: [32]u8,
    proposal_hash: u64,
};

pub const WireDenialPayload = extern struct {
    action_class: [32]u8,
    reason_code: u32,
    failed_scope_dim: [32]u8,
    catalog_schema_version: u32,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

pub const WireTelemetryCheckpointPayload = extern struct {
    metric_set_hash: u64,
    source_offset_watermark: u64,
};

pub const WireReplayResultPayload = extern struct {
    capsule_id: u64,
    divergences: u64,
    first_divergent_seq: u64,
};

pub const WireDeduplicationPayload = extern struct {
    idempotency_key: u64,
    is_duplicate: u8,
};

pub const WireCaseCreationPayload = extern struct {
    basket_id: u64,
    instrument_count: u8,
    rejected_count: u8,
    total_allocated_cents: i64,
};

pub const WirePayload = extern union {
    source_event: WireSourceEventPayload,
    normalization: WireNormalizationPayload,
    policy_decision: WirePolicyDecisionPayload,
    model_call: WireModelCallPayload,
    financial_adapter_call: WireFinancialAdapterCallPayload,
    proposal: WireProposalPayload,
    destination_check: WireDestinationCheckPayload,
    limit_check: WireLimitCheckPayload,
    approval_required: WireApprovalRequiredPayload,
    denial: WireDenialPayload,
    telemetry_checkpoint: WireTelemetryCheckpointPayload,
    replay_result: WireReplayResultPayload,
    deduplication: WireDeduplicationPayload,
    case_creation: WireCaseCreationPayload,
};

pub const WireEvent = extern struct {
    header: WireHeader,
    record_type: u8,
    payload: WirePayload,
};

pub fn toWireEvent(event: schema.AuditEvent) WireEvent {
    return .{
        .header = .{
            .schema_version = event.header.schema_version,
            .run_id = event.header.run_id,
            .seq = event.header.seq,
            .source_offset = event.header.source_offset,
            .tile_id = event.header.tile_id,
            .logical_actor_id = event.header.logical_actor_id,
            .policy_version = event.header.policy_version,
            .capability_envelope_id_le = event.header.capability_envelope_id,
            .timestamp_ns = event.header.timestamp_ns,
            .prev_hash = event.header.prev_hash,
            .record_hash = event.header.record_hash,
            .version = event.header.version,
            .platform_tier = event.header.platform_tier,
            .isolation_tier = event.header.isolation_tier,
            .release_digest = event.header.release_digest,
            .manifest_id = event.header.manifest_id,
        },
        .record_type = @backingInt(std.meta.activeTag(event.payload)),
        .payload = toWirePayload(event.payload),
    };
}

pub fn fromWireEvent(
    codec: anytype,
    event: WireEvent,
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
            .capability_envelope_id = event.header.capability_envelope_id_le,
            .timestamp_ns = event.header.timestamp_ns,
            .prev_hash = event.header.prev_hash,
            .record_hash = event.header.record_hash,
            .version = event.header.version,
            .platform_tier = event.header.platform_tier,
            .isolation_tier = event.header.isolation_tier,
            .release_digest = event.header.release_digest,
            .manifest_id = event.header.manifest_id,
        },
        .payload = payload,
    };
}

fn toWirePayload(payload: schema.AuditEvent.Payload) WirePayload {
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

fn fromWirePayload(record_type: schema.RecordType, payload: WirePayload) !schema.AuditEvent.Payload {
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
        const schema_type_info = @typeInfo(schema.AuditEvent.Payload).@"struct";
        const wire_type_info = @typeInfo(WirePayload).@"struct";
        if (schema_type_info.field_names.len != wire_type_info.field_names.len) {
            @compileError("schema.AuditEvent.Payload and wire.WirePayload have a different number of record-type variants");
        }
        // Check each variant name matches.
        var i: usize = 0;
        while (i < schema_type_info.field_names.len) : (i += 1) {
            if (!std.mem.eql(u8, schema_type_info.field_names[i], wire_type_info.field_names[i])) {
                @compileError("schema.AuditEvent.Payload and wire.WirePayload variant order/names diverge: " ++ schema_type_info.field_names[i] ++ " vs " ++ wire_type_info.field_names[i]);
            }
        }
        // Check each variant's inner struct fields match.
        i = 0;
        while (i < schema_type_info.field_names.len) : (i += 1) {
            const schema_variant_type_info = @typeInfo(schema_type_info.field_types[i]).@"struct";
            const wire_variant_type_info = @typeInfo(wire_type_info.field_types[i]).@"struct";
            if (schema_variant_type_info.field_names.len != wire_variant_type_info.field_names.len) {
                @compileError("schema and wire payload field count diverges for variant " ++ schema_type_info.field_names[i]);
            }
            var j: usize = 0;
            while (j < schema_variant_type_info.field_names.len) : (j += 1) {
                if (!std.mem.eql(u8, schema_variant_type_info.field_names[j], wire_variant_type_info.field_names[j])) {
                    @compileError("schema and wire payload field name diverges for variant " ++ schema_type_info.field_names[i] ++ ": " ++ schema_variant_type_info.field_names[j] ++ " vs " ++ wire_variant_type_info.field_names[j]);
                }
            }
        }
    }
}
