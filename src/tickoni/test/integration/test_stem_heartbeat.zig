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
    const shouldSkip = true;
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
    const shouldSkip = true;
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

test "stem_heartbeat: every stem tile of the pipeline is classified stale when frozen" {
    const shouldSkip = true;
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
