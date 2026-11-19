/// Process integration contracts for tkdiag's fd_stem lifecycle, with real
/// child processes in the payment-pipeline topology (tkdiag is its 0-in, 0-out
/// observer). Identity and scratch-footprint contracts live in
/// c_abi/tkdiag.zig; the supervisor's launch-mode routing is asserted in
/// tile_registry_test.zig.
///
/// tkdiag shuts down on CNC HALT only, like the metric tile: it has no input to
/// exhaust, and an iteration-count bound is not a duration (a 0-input stem loop
/// spins). The lifecycle proof is therefore that it is still running well after
/// start, and that a supervisor HALT then stops it cleanly. Probing
/// /proc/<pid>/cmdline for "__stem-run", as the tkpoly test does, is not used:
/// the registry assertion covers launch mode without a race.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

const max_polls: u32 = 400;
const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
const event_count: u64 = 8;

fn diagTileIndex(sup: *const Supervisor) usize {
    for (sup.topo.tiles, 0..) |tile, i| {
        if (tile.name.eql(rt.tile_ids.tkdiag)) return i;
    }
    unreachable; // paymentPipelineProcess() configures tkdiag.
}

fn startPipeline(sup: *Supervisor, run_dir: []const u8) !void {
    var workspace_buf: [16]u8 = undefined;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .policy_limit_cents = 1_000,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    });
}

fn assertNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |handle| try std.testing.expect(handle.state != .crashed);
}

test "tkdiag_integration: stem tkdiag keeps running until the supervisor halts it, then stops cleanly" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startPipeline(&sup, run_dir);

    // Watch for the whole window in which an iteration-bounded tkdiag would have
    // stopped itself (an earlier design did, within it). A self-exit or a crash
    // here fails the test on the first poll that sees it.
    const diag_idx = diagTileIndex(&sup);
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        try std.testing.expectEqual(rt.tile.TileState.running, sup.monitor()[diag_idx].state);
        util.process.sleepNanos(poll_interval_ns);
    }

    // CNC HALT is the only thing that stops it.
    try sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[diag_idx].state);
    try assertNoCrash(&sup);
}

test "tkdiag_integration: pipeline completes with a stem tkdiag and its CNC slots stay at the placeholders" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startPipeline(&sup, run_dir);

    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    const metrics = sup.snapshotProcessMetrics();
    // tkdiag neither disturbs the event path nor publishes anything but the
    // zero placeholders in its two slots (slot 0 diag_crashed_tile, slot 1
    // diag_sandbox_failures) until shared diagnostic state is wired in.
    try std.testing.expectEqual(event_count, metrics.audited);
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_crash_count);
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_sandbox_count);
    try assertNoCrash(&sup);
}
