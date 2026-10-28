/// AuditLog — append-only audit log for tkaudt process-mode and replay.
/// Used by runtime.zig (replay checksums) and process.zig (audit_log allocation).
const std = @import("std");
const audit = @import("tkaudt");
const audit_shared = @import("audit_shared.zig");

pub const Decision = enum(u8) {
    allow,
    deny,
    malformed_drop,
    duplicate_drop,
};

pub const AuditAppendInput = struct {
    source_offset: u64,
    event_hash: u64,
    decision: Decision,
    tile_id: [6]u8,
};

pub const AuditLog = struct {
    records: []audit.AuditEvent,
    count: usize = 0,
    prev_hash: u64 = audit_shared.audit_seed,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !AuditLog {
        return .{ .records = try allocator.alloc(audit.AuditEvent, capacity) };
    }

    pub fn deinit(self: *AuditLog, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
    }

    pub fn append(self: *AuditLog, msg: AuditAppendInput) error{AuditFull}!void {
        if (self.count >= self.records.len) return error.AuditFull;
        const event = buildPolicyDecisionEvent(
            @intCast(self.count),
            msg.source_offset,
            msg.event_hash,
            msg.decision,
            msg.tile_id,
            self.prev_hash,
        );
        self.records[self.count] = event;
        self.count += 1;
        self.prev_hash = event.header.record_hash;
    }
};

/// Build an audit event with default (zero) metadata.
/// For production use, fill metadata via fillEventMetadata before serialization.
pub fn buildPolicyDecisionEvent(
    seq: u64,
    source_offset: u64,
    event_hash: u64,
    decision: Decision,
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
        .capability_envelope_id = std.mem.zeroes([16]u8),
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
            .outcome = outcome,
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

/// Fill event metadata with the runtime's version/tier/digest info.
pub fn fillEventMetadata(event: *audit.AuditEvent, version: []const u8, platform_tier: []const u8, isolation_tier: []const u8, release_digest: []const u8, manifest_id: []const u8) void {
    @memcpy(event.header.version[0..version.len], version);
    @memcpy(event.header.platform_tier[0..platform_tier.len], platform_tier);
    @memcpy(event.header.isolation_tier[0..isolation_tier.len], isolation_tier);
    @memcpy(event.header.release_digest[0..release_digest.len], release_digest);
    @memcpy(event.header.manifest_id[0..manifest_id.len], manifest_id);
}
