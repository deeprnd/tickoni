const std = @import("std");
const c_abi = @import("c_abi");
const wire = @import("wire.zig");

// ---------------------------------------------------------------------------
// Protobuf field numbers (audit header). Oneof payload field = payload_base
// + record_type (0..13).
// ---------------------------------------------------------------------------
const field_schema_version: u32 = 1;
const field_run_id: u32 = 2;
const field_seq: u32 = 3;
const field_source_offset: u32 = 4;
const field_tile_id: u32 = 5;
const field_logical_actor_id: u32 = 6;
const field_policy_version: u32 = 7;
const field_capability_envelope_id: u32 = 8;
const field_timestamp_ns: u32 = 9;
const field_prev_hash: u32 = 10;
const field_record_hash: u32 = 11;
const field_payload_base: u32 = 12;
const field_version: u32 = 90;
const field_platform_tier: u32 = 91;
const field_isolation_tier: u32 = 92;
const field_release_digest: u32 = 93;
const field_manifest_id: u32 = 94;

pub fn formatProtobuf(
    out: [*]u8,
    out_sz: usize,
    event: *const wire.WireEvent,
    written: *usize,
) c_int {
    var scratch: [512]u8 align(32) = undefined;
    const capped_out_sz = @min(out_sz, scratch.len);
    var enc: c_abi.ballet.PbEncoder = .{};
    if (!c_abi.ballet.pbEncoderInit(&enc, scratch[0..capped_out_sz])) return wire.status_no_space;

    const h = &event.header;
    const tile_len = trimmedLen(&h.tile_id);
    const policy_len = trimmedLen(&h.policy_version);

    if (!c_abi.ballet.pbPushUint32(&enc, field_schema_version, h.schema_version)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_run_id, h.run_id)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_seq, h.seq)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_source_offset, h.source_offset)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_tile_id, h.tile_id[0..tile_len])) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_logical_actor_id, h.logical_actor_id)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_policy_version, h.policy_version[0..policy_len])) return wire.status_no_space;
    if (!c_abi.ballet.pbPushBytes(&enc, field_capability_envelope_id, &h.capability_envelope_id_le)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_timestamp_ns, h.timestamp_ns)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_prev_hash, h.prev_hash)) return wire.status_no_space;
    if (!c_abi.ballet.pbPushUint64(&enc, field_record_hash, h.record_hash)) return wire.status_no_space;

    // Runtime metadata fields (90-94)
    const version_len = trimmedLen(&h.version);
    const platform_tier_len = trimmedLen(&h.platform_tier);
    const isolation_tier_len = trimmedLen(&h.isolation_tier);
    const release_digest_len = trimmedLen(&h.release_digest);
    const manifest_id_len = trimmedLen(&h.manifest_id);
    if (version_len != 0) {
        if (!c_abi.ballet.pbPushBytes(&enc, field_version, h.version[0..version_len])) return wire.status_no_space;
    }
    if (platform_tier_len != 0) {
        if (!c_abi.ballet.pbPushBytes(&enc, field_platform_tier, h.platform_tier[0..platform_tier_len])) return wire.status_no_space;
    }
    if (isolation_tier_len != 0) {
        if (!c_abi.ballet.pbPushBytes(&enc, field_isolation_tier, h.isolation_tier[0..isolation_tier_len])) return wire.status_no_space;
    }
    if (release_digest_len != 0) {
        if (!c_abi.ballet.pbPushBytes(&enc, field_release_digest, h.release_digest[0..release_digest_len])) return wire.status_no_space;
    }
    if (manifest_id_len != 0) {
        if (!c_abi.ballet.pbPushBytes(&enc, field_manifest_id, h.manifest_id[0..manifest_id_len])) return wire.status_no_space;
    }

    if (!c_abi.ballet.pbSubmsgOpen(&enc, field_payload_base + event.record_type)) return wire.status_no_space;
    switch (event.record_type) {
        0 => {
            const p = &event.payload.source_event;
            const source_len = trimmedLen(&p.source_system);
            const event_type_len = trimmedLen(&p.event_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.source_system[0..source_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 2, p.event_type[0..event_type_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.raw_hash)) return wire.status_no_space;
        },
        1 => {
            const p = &event.payload.normalization;
            const event_type_len = trimmedLen(&p.canonical_event_type);
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.source_event_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.normalized_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.canonical_event_type[0..event_type_len])) return wire.status_no_space;
        },
        2 => {
            const p = &event.payload.policy_decision;
            const failed_dim_len = trimmedLen(&p.failed_scope_dim);
            const taxonomy_id_len = trimmedLen(&p.taxonomy_id);
            const classification_code_len = trimmedLen(&p.classification_code);
            if (!c_abi.ballet.pbPushUint32(&enc, 1, p.outcome)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.rule_id)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.failed_scope_dim[0..failed_dim_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 4, p.source_event_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 5, p.catalog_schema_version)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 6, p.taxonomy_id[0..taxonomy_id_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 7, p.taxonomy_version)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 8, p.classification_code[0..classification_code_len])) return wire.status_no_space;
        },
        3 => {
            const p = &event.payload.model_call;
            const model_len = trimmedLen(&p.model_id);
            const actor_role_len = trimmedLen(&p.actor_role);
            const workflow_len = trimmedLen(&p.workflow);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.model_id[0..model_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.prompt_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.response_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.token_estimate)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 5, p.retry_count)) return wire.status_no_space;
            if (actor_role_len != 0 and !c_abi.ballet.pbPushBytes(&enc, 6, p.actor_role[0..actor_role_len])) return wire.status_no_space;
            if (workflow_len != 0 and !c_abi.ballet.pbPushBytes(&enc, 7, p.workflow[0..workflow_len])) return wire.status_no_space;
            if (p.policy_decision_id != 0 and !c_abi.ballet.pbPushUint64(&enc, 8, p.policy_decision_id)) return wire.status_no_space;
            if (p.replay_substitution_id != 0 and !c_abi.ballet.pbPushUint64(&enc, 9, p.replay_substitution_id)) return wire.status_no_space;
        },
        4 => {
            const p = &event.payload.financial_adapter_call;
            const adapter_len = trimmedLen(&p.adapter_id);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.adapter_id[0..adapter_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.request_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.response_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.replay_substitution_id)) return wire.status_no_space;
        },
        5 => {
            const p = &event.payload.proposal;
            const proposal_len = trimmedLen(&p.proposal_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.proposal_type[0..proposal_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.proposal_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.approval_state)) return wire.status_no_space;
        },
        6 => {
            const p = &event.payload.destination_check;
            const dest_len = trimmedLen(&p.destination_type);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.destination_type[0..dest_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.allowlist_version)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.outcome)) return wire.status_no_space;
        },
        7 => {
            const p = &event.payload.limit_check;
            if (!c_abi.ballet.pbPushUint32(&enc, 1, p.limit_type)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 2, p.value)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 3, p.limit)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.outcome)) return wire.status_no_space;
        },
        8 => {
            const p = &event.payload.approval_required;
            const action_len = trimmedLen(&p.action_class);
            const path_len = trimmedLen(&p.approval_path);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.action_class[0..action_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 2, p.approval_path[0..path_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.proposal_hash)) return wire.status_no_space;
        },
        9 => {
            const p = &event.payload.denial;
            const action_len = trimmedLen(&p.action_class);
            const failed_len = trimmedLen(&p.failed_scope_dim);
            const taxonomy_id_len = trimmedLen(&p.taxonomy_id);
            const classification_code_len = trimmedLen(&p.classification_code);
            if (!c_abi.ballet.pbPushBytes(&enc, 1, p.action_class[0..action_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.reason_code)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 3, p.failed_scope_dim[0..failed_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 4, p.catalog_schema_version)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 5, p.taxonomy_id[0..taxonomy_id_len])) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 6, p.taxonomy_version)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushBytes(&enc, 7, p.classification_code[0..classification_code_len])) return wire.status_no_space;
        },
        10 => {
            const p = &event.payload.telemetry_checkpoint;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.metric_set_hash)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.source_offset_watermark)) return wire.status_no_space;
        },
        11 => {
            const p = &event.payload.replay_result;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.capsule_id)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 2, p.divergences)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint64(&enc, 3, p.first_divergent_seq)) return wire.status_no_space;
        },
        12 => {
            const p = &event.payload.deduplication;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.idempotency_key)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.is_duplicate)) return wire.status_no_space;
        },
        13 => {
            const p = &event.payload.case_creation;
            if (!c_abi.ballet.pbPushUint64(&enc, 1, p.basket_id)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 2, p.instrument_count)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushUint32(&enc, 3, p.rejected_count)) return wire.status_no_space;
            if (!c_abi.ballet.pbPushInt64(&enc, 4, p.total_allocated_cents)) return wire.status_no_space;
        },
        else => return wire.status_invalid_field,
    }
    if (!c_abi.ballet.pbSubmsgClose(&enc)) return wire.status_no_space;
    written.* = @intCast(c_abi.ballet.pbEncoderOutSz(&enc));
    if (!c_abi.ballet.pbEncoderFini(&enc)) return wire.status_no_space;
    @memcpy(out[0..written.*], scratch[0..written.*]);
    return wire.status_ok;
}

