/// Linux-strict process topology proof: exact parent-PID validation through
/// /proc, exact sibling stop semantics after observer crashes, and the tighter
/// stale-heartbeat timing envelope that Linux can support.
/// Requires Linux — /proc filesystem access is not available on other OSes.
const std = @import("std");

comptime {
    if (@import("builtin").target.os.tag != .linux)
        @compileError("test_process_topology_linux requires Linux (/proc access)");
}
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;

fn parentPidOf(io: std.Io, pid: std.process.Child.Id) !c_int {
    var path_buf: [64]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/status", .{pid});
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    const n = try file.readPositionalAll(io, &buf, 0);
    const contents = buf[0..n];

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PPid:")) {
            const value = std.mem.trim(u8, line["PPid:".len..], " \t");
            return std.fmt.parseInt(c_int, value, 10);
        }
    }
    return error.PPidNotFound;
}

test "process_topology_linux: every tile is a distinct OS process parented by the supervisor" {
    if (true) return error.SkipZigTest;
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

    const supervisor_pid = c_abi.sandbox.getpid();

    var seen_pids: [8]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const pid = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != pid);
        seen_pids[i] = pid;

        const ppid = try parentPidOf(std.testing.io, pid);
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(event_count, sup.snapshotProcessMetrics().audited);

    sup.stopProcess(std.testing.io);
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_linux: supervisor marks a truly stuck tile stale within the tight Linux heartbeat window" {
    if (true) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 16,
        .heartbeat_interval_ns = 10 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 60 * std.time.ns_per_ms,
        .stuck_tile_idx = 0,
        .stuck_after_messages = 0,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 200;
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
    try std.testing.expectEqual(rt.tile.TileState.stale, sup.monitor()[0].state);
    try std.testing.expectEqual(rt.tile.CrashReason.stale, sup.monitor()[0].crashed_because);
    for (sup.monitor(), 0..) |h, i| {
        if (i == 0) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "process_topology_linux: SIGKILL on one tile is reported by identity without corrupting siblings" {
    if (true) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const tkrepl_idx = 5;
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());
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

    for (sup.monitor(), 0..) |h, i| {
        if (i == tkrepl_idx) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
}

test "process_topology_linux: a self-exiting tile is reported crashed via exit_code, not signal" {
    if (true) return error.SkipZigTest;
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

    const event_count: u64 = 16;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .crash_after_heartbeats = crash_after_heartbeats,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[tkrepl_idx].id.slice());

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

    for (sup.monitor(), 0..) |h, i| {
        if (i == tkrepl_idx) continue;
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);
}
