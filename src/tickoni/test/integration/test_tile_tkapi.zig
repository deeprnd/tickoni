/// tkapi through the real supervisor and stem child, in the minimal fixture
/// (terminal tile) -> tkapi -> tkings -> tkaudt (+ metric). The ingest harness
/// stands in for the terminal tile on tkapi's input. Covers its lifecycle, the
/// wire shape it forwards and drops, the trace id it fills in, and its
/// reliable, never-dropping link to tkings.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const TkEvent = ingest.TkEvent;
const trace_id = c_abi.trace_id;

const source_tkrepl: u8 = 2; // TK_EVENT_SOURCE_TKREPL
const flag_replay: u8 = 1; // TK_EVENT_FLAG_REPLAY

fn tileScratch(sup: *Supervisor, name: []const u8) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), 0);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

fn tileIndex(sup: *const Supervisor, id: rt.tile.TileId) !usize {
    for (sup.topo.tiles, 0..) |t, i| {
        if (t.name.eql(id)) return i;
    }
    return error.TileNotFound;
}

/// A running minimal tkapi fixture fed `events`. Call `stop` before `deinit`.
const Run = struct {
    tmp: util.TmpDir,
    path_buf: [std.fs.max_path_bytes]u8 = undefined,
    workspace_buf: [16]u8 = undefined,
    sup: Supervisor,
    feed: Harness = .{},

    fn start(self: *Run, events: []const TkEvent) !void {
        self.tmp = util.tmpDir();
        errdefer self.tmp.cleanup();
        const run_dir = self.path_buf[0..try self.tmp.dir.realPath(std.testing.io, &self.path_buf)];
        self.sup = try Supervisor.initForTest(std.testing.allocator, topologies.minimalWithApiProcess());
        errdefer self.sup.deinit();
        self.feed = .{};
        try self.sup.startPaymentPipelineProcess(std.testing.io, .{
            .run_dir = run_dir,
            .event_count = events.len,
            .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
            .workspace_name = util.nextWorkspaceName(&self.workspace_buf),
            .metric_port = util.nextMetricPort(),
        });
        errdefer self.sup.stopProcess(std.testing.io) catch {};
        if (events.len != 0) try self.feed.start(std.testing.allocator, &self.sup, .{ .events = events }, 0);
    }

    /// Polls until tkapi has judged every fragment and tkaudt has committed
    /// `audited` records.
    fn awaitSettled(self: *Run, fragments: u64, audited: usize) !Supervisor.ProcessMetricSnapshot {
        const audit = try tileScratch(&self.sup, "tkaudt");
        var poll: u32 = 0;
        while (poll < 2000) : (poll += 1) {
            const m = self.sup.snapshotProcessMetrics();
            if (m.api_published + m.api_wire_invalid >= fragments and c_abi.tkaudit.recordCount(audit) >= audited) break;
            util.process.sleepNanos(5 * std.time.ns_per_ms);
        }
        return self.sup.snapshotProcessMetrics();
    }

    fn stop(self: *Run) void {
        self.feed.finish();
        self.sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    }

    fn deinit(self: *Run) void {
        self.sup.deinit();
        self.tmp.cleanup();
    }
};

fn paymentEvents(comptime n: usize) [n]TkEvent {
    const cfg = @import("tiles").PaymentPipelineConfig{ .event_count = n };
    var events: [n]TkEvent = undefined;
    for (&events, 0..) |*e, i| e.* = ingest.paymentEvent(cfg, i);
    return events;
}