pub fn parseProtobuf(
    in: [*]const u8,
    in_sz: usize,
    event: *wire.WireEvent,
) c_int {
    event.* = std.mem.zeroes(wire.WireEvent);

    var inbuf: c_abi.ballet.PbInbuf = .{};
    c_abi.ballet.pbInbufInit(&inbuf, in[0..in_sz]);
    var tlv: c_abi.ballet.PbTlv = .{};

    while (c_abi.ballet.pbInbufSz(&inbuf) != 0) {
        if (!c_abi.ballet.pbReadTlv(&inbuf, &tlv)) return wire.status_invalid_protobuf;
        switch (tlv.field_id) {
            field_schema_version => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.schema_version = truncateChecked(u16, tlv.varint) orelse return wire.status_invalid_protobuf;
            },
            field_run_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.run_id = tlv.varint;
            },
            field_seq => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.seq = tlv.varint;
            },
            field_source_offset => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.source_offset = tlv.varint;
            },
            field_tile_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.tile_id, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_logical_actor_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.logical_actor_id = tlv.varint;
            },
            field_policy_version => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.policy_version, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_capability_envelope_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.capability_envelope_id_le, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_timestamp_ns => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.timestamp_ns = tlv.varint;
            },
            field_prev_hash => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.prev_hash = tlv.varint;
            },
            field_record_hash => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                event.header.record_hash = tlv.varint;
            },
            field_version => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.version, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_platform_tier => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.platform_tier, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_isolation_tier => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.isolation_tier, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_release_digest => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.release_digest, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            field_manifest_id => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                copyLenBytes(&event.header.manifest_id, &inbuf, tlv.len()) catch |err| return statusFromErr(err);
            },
            12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 => {
                if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                if (c_abi.ballet.pbInbufSz(&inbuf) < tlv.len()) return wire.status_invalid_protobuf;
                const rt = tlv.field_id - field_payload_base;
                event.record_type = truncateChecked(u8, rt) orelse return wire.status_invalid_protobuf;
                var payload_buf: c_abi.ballet.PbInbuf = .{};
                c_abi.ballet.pbInbufInit(&payload_buf, c_abi.ballet.pbInbufCur(&inbuf)[0..@intCast(tlv.len())]);
                const err = parsePayload(rt, &payload_buf, &event.payload);
                if (err != wire.status_ok) return err;
                c_abi.ballet.pbInbufAdvance(&inbuf, tlv.len());
            },
            else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(&inbuf, tlv.len()),
        }
    }

    return wire.status_ok;
}

