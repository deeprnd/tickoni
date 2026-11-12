const std = @import("std");
const c_abi = @import("c_abi");
const schema = @import("audit_schema");
const wire = @import("wire.zig");
const audit_consts = @import("audit_consts");

/// Hash constants — from audit_consts which loads from C header via translate-c.
const hash_k0: u64 = audit_consts.AUDIT_HASH_K0;
const hash_k1: u64 = audit_consts.AUDIT_HASH_K1;

pub fn computeRecordHash(event: schema.AuditEvent) u64 {
    return computeWireRecordHash(wire.toWireEvent(event));
}

pub fn auditEventsEql(a: schema.AuditEvent, b: schema.AuditEvent) bool {
    var ah = a.header;
    var bh = b.header;
    ah.timestamp_ns = 0;
    bh.timestamp_ns = 0;
    return eqlHeader(ah, bh) and eqlPayload(a.payload, b.payload);
}

fn eqlHeader(a: schema.Header, b: schema.Header) bool {
    return a.schema_version == b.schema_version and
        a.run_id == b.run_id and
        a.seq == b.seq and
        a.source_offset == b.source_offset and
        std.mem.eql(u8, &a.tile_id, &b.tile_id) and
        a.logical_actor_id == b.logical_actor_id and
        std.mem.eql(u8, &a.policy_version, &b.policy_version) and
        a.capability_envelope_id == b.capability_envelope_id and
        a.timestamp_ns == b.timestamp_ns and
        a.prev_hash == b.prev_hash and
        a.record_hash == b.record_hash and
        std.mem.eql(u8, &a.version, &b.version) and
        std.mem.eql(u8, &a.platform_tier, &b.platform_tier) and
        std.mem.eql(u8, &a.isolation_tier, &b.isolation_tier) and
        std.mem.eql(u8, &a.release_digest, &b.release_digest) and
        std.mem.eql(u8, &a.manifest_id, &b.manifest_id);
}

fn eqlPayload(a: schema.AuditEvent.Payload, b: schema.AuditEvent.Payload) bool {
    return switch (a) {
        .source_event => |av| switch (b) {
            .source_event => |bv| av.raw_hash == bv.raw_hash and
                std.mem.eql(u8, &av.source_system, &bv.source_system) and
                std.mem.eql(u8, &av.event_type, &bv.event_type),
            else => false,
        },
        .normalization => |av| switch (b) {
            .normalization => |bv| av.source_event_hash == bv.source_event_hash and
                av.normalized_hash == bv.normalized_hash and
                std.mem.eql(u8, &av.canonical_event_type, &bv.canonical_event_type),
            else => false,
        },
        .policy_decision => |av| switch (b) {
            .policy_decision => |bv| av.outcome == bv.outcome and
                av.rule_id == bv.rule_id and
                av.source_event_hash == bv.source_event_hash and
                av.catalog_schema_version == bv.catalog_schema_version and
                std.mem.eql(u8, &av.failed_scope_dim, &bv.failed_scope_dim) and
                std.mem.eql(u8, &av.taxonomy_id, &bv.taxonomy_id) and
                av.taxonomy_version == bv.taxonomy_version and
                std.mem.eql(u8, &av.classification_code, &bv.classification_code),
            else => false,
        },
        .model_call => |av| switch (b) {
            .model_call => |bv| std.mem.eql(u8, &av.model_id, &bv.model_id) and
                av.prompt_hash == bv.prompt_hash and
                av.response_hash == bv.response_hash and
                av.token_estimate == bv.token_estimate and
                av.retry_count == bv.retry_count and
                std.mem.eql(u8, &av.actor_role, &bv.actor_role) and
                std.mem.eql(u8, &av.workflow, &bv.workflow) and
                av.policy_decision_id == bv.policy_decision_id and
                av.replay_substitution_id == bv.replay_substitution_id,
            else => false,
        },
        .financial_adapter_call => |av| switch (b) {
            .financial_adapter_call => |bv| std.mem.eql(u8, &av.adapter_id, &bv.adapter_id) and
                av.request_hash == bv.request_hash and
                av.response_hash == bv.response_hash and
                av.replay_substitution_id == bv.replay_substitution_id,
            else => false,
        },
        .proposal => |av| switch (b) {
            .proposal => |bv| std.mem.eql(u8, &av.proposal_type, &bv.proposal_type) and
                av.proposal_hash == bv.proposal_hash and
                av.approval_state == bv.approval_state,
            else => false,
        },
        .destination_check => |av| switch (b) {
            .destination_check => |bv| std.mem.eql(u8, &av.destination_type, &bv.destination_type) and
                av.allowlist_version == bv.allowlist_version and
                av.outcome == bv.outcome,
            else => false,
        },
        .limit_check => |av| switch (b) {
            .limit_check => |bv| av.limit_type == bv.limit_type and
                av.value == bv.value and
                av.limit == bv.limit and
                av.outcome == bv.outcome,
            else => false,
        },
        .approval_required => |av| switch (b) {
            .approval_required => |bv| std.mem.eql(u8, &av.action_class, &bv.action_class) and
                std.mem.eql(u8, &av.approval_path, &bv.approval_path) and
                av.proposal_hash == bv.proposal_hash,
            else => false,
        },
        .denial => |av| switch (b) {
            .denial => |bv| std.mem.eql(u8, &av.action_class, &bv.action_class) and
                av.reason_code == bv.reason_code and
                std.mem.eql(u8, &av.failed_scope_dim, &bv.failed_scope_dim) and
                av.catalog_schema_version == bv.catalog_schema_version and
                std.mem.eql(u8, &av.taxonomy_id, &bv.taxonomy_id) and
                av.taxonomy_version == bv.taxonomy_version and
                std.mem.eql(u8, &av.classification_code, &bv.classification_code),
            else => false,
        },
        .telemetry_checkpoint => |av| switch (b) {
            .telemetry_checkpoint => |bv| av.metric_set_hash == bv.metric_set_hash and
                av.source_offset_watermark == bv.source_offset_watermark,
            else => false,
        },
        .replay_result => |av| switch (b) {
            .replay_result => |bv| av.capsule_id == bv.capsule_id and
                av.divergences == bv.divergences and
                av.first_divergent_seq == bv.first_divergent_seq,
            else => false,
        },
        .deduplication => |av| switch (b) {
            .deduplication => |bv| av.idempotency_key == bv.idempotency_key and
                av.is_duplicate == bv.is_duplicate,
            else => false,
        },
        .case_creation => |av| switch (b) {
            .case_creation => |bv| av.basket_id == bv.basket_id and
                av.instrument_count == bv.instrument_count and
                av.rejected_count == bv.rejected_count and
                av.total_allocated_cents == bv.total_allocated_cents,
            else => false,
        },
    };
}

