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
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile" },
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
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile" },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

const event_count: u64 = 24;

fn runToCompletion(io: std.Io, topo: rt.topology.Topology, run_dir: []const u8) !Supervisor.ProcessMetricSnapshot {
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    sup.stopProcess(io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    return metrics;
}

test "process_demo_parity: floating, shared-core, and exclusive-core CPU placement all reach identical pipeline metrics" {
    var tmp_floating = std.testing.tmpDir(.{});
    defer tmp_floating.cleanup();
    var floating_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const floating_len = try tmp_floating.dir.realPath(std.testing.io, &floating_path_buf);
    const floating_run_dir = floating_path_buf[0..floating_len];

    const floating_metrics = try runToCompletion(std.testing.io, topologies.paymentPipelineProcess(), floating_run_dir);

    var tmp_shared = std.testing.tmpDir(.{});
    defer tmp_shared.cleanup();
    var shared_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const shared_len = try tmp_shared.dir.realPath(std.testing.io, &shared_path_buf);
    const shared_run_dir = shared_path_buf[0..shared_len];

    const shared_topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };
    const shared_metrics = try runToCompletion(std.testing.io, shared_topo, shared_run_dir);

    var tmp_exclusive = std.testing.tmpDir(.{});
    defer tmp_exclusive.cleanup();
    var exclusive_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exclusive_len = try tmp_exclusive.dir.realPath(std.testing.io, &exclusive_path_buf);
    const exclusive_run_dir = exclusive_path_buf[0..exclusive_len];

    const exclusive_topo = rt.topology.Topology{
        .tiles = &exclusive_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };
    const exclusive_metrics = try runToCompletion(std.testing.io, exclusive_topo, exclusive_run_dir);

    try std.testing.expectEqual(floating_metrics, shared_metrics);
    try std.testing.expectEqual(floating_metrics, exclusive_metrics);
    try std.testing.expectEqual(event_count, floating_metrics.produced);
    try std.testing.expectEqual(event_count, floating_metrics.audited);
}
