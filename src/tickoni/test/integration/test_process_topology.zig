/// v2.14.S1 M6 portable process topology proof: real child-process
/// separation, crash attribution by tile identity, stale classification, and
/// the process-mode fail-closed configuration checks that do not depend on
/// Linux-only /proc or affinity semantics.
const std = @import("std");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

fn logStep(tag: []const u8) void {
    std.Io.File.writeStreamingAll(std.Io.File.stderr(), std.testing.io, tag) catch {};
    std.Io.File.writeStreamingAll(std.Io.File.stderr(), std.testing.io, "\n") catch {};
}

test "process_topology_integration: every tile is a distinct OS process parented by the supervisor" {
    logStep("[P1] START tile_isolation");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    logStep("[P1] before startPaymentPipelineProcess");
    const event_count: u64 = 8;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    logStep("[P1] after startPaymentPipelineProcess");

    var seen_pids: [8]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const pid = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != pid);
        seen_pids[i] = pid;
    }
    logStep("[P1] pids collected, entering poll loop");

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    logStep("[P1] poll loop done, stopping");
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);
    logStep("[P1] stopProcess returned");
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
    logStep("[P1] END tile_isolation");
}

test "process_topology_integration: supervisor marks a truly stuck tile stale while blocked consumers keep heartbeating" {
    logStep("[P2] START stale_detection");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    logStep("[P2] before startPaymentPipelineProcess (stuck test)");
    // CI macOS runners show materially higher scheduling jitter than local
    // Linux, so this lane needs a real heartbeat window rather than a
    // near-zero threshold. The contract under test is topology-health
    // classification (only the intentionally frozen upstream tile goes stale),
    // not sub-100ms reaction time.
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 16,
        .heartbeat_interval_ns = 50 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 2 * std.time.ns_per_s,
        .stuck_tile_idx = 0,
        .stuck_after_messages = 0,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    logStep("[P2] after startPaymentPipelineProcess (stuck test)");

    const max_polls: u32 = 600;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[0].state == rt.tile.TileState.stale) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[P2] poll loop done, tile[0].state = {s}", .{@tagName(sup.monitor()[0].state)}) catch "<fmt>";
        logStep(msg);
    }
    {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[P2] tile[0].crashed_because = {s}", .{@tagName(sup.monitor()[0].crashed_because)}) catch "<fmt>";
        logStep(msg);
    }

    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    try std.testing.expect(sup.monitor()[0].isAlive());

    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expect(h.state != rt.tile.TileState.stale);
    }

    logStep("[P2] calling stopProcess (stuck test)");
    sup.stopProcess(std.testing.io);
    logStep("[P2] stopProcess returned (stuck test)");
    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
    logStep("[P2] END stale_detection");
}

test "process_topology_integration: SIGKILL on one tile is reported by identity without corrupting siblings" {
    logStep("[P3] START sigkill_identity");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const tkrepl_idx = 5;
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());

    logStep("[P3] before startPaymentPipelineProcess (sigkill test)");
    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_s,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    logStep("[P3] after startPaymentPipelineProcess (sigkill test)");

    const tkrepl_pid = sup.monitor()[tkrepl_idx].pid orelse return error.MissingPid;
    var pid_buf: [128]u8 = undefined;
    logStep(std.fmt.bufPrint(&pid_buf, "[P3] killing tkrepl pid {d}", .{tkrepl_pid}) catch "<fmt>");
    try std.posix.kill(tkrepl_pid, std.posix.SIG.KILL);

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    logStep("[P3] poll loop done, stopping");
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);
    logStep("[P3] stopProcess returned (sigkill test)");

    try std.testing.expectEqual(rt.tile.TileState.crashed, sup.monitor()[tkrepl_idx].state);
    try std.testing.expectEqual(rt.tile.CrashReason.signal, sup.monitor()[tkrepl_idx].crashed_because);

    var signal_crash_count: usize = 0;
    for (sup.monitor(), 0..) |h, i| {
        if (h.crashed_because == .signal) signal_crash_count += 1;
        if (i == tkrepl_idx) continue;
        try std.testing.expect(h.state != .crashed);
        try std.testing.expect(h.crashed_because != .signal);
        try std.testing.expect(h.crashed_because != .exit_code);
    }
    try std.testing.expectEqual(@as(usize, 1), signal_crash_count);
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
    logStep("[P3] END sigkill_identity");
}

test "process_topology_integration: a self-exiting tile is reported crashed via exit_code, not signal" {
    logStep("[P4] START self_exit_identity");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const tkrepl_idx = 5;
    var crash_after_heartbeats = std.mem.zeroes([8]u32);
    crash_after_heartbeats[tkrepl_idx] = 1;
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());

    logStep("[P4] before startPaymentPipelineProcess (self-exit test)");
    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .crash_after_heartbeats = crash_after_heartbeats,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_s,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    logStep("[P4] after startPaymentPipelineProcess (self-exit test)");

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    logStep("[P4] poll loop done, stopping");
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);
    logStep("[P4] stopProcess returned (self-exit test)");

    try std.testing.expectEqual(rt.tile.TileState.crashed, sup.monitor()[tkrepl_idx].state);
    try std.testing.expectEqual(rt.tile.CrashReason.exit_code, sup.monitor()[tkrepl_idx].crashed_because);
    try std.testing.expectEqual(@as(u8, 1), sup.monitor()[tkrepl_idx].exit_code);

    var exit_crash_count: usize = 0;
    for (sup.monitor(), 0..) |h, i| {
        if (h.crashed_because == .exit_code) exit_crash_count += 1;
        if (i == tkrepl_idx) continue;
        try std.testing.expect(h.state != .crashed);
        try std.testing.expect(h.crashed_because != .signal);
        try std.testing.expect(h.crashed_because != .exit_code);
    }
    try std.testing.expectEqual(@as(usize, 1), exit_crash_count);
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
    logStep("[P4] END self_exit_identity");
}

test "process_topology_integration: process mode refuses to start a heap_dev-backed channel" {
    logStep("[P5] START heap_dev_reject");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Same shape as paymentPipelineProcess() but the first channel is left
    // at its heap_dev default instead of being declared tango_shm.
    const base = topologies.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].backing = .heap_dev;
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    logStep("[P5] before startPaymentPipelineProcess (should fail)");
    try std.testing.expectError(error.ProcessModeRequiresTangoShm, sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    }));
    logStep("[P5] startPaymentPipelineProcess returned (should be error)");
    for (sup.monitor()) |h| try std.testing.expect(h.pid == null);
    logStep("[P5] END heap_dev_reject");
}

test "process_topology_integration: process mode refuses to start with a missing workspace name" {
    logStep("[P6] START missing_workspace");
    const base = topologies.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].workspace_name = .{};
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    logStep("[P6] before Supervisor.init (should fail)");
    // Supervisor.init() now runs topo.validate()'s structural checks (see
    // Supervisor.init()'s doc comment), so a missing workspace name on a
    // tango_shm channel fails closed here rather than needing a tile to
    // reach startPaymentPipelineProcess first.
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, Supervisor.init(std.testing.allocator, topo));
    logStep("[P6] END missing_workspace");
}
