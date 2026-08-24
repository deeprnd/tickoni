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

test "process_topology_integration: every tile is a distinct OS process parented by the supervisor" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 8;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    var seen_pids: [8]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const pid = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != pid);
        seen_pids[i] = pid;
    }

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_integration: supervisor marks a truly stuck tile stale while blocked consumers keep heartbeating" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

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

    const max_polls: u32 = 600;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[0].state == rt.tile.TileState.stale) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    try std.testing.expect(sup.monitor()[0].isAlive());

    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expect(h.state != rt.tile.TileState.stale);
    }

    sup.stopProcess(std.testing.io);
    // After stopProcess, stale tiles are treated as cleanly stopped rather
    // than crashed — the stale classification happened before shutdown, and
    // the tile's crash/termination during stopProcess is a consequence of the
    // shutdown sequence, not a real crash.
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_integration: SIGKILL on one tile is reported by identity without corrupting siblings" {
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

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_s,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const tkrepl_pid = sup.monitor()[tkrepl_idx].pid orelse return error.MissingPid;
    try std.posix.kill(tkrepl_pid, std.posix.SIG.KILL);

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);

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
}

test "process_topology_integration: a self-exiting tile is reported crashed via exit_code, not signal" {
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

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .crash_after_heartbeats = crash_after_heartbeats,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_s,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const metrics = sup.snapshotProcessMetrics();

    sup.stopProcess(std.testing.io);

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
}

test "process_topology_integration: process mode refuses to start a heap_dev-backed channel" {
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

    try std.testing.expectError(error.ProcessModeRequiresTangoShm, sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    }));
    for (sup.monitor()) |h| try std.testing.expect(h.pid == null);
}

test "process_topology_integration: process mode refuses to start with a missing workspace name" {
    const base = topologies.paymentPipelineProcess();
    var channels: [4]rt.topology.Channel = undefined;
    @memcpy(&channels, base.channels[0..4]);
    channels[0].workspace_name = .{};
    const topo = rt.topology.Topology{ .tiles = base.tiles, .channels = &channels };

    // Supervisor.init() now runs topo.validate()'s structural checks (see
    // Supervisor.init()'s doc comment), so a missing workspace name on a
    // tango_shm channel fails closed here rather than needing a tile to
    // reach startPaymentPipelineProcess first.
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, Supervisor.init(std.testing.allocator, topo));
}
