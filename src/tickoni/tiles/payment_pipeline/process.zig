/// v2.14.S1 process-mode payment-pipeline run configuration: the single
/// file the supervisor writes once per run (writeProcessConfig below) and
/// every stem tile reads before its C harness starts (readProcessConfig,
/// via src/app/tickoni/tile_main_config.zig). The decision logic itself —
/// hashing, framing validation, dedup comparison, policy decision, audit
/// record building — lives in runtime.zig/audit_sink.zig and the stem
/// shims; this file owns only the config handoff.
///
/// v2.14.S8.T2: the config carries a PaymentPipelineConfig by value instead
/// of reading event_count/policy_limit_cents/duplicate/inject_malformed off
/// a LaunchSpec — this file has no dependency on LaunchSpec's shape at all.
///
const std = @import("std");
const rt = @import("runtime");
const util = @import("util");
const payment_runtime = @import("runtime.zig");

// ---------------------------------------------------------------------------
// Payment-pipeline process-mode config: round-tripped through a single file
// shared by every tile in the run (identical for all of them), separate
// from each tile's own LaunchSpec. Same magic/version/fail-closed idiom as
// runtime/launch_spec.zig's LaunchSpec.
// ---------------------------------------------------------------------------

pub const process_config_magic: u32 = 0x544b5043; // "TKPC"
/// v4: ModelRequestSource carries per-slot tiers, the prompt/response shape and a
/// test-only stream fault.
/// v5: the pipeline config carries the full workflow's dispatch template.
/// v6: the pipeline config no longer carries the thread-mode ingest sandbox-failure hook.
pub const process_config_version: u16 = 6;

pub const StuckTileHook = struct {
    tile_idx: u32,
    after_messages: u64 = 0,
    sleep_ns: u64 = 60 * std.time.ns_per_s,
};

pub const ProcessRuntimeConfig = struct {
    pipeline: payment_runtime.PaymentPipelineConfig = .{},
    /// Test-only hook for supervisor heartbeat-staleness integration proofs:
    /// after `after_messages` iterations, the selected tile sleeps forever
    /// without emitting further heartbeats or observing HALT.
    stuck_tile: ?StuckTileHook = null,
};

pub const ProcessConfigFile = struct {
    magic_field: u32 = process_config_magic,
    version_field: u16 = process_config_version,
    cfg: ProcessRuntimeConfig = .{},
};

pub fn writeProcessConfig(cfg: ProcessRuntimeConfig, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
    const file_struct = ProcessConfigFile{ .cfg = cfg };
    var file = try rt.file_io.createFile(io, dir, sub_path);
    defer file.close(io);
    try file.writePositionalAll(io, std.mem.asBytes(&file_struct), 0);
}

pub fn readProcessConfig(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !ProcessRuntimeConfig {
    var file = try rt.file_io.openFile(io, dir, sub_path);
    defer file.close(io);
    var file_struct: ProcessConfigFile = undefined;
    const buf = std.mem.asBytes(&file_struct);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != @sizeOf(ProcessConfigFile)) return error.ProcessConfigTruncated;
    if (file_struct.magic_field != process_config_magic) return error.ProcessConfigBadMagic;
    if (file_struct.version_field != process_config_version) return error.ProcessConfigUnsupportedVersion;
    return file_struct.cfg;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ProcessConfig round-trips through a file" {
    const tmp = util.tmpDir();

    const cfg = ProcessRuntimeConfig{
        .pipeline = .{
            .event_count = 123,
            .policy_limit_cents = 45_600,
            .duplicate = .{ .offset = 3, .source = 1 },
            .inject_malformed = true,
        },
        .stuck_tile = .{ .tile_idx = 2, .after_messages = 7, .sleep_ns = 1234 },
    };
    try writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    const read_back = try readProcessConfig(std.testing.io, tmp.dir, "payment_pipeline.config");
    try std.testing.expectEqual(@as(u64, 123), read_back.pipeline.event_count);
    try std.testing.expectEqual(@as(i64, 45_600), read_back.pipeline.policy_limit_cents);
    if (read_back.pipeline.duplicate) |dup| {
        try std.testing.expectEqual(@as(u64, 3), dup.offset);
        try std.testing.expectEqual(@as(u64, 1), dup.source);
    } else {
        try std.testing.expect(false);
    }
    try std.testing.expect(read_back.pipeline.inject_malformed);
    try std.testing.expectEqual(@as(?u32, 2), if (read_back.stuck_tile) |hook| hook.tile_idx else null);
    try std.testing.expectEqual(@as(?u64, 7), if (read_back.stuck_tile) |hook| hook.after_messages else null);
}

test "ProcessConfig readProcessConfig rejects a truncated file" {
    var tmp = util.tmpDir();

    var file = try tmp.dir.createFile(std.testing.io, "short.config", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigTruncated, readProcessConfig(std.testing.io, tmp.dir, "short.config"));
}

test "ProcessConfig readProcessConfig rejects a bad magic" {
    var tmp = util.tmpDir();

    var file_struct = ProcessConfigFile{};
    file_struct.magic_field = 0xdeadbeef;
    var file = try tmp.dir.createFile(std.testing.io, "bad_magic.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigBadMagic, readProcessConfig(std.testing.io, tmp.dir, "bad_magic.config"));
}