fn parsePayload(record_type: u32, inbuf: *c_abi.ballet.PbInbuf, payload: *wire.WirePayload) c_int {
    var tlv: c_abi.ballet.PbTlv = .{};
    while (c_abi.ballet.pbInbufSz(inbuf) != 0) {
        if (!c_abi.ballet.pbReadTlv(inbuf, &tlv)) return wire.status_invalid_protobuf;
        switch (record_type) {
            0 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.source_event.source_system, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.source_event.event_type, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.source_event.raw_hash = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            1 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.normalization.source_event_hash = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.normalization.normalized_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.normalization.canonical_event_type, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            2 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.policy_decision.outcome = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.policy_decision.rule_id = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.failed_scope_dim, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.policy_decision.source_event_hash = tlv.varint;
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.policy_decision.catalog_schema_version = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.taxonomy_id, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.policy_decision.taxonomy_version = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                8 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.policy_decision.classification_code, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            3 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.model_id, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.prompt_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.response_hash = tlv.varint;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.token_estimate = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.retry_count = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.actor_role, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.model_call.workflow, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                8 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.policy_decision_id = tlv.varint;
                },
                9 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.model_call.replay_substitution_id = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            4 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.financial_adapter_call.adapter_id, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.financial_adapter_call.request_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.financial_adapter_call.response_hash = tlv.varint;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.financial_adapter_call.replay_substitution_id = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            5 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.proposal.proposal_type, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.proposal.proposal_hash = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.proposal.approval_state = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            6 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.destination_check.destination_type, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.destination_check.allowlist_version = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.destination_check.outcome = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            7 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.limit_check.limit_type = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.limit_check.value = @bitCast(tlv.varint);
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.limit_check.limit = @bitCast(tlv.varint);
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.limit_check.outcome = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            8 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.approval_required.action_class, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.approval_required.approval_path, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.approval_required.proposal_hash = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            9 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.denial.action_class, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.denial.reason_code = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.denial.failed_scope_dim, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.denial.catalog_schema_version = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                5 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.denial.taxonomy_id, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                6 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.denial.taxonomy_version = truncateChecked(u32, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                7 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_len) return wire.status_invalid_protobuf;
                    copyLenBytes(&payload.denial.classification_code, inbuf, tlv.len()) catch return wire.status_invalid_protobuf;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            10 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.telemetry_checkpoint.metric_set_hash = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.telemetry_checkpoint.source_offset_watermark = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            11 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.replay_result.capsule_id = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.replay_result.divergences = tlv.varint;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.replay_result.first_divergent_seq = tlv.varint;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            12 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.deduplication.idempotency_key = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    const is_duplicate = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                    if (is_duplicate > 1) return wire.status_invalid_protobuf;
                    payload.deduplication.is_duplicate = is_duplicate;
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            13 => switch (tlv.field_id) {
                1 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.case_creation.basket_id = tlv.varint;
                },
                2 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.case_creation.instrument_count = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                3 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.case_creation.rejected_count = truncateChecked(u8, tlv.varint) orelse return wire.status_invalid_protobuf;
                },
                4 => {
                    if (tlv.wire_type != c_abi.ballet.pb_wire_type_varint) return wire.status_invalid_protobuf;
                    payload.case_creation.total_allocated_cents = @bitCast(tlv.varint);
                },
                else => if (tlv.wire_type == c_abi.ballet.pb_wire_type_len) skipBytes(inbuf, tlv.len()),
            },
            else => return wire.status_invalid_protobuf,
        }
    }
    return wire.status_ok;
}

