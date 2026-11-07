/// Shared audit constants and helpers extracted from audit_sink.zig.
///
/// This module holds symbols that consumers need independently of AuditLog:
///   - audit_seed: the FNV-1a seed used for event hashing
///   - buildPolicyDecisionEvent: builds an AuditEvent from a policy decision
///
/// AuditLog, Decision, and AuditAppendInput stay in audit_sink.zig because
/// they are needed by the audit log builder (runtime.zig's PaymentPipelineState)
/// and by mod.zig's re-export for external consumers.
const std = @import("std");
const audit = @import("audit_tile");
const audit_sink = @import("audit_sink.zig");

/// FNV-1a seed used for event hashing and the first audit record's prev_hash.
/// Must match the C value in audit_schema.h (AUDIT_SEED).
pub const audit_seed: u64 = 0xcbf29ce484222325;

/// Build an audit event with default (zero) metadata.
/// For production use, fill metadata via fillEventMetadata before serialization.
pub fn buildPolicyDecisionEvent(
    seq: u64,
    source_offset: u64,
    event_hash: u64,
    decision: audit_sink.Decision,
    tile_id: [6]u8,
    prev_hash: u64,
) audit.AuditEvent {
    const outcome: audit.PolicyOutcome = switch (decision) {
        .allow => .allow,
        .deny => .deny,
        .malformed_drop => .malformed_drop,
        .duplicate_drop => .duplicate_drop,
    };
    return audit.buildEvent(.{
        .schema_version = audit.audit_schema_version,
        .run_id = 0,
        .seq = seq,
        .source_offset = source_offset,
        .tile_id = tile_id,
        .logical_actor_id = 0,
        .policy_version = std.mem.zeroes([32]u8),
        .capability_envelope_id = 0,
        .timestamp_ns = 0,
        .prev_hash = prev_hash,
        .record_hash = 0,
        .version = std.mem.zeroes([64]u8),
        .platform_tier = std.mem.zeroes([64]u8),
        .isolation_tier = std.mem.zeroes([64]u8),
        .release_digest = std.mem.zeroes([64]u8),
        .manifest_id = std.mem.zeroes([64]u8),
    }, .{
        .policy_decision = .{
            .outcome = @backingInt(outcome),
            .rule_id = 0,
            .failed_scope_dim = std.mem.zeroes([32]u8),
            .source_event_hash = event_hash,
            .catalog_schema_version = 0,
            .taxonomy_id = std.mem.zeroes([32]u8),
            .taxonomy_version = 0,
            .classification_code = std.mem.zeroes([32]u8),
        },
    });
}