pub fn computeWireRecordHash(event: wire.Event) u64 {
    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, hash_k0, hash_k1);
    const h = &event.header;

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.schema_version));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.run_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.seq));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.source_offset));
    c_abi.ballet.siphashAppend(&sip, &h.tile_id);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.logical_actor_id));
    c_abi.ballet.siphashAppend(&sip, &h.policy_version);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.capability_envelope_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&h.prev_hash));
    c_abi.ballet.siphashAppend(&sip, &h.version);
    c_abi.ballet.siphashAppend(&sip, &h.platform_tier);
    c_abi.ballet.siphashAppend(&sip, &h.isolation_tier);
    c_abi.ballet.siphashAppend(&sip, &h.release_digest);
    c_abi.ballet.siphashAppend(&sip, &h.manifest_id);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&event.record_type));

    switch (event.record_type) {
        0 => {
            const p = &event.payload.source_event;
            c_abi.ballet.siphashAppend(&sip, &p.source_system);
            c_abi.ballet.siphashAppend(&sip, &p.event_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.raw_hash));
        },
        1 => {
            const p = &event.payload.normalization;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_event_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.normalized_hash));
            c_abi.ballet.siphashAppend(&sip, &p.canonical_event_type);
        },
        2 => {
            const p = &event.payload.policy_decision;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.rule_id));
            c_abi.ballet.siphashAppend(&sip, &p.failed_scope_dim);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_event_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.catalog_schema_version));
            c_abi.ballet.siphashAppend(&sip, &p.taxonomy_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.taxonomy_version));
            c_abi.ballet.siphashAppend(&sip, &p.classification_code);
        },
        3 => {
            const p = &event.payload.model_call;
            c_abi.ballet.siphashAppend(&sip, &p.model_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.prompt_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.response_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.token_estimate));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.retry_count));
            c_abi.ballet.siphashAppend(&sip, &p.actor_role);
            c_abi.ballet.siphashAppend(&sip, &p.workflow);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.policy_decision_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.replay_substitution_id));
        },
        4 => {
            const p = &event.payload.financial_adapter_call;
            c_abi.ballet.siphashAppend(&sip, &p.adapter_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.request_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.response_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.replay_substitution_id));
        },
        5 => {
            const p = &event.payload.proposal;
            c_abi.ballet.siphashAppend(&sip, &p.proposal_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.proposal_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.approval_state));
        },
        6 => {
            const p = &event.payload.destination_check;
            c_abi.ballet.siphashAppend(&sip, &p.destination_type);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.allowlist_version));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
        },
        7 => {
            const p = &event.payload.limit_check;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.limit_type));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.value));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.limit));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.outcome));
        },
        8 => {
            const p = &event.payload.approval_required;
            c_abi.ballet.siphashAppend(&sip, &p.action_class);
            c_abi.ballet.siphashAppend(&sip, &p.approval_path);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.proposal_hash));
        },
        9 => {
            const p = &event.payload.denial;
            c_abi.ballet.siphashAppend(&sip, &p.action_class);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.reason_code));
            c_abi.ballet.siphashAppend(&sip, &p.failed_scope_dim);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.catalog_schema_version));
            c_abi.ballet.siphashAppend(&sip, &p.taxonomy_id);
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.taxonomy_version));
            c_abi.ballet.siphashAppend(&sip, &p.classification_code);
        },
        10 => {
            const p = &event.payload.telemetry_checkpoint;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.metric_set_hash));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.source_offset_watermark));
        },
        11 => {
            const p = &event.payload.replay_result;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.capsule_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.divergences));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.first_divergent_seq));
        },
        12 => {
            const p = &event.payload.deduplication;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.idempotency_key));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.is_duplicate));
        },
        13 => {
            const p = &event.payload.case_creation;
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.basket_id));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.instrument_count));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.rejected_count));
            c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&p.total_allocated_cents));
        },
        else => {},
    }

    return c_abi.ballet.siphashFini(&sip);
}
