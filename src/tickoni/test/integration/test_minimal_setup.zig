/// Minimal 3-tile integration test: (harness) → tkings → tkaudt (+ metric observer).
/// The metric tile is required so Firedancer's fd_topo_fill_tile sets
/// tile_c->metrics to a non-NULL value for every tile.
/// Used to isolate the tkaudt fd_metrics_tl SIGSEGV by removing all
/// other pipeline tiles from the debugging surface.
const std = @import("std");
const builtin = @import("builtin");
const rt = @import("runtime");
const tile_ids = rt.tile_ids;
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");
const tiles = @import("tiles");

const mrs = tiles.model_request_source;
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;

const Supervisor = supervisor_mod.Supervisor;

test "minimal_setup_integration: tkings → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 3-tile topology: tkings → tkaudt + metric (observer only)
    const topo = topologies.minimalProcess();
    try std.testing.expectEqual(@as(usize, 3), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings(tile_ids.metric.slice(), topo.tiles[2].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
    }, .{});
    errdefer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

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
    var metrics = sup.snapshotProcessMetrics();
    while (poll < max_polls) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.audited >= event_count and metrics.produced >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} audited={d}\n", .{ metrics.produced, metrics.audited });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\n", .{ i, @tagName(h.state), h.pid });
    }

    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);

    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "minimal_setup_integration: tkgate → tkings → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 4-tile topology: (harness as terminal tile) → tkgate → tkings → tkaudt + metric
    const topo = topologies.minimalWithApiProcess();
    try std.testing.expectEqual(@as(usize, 4), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkgate.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[2].name.slice());
    try std.testing.expectEqualStrings(tile_ids.metric.slice(), topo.tiles[3].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&ws_buf),
        .metric_port = util.nextMetricPort(),
    }, .{});
    errdefer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    // One child process per tile, parented by the supervisor.
    try std.testing.expectEqual(@as(usize, 4), sup.monitor().len);
    const supervisor_pid = c_abi.sandbox.getpid();
    for (sup.monitor()) |h| {
        const child_id = h.pid orelse return error.MissingPid;
        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    var metrics = sup.snapshotProcessMetrics();
    var poll: u32 = 0;
    while (poll < 400) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();

    // Every event passed tkgate, then tkings, then reached the audit chain.
    try std.testing.expectEqual(event_count, metrics.api_published);
    try std.testing.expectEqual(@as(u64, 0), metrics.api_wire_invalid);
    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(event_count, metrics.audited);

    // Every tile, tkgate included, stops on its event count or the HALT.
    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "minimal_setup_integration: tkings → tknorm → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 4-tile topology: tkings → tknorm → tkaudt + metric (observer only)
    const topo = topologies.minimalWithNormProcess();
    try std.testing.expectEqual(@as(usize, 4), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tknorm.slice(), topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[2].name.slice());
    try std.testing.expectEqualStrings(tile_ids.metric.slice(), topo.tiles[3].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
        .verbose = true,
    }, .{});
    errdefer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    const supervisor_pid = c_abi.sandbox.getpid();

    // Verify exactly 4 child processes, parented by the supervisor
    try std.testing.expectEqual(@as(usize, 4), sup.monitor().len);
    var seen_pids: [4]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const child_id = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != child_id);
        seen_pids[i] = child_id;

        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for tknorm and tkaudt to finish processing.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    var metrics = sup.snapshotProcessMetrics();
    while (poll < max_polls) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.produced >= event_count and
            metrics.normalized >= event_count and
            metrics.audited >= event_count)
        {
            break;
        }
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} normalized={d} audited={d}\n", .{
        metrics.produced,
        metrics.normalized,
        metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\n", .{ i, @tagName(h.state), h.pid });
    }

    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);
    try std.testing.expectEqual(@as(u64, event_count), metrics.normalized);
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);

    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "minimal_setup_integration: tkings → tknorm → tkdedu → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 5-tile topology: tkings → tknorm → tkdedu → tkaudt + metric (observer only)
    const topo = topologies.minimalWithDeduProcess();
    try std.testing.expectEqual(@as(usize, 5), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tknorm.slice(), topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkdedu.slice(), topo.tiles[2].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[3].name.slice());
    try std.testing.expectEqualStrings(tile_ids.metric.slice(), topo.tiles[4].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
        .verbose = true,
    }, .{});
    errdefer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    const supervisor_pid = c_abi.sandbox.getpid();

    // Verify exactly 5 child processes, parented by the supervisor
    try std.testing.expectEqual(@as(usize, 5), sup.monitor().len);
    var seen_pids: [5]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const child_id = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != child_id);
        seen_pids[i] = child_id;

        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for tknorm, tkdedu and tkaudt to finish processing.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    var metrics = sup.snapshotProcessMetrics();
    while (poll < max_polls) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.produced >= event_count and
            metrics.normalized >= event_count and
            metrics.audited >= event_count)
        {
            break;
        }
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} normalized={d} deduplicated={d} audited={d}\n", .{
        metrics.produced,
        metrics.normalized,
        metrics.duplicates,
        metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\n", .{ i, @tagName(h.state), h.pid });
    }

    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);
    try std.testing.expectEqual(@as(u64, event_count), metrics.normalized);
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);

    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "minimal_setup_integration: tkings → tknorm → tkdedu → tkpoly → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal 6-tile topology: tkings → tknorm → tkdedu → tkpoly → tkaudt + metric (observer only)
    const topo = topologies.minimalWithPolyProcess();
    try std.testing.expectEqual(@as(usize, 6), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tknorm.slice(), topo.tiles[1].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkdedu.slice(), topo.tiles[2].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkpoly.slice(), topo.tiles[3].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[4].name.slice());
    try std.testing.expectEqualStrings(tile_ids.metric.slice(), topo.tiles[5].name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
        .verbose = true,
    }, .{});
    errdefer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    const supervisor_pid = c_abi.sandbox.getpid();

    // Verify exactly 6 child processes, parented by the supervisor
    try std.testing.expectEqual(@as(usize, 6), sup.monitor().len);
    var seen_pids: [6]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const child_id = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != child_id);
        seen_pids[i] = child_id;

        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for tknorm, tkdedu, tkpoly and tkaudt to finish processing.
    const max_polls: u32 = 400;
    var poll: u32 = 0;
    var metrics = sup.snapshotProcessMetrics();
    while (poll < max_polls) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.produced >= event_count and
            metrics.normalized >= event_count and
            metrics.audited >= event_count)
        {
            break;
        }
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} normalized={d} deduplicated={d} allowed={d} denied={d} audited={d}\n", .{
        metrics.produced,
        metrics.normalized,
        metrics.duplicates,
        metrics.allowed,
        metrics.denied,
        metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\n", .{ i, @tagName(h.state), h.pid });
    }

    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);
    try std.testing.expectEqual(@as(u64, event_count), metrics.normalized);
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);

    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

