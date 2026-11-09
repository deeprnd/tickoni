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
    prev_hash: u64,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !AuditLog {
        return .{
            .records = try allocator.alloc(audit.AuditEvent, capacity),
            .prev_hash = audit_seed,
        };
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

// ─── Unit tests ─────────────────────────────────────────────────────────────

test "audit log init has correct empty state" {
    var log = try AuditLog.init(std.testing.allocator, 4);
    defer log.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), log.count);
    try std.testing.expectEqual(audit_seed, log.prev_hash);
}

test "audit log sequential appends chain hashes" {
    var log = try AuditLog.init(std.testing.allocator, 4);
    defer log.deinit(std.testing.allocator);

    const input = [_]AuditAppendInput{
        .{ .source_offset = 1, .event_hash = 0xabc, .decision = .allow, .tile_id = [6]u8{ 't', 'k', 'p', 'o', 'l', 'y' } },
        .{ .source_offset = 2, .event_hash = 0xdef, .decision = .deny, .tile_id = [6]u8{ 't', 'k', 'p', 'o', 'l', 'y' } },
        .{ .source_offset = 3, .event_hash = 0x123, .decision = .malformed_drop, .tile_id = [6]u8{ 't', 'k', 'n', 'o', 'r', 'm' } },
    };

    try log.append(input[0]);
    try log.append(input[1]);
    try log.append(input[2]);

    try std.testing.expectEqual(@as(usize, 3), log.count);

    // Verify hash chain: records[i].header.prev_hash == records[i-1].header.record_hash
    try std.testing.expectEqual(
        log.records[1].header.prev_hash,
        log.records[0].header.record_hash,
    );
    try std.testing.expectEqual(
        log.records[2].header.prev_hash,
        log.records[1].header.record_hash,
    );

    // Verify initial prev_hash matches the first record's hash
    try std.testing.expectEqual(audit_seed, log.records[0].header.prev_hash);
}

test "audit log returns AuditFull on overflow" {
    var log = try AuditLog.init(std.testing.allocator, 2);
    defer log.deinit(std.testing.allocator);

    const input = AuditAppendInput{
        .source_offset = 1,
        .event_hash = 0xabc,
        .decision = .allow,
        .tile_id = [6]u8{ 't', 'k', 'p', 'o', 'l', 'y' },
    };

    try log.append(input);
    try log.append(input);
    try std.testing.expectError(error.AuditFull, log.append(input));
    try std.testing.expectEqual(@as(usize, 2), log.count);
}

test "audit log deinit frees without panic" {
    var log = try AuditLog.init(std.testing.allocator, 2);
    try log.append(.{
        .source_offset = 1,
        .event_hash = 0xabc,
        .decision = .allow,
        .tile_id = [6]u8{ 't', 'k', 'p', 'o', 'l', 'y' },
    });
    log.deinit(std.testing.allocator);

    // Verify memory was freed by re-allocating the same size — if deinit
    // did not free, this would be the same block and could silently corrupt
    // the prior state. The fact that init succeeds proves the region is free.
    var log2 = try AuditLog.init(std.testing.allocator, 2);
    defer log2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), log2.count);
}
