/// v2.14.S1 M6 / Release Gate demo/replay parity (T14): CPU placement is a
/// scheduling policy, not a correctness dimension — floating, explicit
/// shared-core, and explicit exclusive-core runs of the same deterministic
/// input must all reach identical final pipeline metrics through the real
/// supervisor. "Demo and replay results match under both exclusive-core and
/// shared-core configs" (Release Gate) requires the exclusive-core leg
/// specifically; floating is the third leg proving the baseline itself.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

/// Same 8 tiles as topologies.paymentPipelineProcess(), except tkpoly and
/// tkaudt both declare an explicit shared placement on CPU 0 — a different
/// pair than test_process_cpu_placement.zig pins, so this test's coverage
/// is not just a duplicate of M5's.
const shared_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile" },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("metric") catch unreachable, .name = "metric" },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

/// Same 8 tiles, tkpoly and tkaudt each pinned to their own exclusive CPU
/// (0 and 1 — distinct ids, since two tiles cannot both declare `exclusive`
/// on the same CPU). Same tile pair as shared_core_tiles for a like-for-like
/// comparison of placement mode, not tile identity.
const exclusive_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile" },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .cpu_placement = .{ .exclusive = 0 } },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .cpu_placement = .{ .exclusive = 1 } },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("metric") catch unreachable, .name = "metric" },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

const event_count: u64 = 24;

fn runToCompletion(io: std.Io, topo: rt.topology.Topology, run_dir: []const u8, workspace_name: []const u8) !Supervisor.ProcessMetricSnapshot {
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    try sup.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
    });

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    try sup.stopProcess(io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    return metrics;
}

test "process_demo_parity: floating, shared-core, and exclusive-core CPU placement all reach identical pipeline metrics" {
    if (false) return error.SkipZigTest;
    var tmp_floating = util.tmpDir();
    var floating_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const floating_len = try tmp_floating.dir.realPath(std.testing.io, &floating_path_buf);
    const floating_run_dir = floating_path_buf[0..floating_len];

    var ws_buf: [16]u8 = undefined;
    const floating_metrics = try runToCompletion(std.testing.io, topologies.paymentPipelineProcess(), floating_run_dir, util.nextWorkspaceName(&ws_buf));

    var tmp_shared = util.tmpDir();
    var shared_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const shared_len = try tmp_shared.dir.realPath(std.testing.io, &shared_path_buf);
    const shared_run_dir = shared_path_buf[0..shared_len];

    const shared_topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };
    const shared_metrics = try runToCompletion(std.testing.io, shared_topo, shared_run_dir, util.nextWorkspaceName(&ws_buf));

    var tmp_exclusive = util.tmpDir();
    var exclusive_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exclusive_len = try tmp_exclusive.dir.realPath(std.testing.io, &exclusive_path_buf);
    const exclusive_run_dir = exclusive_path_buf[0..exclusive_len];

    const exclusive_topo = rt.topology.Topology{
        .tiles = &exclusive_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };
    const exclusive_metrics = try runToCompletion(std.testing.io, exclusive_topo, exclusive_run_dir, util.nextWorkspaceName(&ws_buf));

    // Compare all fields except metric_boot_timestamp (varies by wall-clock time
    // across runs; CPU placement is a scheduling policy, not a correctness
    // dimension — pipeline counters must match).
    try std.testing.expectEqual(floating_metrics.produced, shared_metrics.produced);
    try std.testing.expectEqual(floating_metrics.normalized, shared_metrics.normalized);
    try std.testing.expectEqual(floating_metrics.invalid, shared_metrics.invalid);
    try std.testing.expectEqual(floating_metrics.duplicates, shared_metrics.duplicates);
    try std.testing.expectEqual(floating_metrics.allowed, shared_metrics.allowed);
    try std.testing.expectEqual(floating_metrics.denied, shared_metrics.denied);
    try std.testing.expectEqual(floating_metrics.audited, shared_metrics.audited);
    try std.testing.expectEqual(floating_metrics.replay_checked, shared_metrics.replay_checked);
    try std.testing.expectEqual(floating_metrics.replay_match, shared_metrics.replay_match);
    try std.testing.expectEqual(floating_metrics.metric_snapshots, shared_metrics.metric_snapshots);
    try std.testing.expectEqual(floating_metrics.metric_backpressure_waits, shared_metrics.metric_backpressure_waits);
    try std.testing.expectEqual(floating_metrics.diag_crash_count, shared_metrics.diag_crash_count);
    try std.testing.expectEqual(floating_metrics.diag_sandbox_count, shared_metrics.diag_sandbox_count);
    try std.testing.expectEqual(floating_metrics.produced, exclusive_metrics.produced);
    try std.testing.expectEqual(floating_metrics.normalized, exclusive_metrics.normalized);
    try std.testing.expectEqual(floating_metrics.invalid, exclusive_metrics.invalid);
    try std.testing.expectEqual(floating_metrics.duplicates, exclusive_metrics.duplicates);
    try std.testing.expectEqual(floating_metrics.allowed, exclusive_metrics.allowed);
    try std.testing.expectEqual(floating_metrics.denied, exclusive_metrics.denied);
    try std.testing.expectEqual(floating_metrics.audited, exclusive_metrics.audited);
    try std.testing.expectEqual(floating_metrics.replay_checked, exclusive_metrics.replay_checked);
    try std.testing.expectEqual(floating_metrics.replay_match, exclusive_metrics.replay_match);
    try std.testing.expectEqual(floating_metrics.metric_snapshots, exclusive_metrics.metric_snapshots);
    try std.testing.expectEqual(floating_metrics.metric_backpressure_waits, exclusive_metrics.metric_backpressure_waits);
    try std.testing.expectEqual(floating_metrics.diag_crash_count, exclusive_metrics.diag_crash_count);
    try std.testing.expectEqual(floating_metrics.diag_sandbox_count, exclusive_metrics.diag_sandbox_count);
    try std.testing.expectEqual(event_count, floating_metrics.produced);
    try std.testing.expectEqual(event_count, floating_metrics.audited);
}