test "minimal_setup_integration: harness → tkgate → spine → tkdisp → tkagnt → tkmodl → tkaudt + metric observer" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    // Minimal agent topology: every agent request takes the spine (tkings →
    // tknorm → tkdedu → tkcase → tkpoly → tkaudt), and tkcase → tkdisp → tkagnt
    // → tkmodl → {tkaudt, tkagnt}, tkagnt → {tkaudt, tkdisp}, plus the metric
    // observer. The test harness publishes the requests on tkgate's input,
    // standing in for the terminal tile; tkgate feeds tkings.
    const topo = topologies.agentProcess(1);
    const names = [_]rt.tile.TileId{ tile_ids.tkings, tile_ids.tknorm, tile_ids.tkdedu, tile_ids.tkcase, tile_ids.tkpoly, tile_ids.tkaudt, tile_ids.tkdisp, tile_ids.tkagnt, tile_ids.tkmodl, tile_ids.metric, tile_ids.tkgate };
    try std.testing.expectEqual(names.len, topo.tiles.len);
    for (names, topo.tiles) |want, t| try std.testing.expectEqualStrings(want.slice(), t.name.slice());

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const port = util.nextMetricPort();
    const event_count: u64 = 8;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);

    // One fixture-mode instance serving the `low` tier, with its captured
    // responses.
    const source = mrs.ModelRequestSource{};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scratch = try a.alloc(u8, mrs.scratchBytes(source.shape) + 64);
    const contents = try a.alloc(supervisor_mod.model_instances.FixtureContent, source.shape.fixtures);
    for (contents, 0..) |*c, i| {
        const buf = try a.alloc(u8, mrs.scratchBytes(source.shape));
        const n = mrs.fillResponse(buf, .llm, i, source.shape);
        c.* = .{ .key = mrs.fixtureKey(i), .bytes = buf[0..n] };
    }
    const model_configs = [_]supervisor_mod.model_instances.InstanceConfig{
        .{ .kind_id = 0, .tier = .low, .config = mrs.fixtureConfig(.llm, source.shape, scratch), .contents = contents },
    };
    const run_config = supervisor_mod.ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = port,
        .model_configs = &model_configs,
        .dispatch_template = source,
        .agent_prompts = try mrs.prompts(source.shape, a),
    };
    try sup.startPaymentPipelineProcess(std.testing.io, run_config);
    errdefer sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    // The harness writes into the shared workspace, so it stops before the run.
    var harness: Harness = .{};
    try harness.start(std.testing.allocator, &sup, .{ .agent_requests = source }, event_count);
    errdefer harness.finish();

    const supervisor_pid = c_abi.sandbox.getpid();

    // Verify exactly one child process per tile, parented by the supervisor
    try std.testing.expectEqual(names.len, sup.monitor().len);
    var seen_pids: [names.len]std.process.Child.Id = undefined;
    for (sup.monitor(), 0..) |h, i| {
        const child_id = h.pid orelse return error.MissingPid;
        for (seen_pids[0..i]) |other| try std.testing.expect(other != child_id);
        seen_pids[i] = child_id;

        const ppid = try c_abi.os.parentPid(@intCast(c_abi.os.processDiagnosticPid(child_id)));
        try std.testing.expectEqual(supervisor_pid, ppid);
    }

    // Wait for the agent to deliver every terminal result. Per event: the
    // spine's policy decision, one tkmodl record and one agent record; plus the
    // case's creation and completion records from tkcase.
    const max_polls: u32 = 1200;
    var poll: u32 = 0;
    var metrics = sup.snapshotProcessMetrics();
    while (poll < max_polls) : (poll += 1) {
        metrics = sup.snapshotProcessMetrics();
        if (metrics.produced >= event_count and metrics.audited >= 3 * event_count + 2) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] metrics: produced={d} allowed={d} denied={d} audited={d} dispatched={d}\n", .{
        metrics.produced,
        metrics.allowed,
        metrics.denied,
        metrics.audited,
        metrics.agent_dispatched,
    });

    try std.testing.expectEqual(event_count, metrics.produced);
    try std.testing.expectEqual(@as(u64, 0), metrics.ingest_invalid);
    // `allowed` sums tkpoly's and tkmodl's: each request is allowed by both.
    try std.testing.expectEqual(2 * event_count, metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try std.testing.expectEqual(3 * event_count + 2, metrics.audited);
    try std.testing.expectEqual(event_count, metrics.agent_dispatched);
    // tkcase forwards each event to tkpoly and tkdisp (CNC slot 0).
    try std.testing.expectEqual(2 * event_count, metrics.forwarded);

    harness.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}
