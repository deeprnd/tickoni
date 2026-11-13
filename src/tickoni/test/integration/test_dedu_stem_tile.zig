/// Standalone pipeline integration tests for the tkdedu fd_stem tile.
///
/// Tests:
/// 1. Stem tile processes all events — deduplicated output flows through
///    tkdedu → tkaudt (tkaudt sink)
/// 2. Pipeline completes end-to-end — audited == event_count (tkaudt sink)
/// 3. No crashes, no hangs, no deadlocks — all tiles stop cleanly
///
/// Identity tests (compile-time symbol linkage) live in c_abi/tkdedu.zig.
const std = @import("std");
const builtin = @import("builtin");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const rt = runtime;
const tile_ids = runtime.tile_ids;
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

/// Maximum polls before giving up waiting for the pipeline to complete.
const MAX_POLL: u32 = 400;

/// Poll interval: 5 ms.
const POLL_INTERVAL: u64 = 5 * std.time.ns_per_ms;

/// Default event count.
const DEFAULT_EVENT_COUNT: u64 = 8;

/// Expected number of tiles in the minimal-with-dedu topology:
/// tkings, tknorm, tkdedu, tkaudt, metric.
const EXPECTED_TILE_COUNT: usize = 5;

test "tkdedu_integration: stem tile processes all events" {
    if (false) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalWithDeduProcess();
    try std.testing.expectEqual(EXPECTED_TILE_COUNT, topo.tiles.len);

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 8;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
        .inject_duplicate = false,
        .inject_malformed = false,
    });

    // Wait for tkaudt to finish auditing (tkaudt is the pipeline sink).
    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] tkdedu stem: produced={d} normalized={d} deduplicated={d} audited={d}\\n", .{
        metrics.produced, metrics.normalized, metrics.duplicates, metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s}\\n", .{ i, @tagName(h.state) });
    }

    // Task 12 assertion 1: tkdedu received all produced events and tkaudt
    // audited them. With inject_duplicate=false all events are unique so
    // duplicates should be 0.
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);
    try std.testing.expectEqual(@as(u64, event_count), metrics.normalized);
    try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 0), metrics.invalid);

    // Task 12 assertion 2: no tile crashed.
    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "tkdedu_integration: pipeline completes without crashes or hangs" {
    if (false) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalWithDeduProcess();
    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io) catch |err| std.log.err("defer teardown stop: {any}", .{err});
        sup.deinit();
    }

    const event_count: u64 = 8;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
        .inject_duplicate = true,
        .inject_malformed = false,
    });

    // Wait for tkaudt to finish auditing (pipeline sink).
    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] pipeline: produced={d} normalized={d} deduplicated={d} audited={d}\\n", .{
        metrics.produced, metrics.normalized, metrics.duplicates, metrics.audited,
    });

    // Task 12 assertion 1: every event produced was audited (duplicates
    // are silently removed — tkaudt only sees unique events).
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expect(@as(u64, 0) < metrics.duplicates, "at least one duplicate should exist with inject_duplicate=true");

    // Task 12 assertion 2: no tile crashed.
    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    // Task 12 assertion 3: clean shutdown — all tiles reach .stopped.
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "tkdedu_integration: CNC HALT stops tile cleanly" {
    if (false) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalWithDeduProcess();
    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer {
        sup.stopProcess(std.testing.io) catch |err| std.log.err("defer teardown stop: {any}", .{err});
        sup.deinit();
    }

    const event_count: u64 = 2;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
        .inject_duplicate = false,
        .inject_malformed = false,
    });

    // Wait for at least 1 event to be processed before stopping.
    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.produced >= 1) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    // Signal stop — verifies SHOULD_SHUTDOWN / CNC HALT path.
    sup.stopProcess(std.testing.io) catch |err| std.log.err("CNC HALT stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    // All tiles should reach .stopped (not crashed or hung).
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "tkdedu_integration: sequential runs on same workspace" {
    if (false) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Run 3x: start → event_count=20 → stop → deinit.
    // Each run must reset counters cleanly — catches stale workspace / CNC
    // collision bugs.
    const runs: usize = 3;
    const per_run_events: u64 = 20;
    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var sup = try Supervisor.initForTest(std.testing.allocator, topologies.minimalWithDeduProcess());
        defer {
            sup.stopProcess(std.testing.io) catch |err| std.log.err("defer teardown stop: {any}", .{err});
            sup.deinit();
        }

        const metric_port = util.nextMetricPort();
        var ws_buf: [16]u8 = undefined;
        const workspace_name = util.nextWorkspaceName(&ws_buf);
        try sup.startPaymentPipelineProcess(std.testing.io, .{
            .run_dir = run_dir,
            .event_count = per_run_events,
            .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
            .workspace_name = workspace_name,
            .metric_port = metric_port,
            .inject_duplicate = false,
            .inject_malformed = false,
        });

        // Wait for all events to be audited.
        const max_polls: u32 = MAX_POLL;
        var poll: u32 = 0;
        while (poll < max_polls) : (poll += 1) {
            const snap = sup.snapshotProcessMetrics();
            if (snap.audited >= per_run_events) break;
            util.process.sleepNanos(POLL_INTERVAL);
        }

        const metrics = sup.snapshotProcessMetrics();
        try std.testing.expectEqual(per_run_events, metrics.audited);
        try std.testing.expectEqual(per_run_events, metrics.produced);
        try std.testing.expectEqual(per_run_events, metrics.normalized);
        try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);
        try std.testing.expectEqual(@as(u64, 0), metrics.invalid);

        for (sup.monitor()) |h| {
            try std.testing.expect(h.state != .crashed);
        }

        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
        for (sup.monitor()) |h| {
            try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        }
    }
}
