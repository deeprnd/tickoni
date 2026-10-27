const std = @import("std");
const schema = @import("audit_schema");

pub const audit_schema_version = schema.audit_schema_version;
pub const PolicyOutcome = schema.PolicyOutcome;
pub const LimitType = schema.LimitType;
pub const RecordType = schema.RecordType;
pub const SourceEventPayload = schema.SourceEventPayload;
pub const NormalizationPayload = schema.NormalizationPayload;
pub const PolicyDecisionPayload = schema.PolicyDecisionPayload;
pub const ModelCallPayload = schema.ModelCallPayload;
pub const FinancialAdapterCallPayload = schema.FinancialAdapterCallPayload;
pub const ProposalPayload = schema.ProposalPayload;
pub const DestinationCheckPayload = schema.DestinationCheckPayload;
pub const LimitCheckPayload = schema.LimitCheckPayload;
pub const ApprovalRequiredPayload = schema.ApprovalRequiredPayload;
pub const DenialPayload = schema.DenialPayload;
pub const TelemetryCheckpointPayload = schema.TelemetryCheckpointPayload;
pub const ReplayResultPayload = schema.ReplayResultPayload;
pub const DeduplicationPayload = schema.DeduplicationPayload;
pub const CaseCreationPayload = schema.CaseCreationPayload;
pub const Header = schema.Header;
pub const AuditEvent = schema.AuditEvent;

// ---------------------------------------------------------------------------
// FNV-1a hash helpers — mirrors the stem tile's inline hash for the
// policy_decision payload fields it exercises.
// Uses @mulWithOverflow for overflow-safe comptime hashing.
// ---------------------------------------------------------------------------

const AUDIT_SEED: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x100000001b3;

fn mul_fnv(h: u64, x: u64) u64 {
    // FNV-1a: XOR then multiply. Overflow is intentional and part of the
    // algorithm — we discard the carry with @mulWithOverflow.
    const result = @mulWithOverflow(h ^ x, FNV_PRIME);
    _ = result[1];
    return result[0];
}

fn fnv1a_hash_6(
    seq: u64,
    source_offset: u64,
    prev_hash: u64,
    outcome: u8,
    source_event_hash: u64,
) u64 {
    var h: u64 = AUDIT_SEED;
    h = mul_fnv(h, seq);
    h = mul_fnv(h, source_offset);
    h = mul_fnv(h, prev_hash);
    h = mul_fnv(h, @as(u64, outcome));
    h = mul_fnv(h, source_event_hash);
    return h;
}

// ---------------------------------------------------------------------------
// Schema and layout invariants
// ---------------------------------------------------------------------------

test "AuditEvent struct: header at offset 0, payload follows" {
    const ae_size = @sizeOf(schema.AuditEvent);
    const hdr_size = @sizeOf(schema.Header);
    const union_size = @sizeOf(schema.AuditEvent.Payload);

    try std.testing.expectEqual(@as(usize, 0), @offsetOf(schema.AuditEvent, "header"));
    try std.testing.expectEqual(hdr_size, @offsetOf(schema.AuditEvent, "payload"));
    try std.testing.expectEqual(ae_size, hdr_size + union_size);
}

test "PolicyOutcome enum has 7 values" {
    const outcomes = std.meta.tags(schema.PolicyOutcome);
    try std.testing.expectEqual(@as(usize, 7), outcomes.len);
}

test "PolicyOutcome C↔Zig backing size matches" {
    const c_audit = @import("audit_mod");
    // C defines PolicyOutcome as int8_t — verify the translate-c import
    // matches.
    try std.testing.expectEqual(
        @sizeOf(c_audit.PolicyOutcome),
        @sizeOf(schema.PolicyOutcome),
    );
    try std.testing.expectEqual(
        @sizeOf(std.meta.Tag(schema.PolicyOutcome)),
        @sizeOf(c_audit.PolicyOutcome),
    );
}

test "PolicyDecisionPayload C↔Zig layout parity" {
    const c_audit = @import("audit_mod");
    try std.testing.expectEqual(
        @sizeOf(c_audit.PolicyDecisionPayload),
        @sizeOf(schema.PolicyDecisionPayload),
    );
    try std.testing.expectEqual(
        @alignOf(c_audit.PolicyDecisionPayload),
        @alignOf(schema.PolicyDecisionPayload),
    );
    // Verify each field offset matches byte-for-byte.
    const info = @typeInfo(schema.PolicyDecisionPayload).@"struct";
    inline for (info.field_names) |fname| {
        try std.testing.expectEqual(
            @offsetOf(c_audit.PolicyDecisionPayload, fname),
            @offsetOf(schema.PolicyDecisionPayload, fname),
        );
    }
}

test "audit_schema_version is 2" {
    try std.testing.expectEqual(
        @as(u16, 2),
        schema.audit_schema_version,
    );
}

test "FNV-1a hash is deterministic for identical inputs" {
    const h1 = fnv1a_hash_6(0, 42, AUDIT_SEED, 0, 9001);
    const h2 = fnv1a_hash_6(0, 42, AUDIT_SEED, 0, 9001);

    try std.testing.expectEqual(h1, h2);
}

test "audit hash differs when any input changes" {
    const base_hash = fnv1a_hash_6(5, 100, AUDIT_SEED, 0, 1234);

    try std.testing.expect(fnv1a_hash_6(6, 100, AUDIT_SEED, 0, 1234) != base_hash);
    try std.testing.expect(fnv1a_hash_6(5, 101, AUDIT_SEED, 0, 1234) != base_hash);
    try std.testing.expect(fnv1a_hash_6(5, 100, 1, 0, 1234) != base_hash);
    try std.testing.expect(fnv1a_hash_6(5, 100, AUDIT_SEED, 0, 1235) != base_hash);
    try std.testing.expect(fnv1a_hash_6(5, 100, AUDIT_SEED, 0, 1235) != base_hash);
}

test "hash chain seeds with AUDIT_SEED as first prev_hash" {
    const h0 = fnv1a_hash_6(0, 0, AUDIT_SEED, 0, 0);

    try std.testing.expect(h0 != AUDIT_SEED);

    const h1 = fnv1a_hash_6(0, 0, h0, 0, 0);
    try std.testing.expect(h0 != h1);
}