fn trimmedLen(buf: []const u8) usize {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) : (len += 1) {}
    return len;
}

fn zeroTail(buf: []u8, used: usize) void {
    if (used < buf.len) @memset(buf[used..], 0);
}

fn skipBytes(buf: *c_abi.ballet.PbInbuf, len: u64) void {
    if (c_abi.ballet.pbInbufSz(buf) >= len) c_abi.ballet.pbInbufAdvance(buf, len);
}

fn copyLenBytes(dst: []u8, buf: *c_abi.ballet.PbInbuf, len: u64) !void {
    if (len > dst.len) return error.InvalidProtobuf;
    if (c_abi.ballet.pbInbufSz(buf) < len) return error.InvalidProtobuf;
    const src = c_abi.ballet.pbInbufCur(buf)[0..@intCast(len)];
    @memcpy(dst[0..@intCast(len)], src);
    zeroTail(dst, @intCast(len));
    c_abi.ballet.pbInbufAdvance(buf, len);
}

fn truncateChecked(comptime T: type, value: u64) ?T {
    return if (value <= std.math.maxInt(T)) @intCast(value) else null;
}

fn statusFromErr(err: anyerror) c_int {
    return switch (err) {
        error.InvalidProtobuf => wire.status_invalid_protobuf,
        else => wire.status_invalid_protobuf,
    };
}
