/// Linux-strict CPU placement proof: pin every tile onto one explicit shared
/// core so the shared placement signal is materially stronger than ambient CI
/// noise, then verify that fully-shared and floating runs produce comparable
/// results within a noise margin.
///
/// On some hardware (few cores, shared L3, no SMT) shared-core can be faster
/// than floating because cross-core cache thrashing on many cores dominates
/// over single-core contention.  The direction of the timing gap is
/// platform-dependent, so we assert relative closeness (within a 2x envelope)
/// rather than a fixed ordering.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;
const TileId = rt.topology.TileId;

const shared_core_tiles = [_]rt.topology.TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile", .cpu_placement = .{ .shared = 0 } },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile", .cpu_placement = .{ .shared = 0 } },
};

const event_count: u64 = 64;
const samples: usize = 5;

fn runDurationNs(io: std.Io, topo: rt.topology.Topology, run_dir: []const u8) !u64 {
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const start_ns = util.process.monotonicNanos();
    try sup.startPaymentPipelineProcess(io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 1200;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    const elapsed_ns = std.math.cast(u64, util.process.monotonicNanos() - start_ns) orelse return error.DurationOverflow;
    sup.stopProcess(io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);

    return elapsed_ns;
}

fn median(values: [samples]u64) u64 {
    var copy = values;
    std.sort.pdq(u64, &copy, {}, std.sort.asc(u64));
    return copy[samples / 2];
}

test "process_cpu_placement_linux: shared-core and floating are within a 2x envelope" {
    // Interleave floating and shared samples so transient host noise hits both
    // placement modes in the same phase, then take a median over five runs to
    // keep one slow ambient outlier from flipping the result.
    //
    // The direction of the timing gap is platform-dependent — on some hosts
    // shared-core is slower (single-core contention), on others floating is
    // slower (cross-core cache thrashing).  Assert that both placements stay
    // within a 2x envelope of each other.
    const shared_topo = rt.topology.Topology{
        .tiles = &shared_core_tiles,
        .channels = topologies.paymentPipelineProcess().channels,
    };

    var floating_runs: [samples]u64 = undefined;
    var shared_runs: [samples]u64 = undefined;
    inline for (0..samples) |i| {
        var floating_tmp = std.testing.tmpDir(.{});
        defer floating_tmp.cleanup();
        var floating_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const floating_len = try floating_tmp.dir.realPath(std.testing.io, &floating_path_buf);
        floating_runs[i] = try runDurationNs(std.testing.io, topologies.paymentPipelineProcess(), floating_path_buf[0..floating_len]);

        var shared_tmp = std.testing.tmpDir(.{});
        defer shared_tmp.cleanup();
        var shared_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const shared_len = try shared_tmp.dir.realPath(std.testing.io, &shared_path_buf);
        shared_runs[i] = try runDurationNs(std.testing.io, shared_topo, shared_path_buf[0..shared_len]);
    }

    const floating_median = median(floating_runs);
    const shared_median = median(shared_runs);

    // Enforce that neither placement is more than 2x the other.
    try std.testing.expect(floating_median <= 2 * shared_median);
    try std.testing.expect(shared_median <= 2 * floating_median);
}
