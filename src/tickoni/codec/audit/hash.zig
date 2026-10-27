const std = @import("std");
const c_abi = @import("c_abi");
const schema = @import("audit_schema");
const wire = @import("wire.zig");

/// k0/k1 are fixed constants baked into the audit schema. Changing them
/// invalidates all existing audit logs.
const hash_k0: u64 = 0x0000544455414B54; // "TKAUDT\0\0" LE
const hash_k1: u64 = 2; // schema version

pub fn computeRecordHash(event: schema.AuditEvent) u64 {
    return computeWireRecordHash(wire.toWireEvent(event));
}

pub fn auditEventsEql(a: schema.AuditEvent, b: schema.AuditEvent) bool {
    var ah = a.header;
    var bh = b.header;
    ah.timestamp_ns = 0;
    bh.timestamp_ns = 0;
    return std.meta.eql(ah, bh) and std.meta.eql(a.payload, b.payload);
}

pub fn computeWireRecordHash(event: wire.WireEvent) u64 {
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
    c_abi.ballet.siphashAppend(&sip, &h.capability_envelope_id_le);
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
