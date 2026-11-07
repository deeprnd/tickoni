const std = @import("std");
const audit = @import("audit");
const audit_consts = @import("audit_consts");

pub const AuditAppendInput = struct {
    source_offset: u64,
    event_hash: u64,
    decision: Decision,
    tile_id: [6]u8,
};

pub const Decision = enum(u8) {
    allow,
    deny,
    malformed_drop,
    duplicate_drop,
};

pub const audit_seed: u64 = audit_consts.AUDIT_INITIAL_HASH;

pub const AuditLog = struct {
    records: []audit.AuditEvent,
    count: usize = 0,
    prev_hash: u64 = audit_seed,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !AuditLog {
        return .{ .records = try allocator.alloc(audit.AuditEvent, capacity) };
    }

    pub fn deinit(self: *AuditLog, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
    }

    pub fn append(self: *AuditLog, msg: AuditAppendInput) error{AuditFull}!void {
        if (self.count >= self.records.len) return error.AuditFull;
        const outcome: audit.PolicyOutcome = switch (msg.decision) {
            .allow => .allow,
            .deny => .deny,
            .malformed_drop => .malformed_drop,
            .duplicate_drop => .duplicate_drop,
        };
        const event = audit.buildEvent(.{
            .schema_version = audit.audit_schema_version,
            .run_id = 0,
            .seq = @intCast(self.count),
            .source_offset = msg.source_offset,
            .tile_id = msg.tile_id,
            .logical_actor_id = 0,
            .policy_version = std.mem.zeroes([32]u8),
            .capability_envelope_id = 0,
            .timestamp_ns = 0,
            .prev_hash = self.prev_hash,
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
                .source_event_hash = msg.event_hash,
                .catalog_schema_version = 0,
                .taxonomy_id = std.mem.zeroes([32]u8),
                .taxonomy_version = 0,
                .classification_code = std.mem.zeroes([32]u8),
            },
        });
        self.records[self.count] = event;
        self.count += 1;
        self.prev_hash = event.header.record_hash;
    }
};
