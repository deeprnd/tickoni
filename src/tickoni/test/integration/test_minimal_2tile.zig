/// Minimal 3-tile integration test: tkings → tkaudt (+ metric observer).
/// The metric tile is required so Firedancer's fd_topo_fill_tile sets
/// tile_c->metrics to a non-NULL value for every tile.
/// Used to isolate the tkaudt fd_metrics_tl SIGSEGV by removing all
/// other pipeline tiles from the debugging surface.
const std = @import("std");
const builtin = @import("builtin");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

test "minimal_3tile_integration: tkings → tkaudt + metric observer" {
    if (false) return error.SkipZigTest;
    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 3-tile topology: tkings → tkaudt + metric (observer only)
    const topo = topologies.minimalProcess();
    try std.testing.expectEqual(@as(usize, 3), topo.tiles.len);
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings("metric", topo.tiles[2].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
    });

    const supervisor_pid = c_abi.sandbox.getpid();

    // Verify exactly 3 child processes, parented by the supervisor
    try std.testing.expectEqual(@as(usize, 3), sup.monitor().len);
    var seen_pids: [3]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const child_id = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != child_id);
        seen_pids[i] = child_id;

        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for tkaudt to finish auditing
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} audited={d}\\n", .{ metrics.produced, metrics.audited });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\\n", .{ i, @tagName(h.state), h.pid });
    }

    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);

    sup.stopProcess(std.testing.io) catch {};
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}