test "tkapi_integration: child launches through __stem-run and halts cleanly" {
    if (@import("builtin").target.os.tag != .linux) return error.SkipZigTest;

    var run: Run = undefined;
    // Zero events is an idle source: the child stays alive for argv inspection
    // and must stop on the CNC HALT sent by stopProcess.
    try run.start(&.{});
    defer run.deinit();
    errdefer run.stop();

    const api_idx = try tileIndex(&run.sup, rt.tile_ids.tkapi);
    const pid = run.sup.monitor()[api_idx].pid orelse return error.ApiChildHasNoPid;
    var cmdline_path_buf: [64]u8 = undefined;
    const cmdline_path = try std.fmt.bufPrint(&cmdline_path_buf, "/proc/{d}/cmdline", .{pid});

    var found_stem = false;
    var found_tile = false;
    var poll: u32 = 0;
    while (poll < 400) : (poll += 1) {
        var file = std.Io.Dir.cwd().openFile(std.testing.io, cmdline_path, .{}) catch {
            util.process.sleepNanos(5 * std.time.ns_per_ms);
            continue;
        };
        var cmdline: [4096]u8 = undefined;
        const len = file.readPositionalAll(std.testing.io, &cmdline, 0) catch 0;
        file.close(std.testing.io);
        var args = std.mem.splitScalar(u8, cmdline[0..len], 0);
        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "__stem-run")) found_stem = true;
            if (std.mem.eql(u8, arg, "__tile-run")) found_tile = true;
        }
        if (found_stem or found_tile) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }
    try std.testing.expect(found_stem);
    try std.testing.expect(!found_tile);
    try std.testing.expectEqual(@as(u64, 0), run.sup.snapshotProcessMetrics().api_published);

    run.stop();
    try std.testing.expectEqual(rt.tile.TileState.stopped, run.sup.monitor()[api_idx].state);
}

test "tkapi_integration: user requests reach tkings in order; malformed ones are dropped and counted" {
    var events = paymentEvents(9);
    events[1].version += 1; // unknown wire version
    events[2].kind = 9; // unknown kind
    events[3].source = source_tkrepl; // replay never enters through the API
    events[4].source = source_tkrepl;
    events[4].flags = flag_replay;
    events[5].flags = flag_replay; // the replay bit, from the API
    events[6].idempotency_key = 0; // no idempotency key
    const valid = [_]usize{ 0, 7, 8 };

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, valid.len);
    try std.testing.expectEqual(@as(u64, valid.len), m.api_published);
    try std.testing.expectEqual(@as(u64, events.len - valid.len), m.api_wire_invalid);
    // tkings received exactly what tkapi forwarded, and framed all of it.
    try std.testing.expectEqual(@as(u64, valid.len), m.produced);
    try std.testing.expectEqual(@as(u64, 0), m.ingest_invalid);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, valid.len), c_abi.tkaudit.recordCount(audit));
    for (valid, 0..) |offset, i| {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSourceOffset(audit, i));
        // The producer's trace id is passed through unchanged.
        try std.testing.expectEqualSlices(u8, &events[offset].trace_id, &c_abi.tkaudit.recordTraceId(audit, i));
    }
}

test "tkapi_integration: a request without a trace id gets a random one, distinct per request" {
    var events = paymentEvents(5);
    const zero = trace_id.fromInt(0);
    events[0].trace_id = zero;
    events[1].trace_id = zero;
    events[3].trace_id = zero;
    events[4].trace_id = zero;

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);
    // tkings, which refuses an absent trace id, framed every one.
    try std.testing.expectEqual(@as(u64, 0), m.ingest_invalid);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));
    var ids: [events.len][trace_id.len]u8 = undefined;
    for (&ids, 0..) |*id, i| id.* = c_abi.tkaudit.recordTraceId(audit, i);
    // The one the producer supplied is kept.
    try std.testing.expectEqualSlices(u8, &events[2].trace_id, &ids[2]);
    for (ids, 0..) |id, i| {
        try std.testing.expect(!std.mem.eql(u8, &id, &zero));
        for (ids[i + 1 ..]) |other| try std.testing.expect(!std.mem.eql(u8, &id, &other));
    }
}

test "tkapi_integration: more requests than the link depth are back-pressured, never dropped" {
    // 1000 fragments through two 64-deep links: tkapi waits on tkings's
    // credits, the harness on tkapi's, and every request arrives once, in order.
    const n = 1000;
    const events = paymentEvents(n);

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(n, n);
    try std.testing.expectEqual(@as(u64, n), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);
    try std.testing.expectEqual(@as(u64, n), m.produced);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, n), c_abi.tkaudit.recordCount(audit));
    for (0..n) |i| {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSourceOffset(audit, i));
        try std.testing.expectEqualSlices(u8, &events[i].trace_id, &c_abi.tkaudit.recordTraceId(audit, i));
    }
}
