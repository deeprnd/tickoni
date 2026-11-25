/// tkings through the real supervisor and stem child: its lifecycle, and its
/// framing of what arrives on its input link (its only source).
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");

// That the supervisor launches tkings through "__stem-run" is asserted in
// supervisor.zig's tileArgv tests, on every platform.
test "tkings_integration: idle child stays running and halts cleanly" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try supervisor_mod.Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var workspace_buf: [16]u8 = undefined;
    // Zero is an idle source, so the child remains alive until it must stop
    // on the CNC HALT sent by stopProcess.
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = 0,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    }, .{});

    var ingest_idx: usize = 0;
    while (!sup.topo.tiles[ingest_idx].name.eql(rt.tile_ids.tkings)) : (ingest_idx += 1) {}
    _ = sup.monitor()[ingest_idx].pid orelse return error.IngestChildHasNoPid;
    try std.testing.expectEqual(rt.tile.TileState.running, sup.monitor()[ingest_idx].state);
    try std.testing.expectEqual(@as(u64, 0), sup.snapshotProcessMetrics().produced);
    feed.finish();
    try sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[ingest_idx].state);
}

fn tileScratch(sup: *supervisor_mod.Supervisor, name: []const u8) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), 0);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

test "tkings_integration: malformed envelopes are dropped and counted, canonical ones framed in arrival order" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    const cfg = @import("tiles").PaymentPipelineConfig{ .event_count = 8 };
    var events: [7]ingest.TkEvent = undefined;
    for (&events, 0..) |*e, i| e.* = ingest.paymentEvent(cfg, i);
    events[0].trace_id = c_abi.trace_id.fromInt(11);
    events[1].version += 1; // unknown wire version
    events[2].trace_id = c_abi.trace_id.fromInt(12);
    // A producer cannot pre-decide what later tiles own: tkings resets it.
    events[2].source_offset = 99;
    events[2].case_id = 5;
    events[2].decision = 1;
    events[2].event_hash = 0xdead;
    events[3].trace_id = c_abi.trace_id.fromInt(0); // no trace
    events[4].flags = 1; // the replay bit, from tkgate
    events[5].kind = 9; // unknown kind
    events[6].trace_id = c_abi.trace_id.fromInt(13);
    const valid = [_]u64{ 11, 12, 13 };

    var sup = try supervisor_mod.Supervisor.initForTest(std.testing.allocator, topologies.minimalProcess());
    defer sup.deinit();
    var workspace_buf: [16]u8 = undefined;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = events.len,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    });
    var feed: Harness = .{};
    try feed.start(std.testing.allocator, &sup, .{ .events = &events }, 0);
    defer {
        feed.finish();
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    const audit = try tileScratch(&sup, "tkaudt");
    var poll: u32 = 0;
    while (poll < 400) : (poll += 1) {
        const m = sup.snapshotProcessMetrics();
        if (m.produced + m.ingest_invalid >= events.len and c_abi.tkaudit.recordCount(audit) >= valid.len) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    const m = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, valid.len), m.produced);
    try std.testing.expectEqual(@as(u64, events.len - valid.len), m.ingest_invalid);

    // Only the canonical events reached tkaudt, numbered by tkings in arrival
    // order, each under its producer's trace, with nothing pre-decided.
    try std.testing.expectEqual(@as(usize, valid.len), c_abi.tkaudit.recordCount(audit));
    for (valid, 0..) |trace, i| {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSourceOffset(audit, i));
        try std.testing.expectEqual(@as(u128, trace), c_abi.trace_id.toInt(c_abi.tkaudit.recordTraceId(audit, i)));
        try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordCaseId(audit, i));
        try std.testing.expectEqual(@as(u8, 0), c_abi.tkaudit.recordOutcome(audit, i));
        try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordSourceEventHash(audit, i));
    }
}
