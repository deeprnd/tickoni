/// CNC liveness of every stem tile in the payment pipeline, with real child
/// processes (tknorm, tkdedu, tkpoly, tkaudt and tkdiag are stem tiles here, and
/// so is metric, which runs fd_metric_tile.c's stem loop; tkings and tkrepl stay
/// on the generic path and are not examined).
/// The full investment workflow, which adds tkmodl, tkagnt, tkdisp, tkcase,
/// tktool and tkadpt, is covered in test_tile_tkagnt.zig with the same
/// assertions from stem_liveness.zig.
///
/// The run uses `event_count = 0`, which disables every event gate: no event
/// flows, no tile finishes, and each stem tile idles in its loop until the
/// supervisor's HALT. That isolates liveness from throughput: what is proved
/// is that an idle stem loop still reaches CNC `RUN` and keeps its heartbeat
/// advancing from housekeeping, and that a tile frozen with SIGSTOP stops
/// advancing it and is classified stale by the supervisor, as a generic-path
/// tile is. Nothing here reads a `.running` state as progress.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");
const stem_liveness = @import("stem_liveness");

const Supervisor = supervisor_mod.Supervisor;

fn startIdlePipeline(sup: *Supervisor, run_dir: []const u8) !void {
    var workspace_buf: [16]u8 = undefined;
    // Idle (event_count 0): no events, so no producer on tkings's input.
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 0,
        .heartbeat_stale_after_ns = stem_liveness.stale_after_ns,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    });
}

fn expectNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |handle| try std.testing.expect(handle.state != .crashed);
}

test "stem_heartbeat: every stem tile reaches CNC RUN and advances its heartbeat while idle" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdlePipeline(&sup, run_dir);

    try stem_liveness.expectStemTilesAlive(&sup);
    try stem_liveness.expectNoStemTileStale(&sup);
    try expectNoCrash(&sup);
}

test "stem_heartbeat: a frozen tkdiag is classified stale and no other stem tile is" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // The audit finding: an observer stem tile with no heartbeat could not be
    // told apart from a healthy one. tkdiag does nothing but spin, so a
    // stopped process is the only way it can stop making progress.
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdlePipeline(&sup, run_dir);
    try stem_liveness.expectStemTilesAlive(&sup);

    try stem_liveness.expectFrozenTileGoesStaleAlone(&sup, stem_liveness.indexOf(&sup, rt.tile_ids.tkdiag));
    try expectNoCrash(&sup);
}

/// Window over which an idle tile's CPU use is measured. Long against the
/// Windows GetProcessTimes granularity (a timer tick, about 15.6 ms).
const idle_window_ns: u64 = 2 * std.time.ns_per_s;
/// Upper bound on the CPU an idle stem tile may use over the window, as a
/// fraction of one core: 1/5. An idle tile that spins uses a whole core on an
/// idle host and still about a third of one when nine spinning tiles share
/// four cores. One that sleeps uses a few percent (tile-orchestration.md, "The
/// same deviation in `fd_stem`").
const idle_cpu_max_num: u64 = 1;
const idle_cpu_max_den: u64 = 5;
const max_tiles = 16;

fn tileCpuNanos(sup: *const Supervisor, idx: usize) !u64 {
    const id = sup.monitor()[idx].pid orelse return error.NoChildPid;
    return c_abi.os_stats.processCpuNanos(util.os_api.processDiagnosticPid(id));
}

test "stem_heartbeat: an idle stem tile sleeps instead of spinning on a core" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdlePipeline(&sup, run_dir);
    // Every stem tile is in its loop (RUN, heartbeat moving) before measuring.
    try stem_liveness.expectStemTilesAlive(&sup);

    const tile_cnt = sup.monitor().len;
    try std.testing.expect(tile_cnt <= max_tiles);
    var before: [max_tiles]u64 = undefined;
    for (0..tile_cnt) |idx| {
        if (stem_liveness.isStem(idx, &sup)) before[idx] = try tileCpuNanos(&sup, idx);
    }
    const t0 = util.process.monotonicNanos();
    util.process.sleepNanos(idle_window_ns);
    const wall_ns: u64 = @intCast(util.process.monotonicNanos() - t0);

    // Every tile is reported before failing, so one run shows all offenders.
    var spinning: usize = 0;
    for (0..tile_cnt) |idx| {
        if (!stem_liveness.isStem(idx, &sup)) continue;
        const used_ns = try tileCpuNanos(&sup, idx) - before[idx];
        const spins = used_ns * idle_cpu_max_den > wall_ns * idle_cpu_max_num;
        if (spins) spinning += 1;
        std.debug.print("stem_heartbeat: idle {s} used {d} ms of CPU in {d} ms{s}\n", .{
            sup.topo.tiles[idx].name.slice(), used_ns / std.time.ns_per_ms,
            wall_ns / std.time.ns_per_ms,     if (spins) " (spinning)" else "",
        });
    }
    if (spinning != 0) return error.IdleStemTileSpins;
    try expectNoCrash(&sup);
}

test "stem_heartbeat: a sleeping idle stem tile keeps its heartbeat for the whole idle window" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // The idle sleep must not cost a tile its liveness: polled for the whole
    // window, no idle stem tile is ever classified stale. The liveness
    // threshold (1 s), not the 100 ms default, so a host scheduler stall (a VM
    // pausing its vCPUs) is not read as a stale tile; a healthy idle tile
    // heartbeats about every STEM_LAZY (tile-orchestration.md, "Staleness
    // budget"). Spinning instead of sleeping is caught by the CPU test above.
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdlePipeline(&sup, run_dir);
    try stem_liveness.expectStemTilesAlive(&sup);

    const t0 = util.process.monotonicNanos();
    while (@as(u64, @intCast(util.process.monotonicNanos() - t0)) < idle_window_ns) {
        try stem_liveness.expectNoStemTileStale(&sup);
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try expectNoCrash(&sup);
}

test "stem_heartbeat: every stem tile of the pipeline is classified stale when frozen" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdlePipeline(&sup, run_dir);
    try stem_liveness.expectStemTilesAlive(&sup);

    try stem_liveness.expectEveryFrozenStemTileGoesStale(&sup);
    try expectNoCrash(&sup);
}
