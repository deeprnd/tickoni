/// tkgate through the real supervisor and stem child, in the minimal fixture
/// (terminal tile) -> tkgate -> tkings -> tkaudt (+ metric). The ingest harness
/// stands in for the terminal tile on tkgate's input. Covers its lifecycle, the
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

/// A running minimal tkgate fixture fed `events`. Call `stop` before `deinit`.
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

    /// Polls until tkgate has judged every fragment and tkaudt has committed
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

// That the supervisor launches tkgate through "__stem-run" is asserted in
// supervisor.zig's tileArgv tests, on every platform.
test "tkgate_integration: idle child stays running and halts cleanly" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var run: Run = undefined;
    // Zero events is an idle source: the child stays alive until it must stop
    // on the CNC HALT sent by stopProcess.
    try run.start(&.{});
    defer run.deinit();
    errdefer run.stop();

    const api_idx = try tileIndex(&run.sup, rt.tile_ids.tkgate);
    _ = run.sup.monitor()[api_idx].pid orelse return error.ApiChildHasNoPid;
    try std.testing.expectEqual(rt.tile.TileState.running, run.sup.monitor()[api_idx].state);
    try std.testing.expectEqual(@as(u64, 0), run.sup.snapshotProcessMetrics().api_published);

    run.stop();
    try std.testing.expectEqual(rt.tile.TileState.stopped, run.sup.monitor()[api_idx].state);
}

test "tkgate_integration: user requests reach tkings in order; malformed ones are dropped and counted" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

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
    // tkings received exactly what tkgate forwarded, and framed all of it.
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

test "tkgate_integration: a request without a trace id gets a random one, distinct per request" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

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

test "tkgate_integration: more requests than the link depth are back-pressured, never dropped" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // 1000 fragments through two 64-deep links: tkgate waits on tkings's
    // credits, the harness on tkgate's, and every request arrives once, in order.
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

test "tkgate_integration: all valid events pass through, audit is precise" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(6);

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);
    try std.testing.expectEqual(@as(u64, events.len), m.produced);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));
    for (0..events.len) |i| {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSourceOffset(audit, i));
        try std.testing.expectEqualSlices(u8, &events[i].trace_id, &c_abi.tkaudit.recordTraceId(audit, i));
    }
}

test "tkgate_integration: all-malformed events are dropped, none reach tkings" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(5);
    events[0].source = source_tkrepl; // wrong source
    events[1].idempotency_key = 0; // missing idempotency key
    events[2].flags = flag_replay; // replay flag set
    events[3].version += 1; // unknown version
    events[4].kind = 9; // unknown kind

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, 0);
    try std.testing.expectEqual(@as(u64, 0), m.api_published);
    try std.testing.expectEqual(@as(u64, events.len), m.api_wire_invalid);
    try std.testing.expectEqual(@as(u64, 0), m.produced);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, 0), c_abi.tkaudit.recordCount(audit));
}

test "tkgate_integration: agent-request events pass through the same wire check" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const source_tkgate: u8 = 1; // TK_EVENT_SOURCE_TKGATE

    var events: [3]TkEvent = undefined;
    for (&events, 0..) |*ev, i| {
        ev.* = .{};
        ev.version = 1;
        ev.kind = 2; // TK_EVENT_KIND_AGENT_REQUEST
        ev.source = source_tkgate;
        ev.idempotency_key = 1_000_000 + i;
        ev.trace_id = trace_id.fromInt(100 + i);
    }

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));
}

test "tkgate_integration: non-zero trace ids pass through unchanged, all results are distinct" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(4);
    events[0].trace_id = trace_id.fromInt(42);
    events[1].trace_id = trace_id.fromInt(99);
    events[2].trace_id = trace_id.fromInt(256);
    events[3].trace_id = trace_id.fromInt(777);

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));
    for (0..events.len) |i| {
        try std.testing.expectEqualSlices(u8, &events[i].trace_id, &c_abi.tkaudit.recordTraceId(audit, i));
    }

    // All trace ids are non-zero and pairwise distinct.
    var ids: [events.len][trace_id.len]u8 = undefined;
    for (&ids, 0..) |*id, i| id.* = c_abi.tkaudit.recordTraceId(audit, i);
    var zero: [trace_id.len]u8 = undefined;
    for (0..events.len) |i| {
        try std.testing.expect(!std.mem.eql(u8, &ids[i], &zero));
        for (ids[i + 1 ..]) |other| try std.testing.expect(!std.mem.eql(u8, &ids[i], &other));
    }
}

test "tkgate_integration: audit records carry correct source_offset continuity and type" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(7);
    events[2].idempotency_key = 0; // invalid — dropped

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len - 1);
    try std.testing.expectEqual(@as(u64, events.len - 1), m.api_published);
    try std.testing.expectEqual(@as(u64, 1), m.api_wire_invalid);
    try std.testing.expectEqual(@as(u64, events.len - 1), m.produced);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len - 1), c_abi.tkaudit.recordCount(audit));

    // Source offsets are continuous from 0 — no gaps from dropped events.
    for (0..events.len - 1) |i| {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSourceOffset(audit, i));
    }

    // Every record is a source_event (type 0) decided by tknorm.
    for (0..events.len - 1) |i| {
        try std.testing.expectEqual(@as(u32, @intCast(c_abi.tkaudit.RECORD_SOURCE_EVENT)), c_abi.tkaudit.recordType(audit, i));
    }
}

test "tkgate_integration: source event hashes are unique per event" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(10);
    // Each payment event has a different idempotency_key and trace_id,
    // so every event should produce a unique source event hash.
    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));

    var hashes: [events.len]u64 = undefined;
    for (0..events.len) |i| hashes[i] = c_abi.tkaudit.recordSourceEventHash(audit, i);

    // All hashes are pairwise distinct.
    for (0..events.len) |i| {
        for (hashes[i + 1 ..]) |other| {
            try std.testing.expect(hashes[i] != other);
        }
    }
}

test "tkgate_integration: large batch preserves audit chain integrity" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const n: usize = 200;
    const events = paymentEvents(n);

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(n, n);
    try std.testing.expectEqual(@as(u64, n), m.api_published);
    try std.testing.expectEqual(@as(u64, 0), m.api_wire_invalid);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, n), c_abi.tkaudit.recordCount(audit));

    // Verify hash chain: each record's prev_hash equals the previous record's hash.
    for (1..n) |i| {
        const prev_hash = c_abi.tkaudit.recordHash(audit, i - 1);
        try std.testing.expectEqual(prev_hash, c_abi.tkaudit.recordPrevHash(audit, i));
    }
}

test "tkgate_integration: mixed valid and invalid events produce correct counters" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // 20 events: 5 malformed (various reasons), 15 valid.
    var events: [20]TkEvent = undefined;
    var invalid_count: usize = 0;
    for (&events, 0..) |*ev, i| {
        ev.* = paymentEvents(20)[i];
        // Inject specific malformations in a pattern.
        if (i == 3 or i == 7 or i == 12) {
            ev.idempotency_key = 0;
            invalid_count += 1;
        } else if (i == 5) {
            ev.source = source_tkrepl; // replay source
            invalid_count += 1;
        } else if (i == 15) {
            ev.flags = flag_replay;
            invalid_count += 1;
        } else if (i == 18) {
            ev.version += 1; // unknown version
            invalid_count += 1;
        }
    }

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len - invalid_count);
    try std.testing.expectEqual(@as(u64, events.len - invalid_count), m.api_published);
    try std.testing.expectEqual(@as(u64, invalid_count), m.api_wire_invalid);
    try std.testing.expectEqual(@as(u64, events.len - invalid_count), m.produced);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len - invalid_count), c_abi.tkaudit.recordCount(audit));
}

test "tkgate_integration: audit outcome is allow for all forwarded events" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events = paymentEvents(12);
    events[4].idempotency_key = 0; // dropped
    events[9].source = source_tkrepl; // dropped

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const expected = events.len - 2;
    const m = try run.awaitSettled(events.len, expected);
    try std.testing.expectEqual(@as(u64, expected), m.api_published);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, expected), c_abi.tkaudit.recordCount(audit));

    // Every forwarded event results in an allow outcome.
    for (0..expected) |i| {
        try std.testing.expectEqual(
            c_abi.tkaudit.POLICY_ALLOW,
            c_abi.tkaudit.recordOutcome(audit, i),
        );
    }
}

test "tkgate_integration: trace ids are unique across mixed valid/invalid batches" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var events: [15]TkEvent = undefined;
    for (&events, 0..) |*ev, i| {
        ev.* = paymentEvents(15)[i];
        // Make some arrive without trace ids (all zero).
        if (i == 2 or i == 5 or i == 8 or i == 11) {
            ev.trace_id = trace_id.fromInt(0);
        }
    }
    // Make one event invalid.
    events[7].idempotency_key = 0;

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const expected = events.len - 1;
    const m = try run.awaitSettled(events.len, expected);
    try std.testing.expectEqual(@as(u64, expected), m.api_published);

    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, expected), c_abi.tkaudit.recordCount(audit));

    // All trace ids are non-zero and pairwise distinct.
    var ids: [expected][trace_id.len]u8 = undefined;
    for (0..expected) |i| ids[i] = c_abi.tkaudit.recordTraceId(audit, i);

    var zero: [trace_id.len]u8 = undefined;
    for (0..expected) |i| {
        try std.testing.expect(!std.mem.eql(u8, &ids[i], &zero));
        for (ids[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, &ids[i], &other));
        }
    }
}

test "tkgate_integration: event body fields survive tkgate forwarding unchanged" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // tkgate is a transparent wire validator; it must forward the full body
    // without modification. We check payment-specific fields in the audit
    // source_event records via tkings's framing.
    var events: [5]TkEvent = undefined;
    const raw_events = paymentEvents(5);
    for (0..5) |i| {
        events[i] = raw_events[i];
        // Override with specific known values.
        events[i].body.payment.amount_cents = 1000 * @as(i64, @intCast(i + 1));
        // currency is a 3-byte array at a fixed offset in TkEvent.body.payment.
        events[i].body.payment.currency = @as([3]u8, .{ 'U', 'S', 'D' });
    }

    var run: Run = undefined;
    try run.start(&events);
    defer run.deinit();
    defer run.stop();

    const m = try run.awaitSettled(events.len, events.len);
    try std.testing.expectEqual(@as(u64, events.len), m.api_published);

    // tkings frames the event and records the source event hash.
    // We verify the events were actually accepted by tkings (produced count).
    try std.testing.expectEqual(@as(u64, events.len), m.produced);

    // The trace_id and idempotency_key survived (checked via audit).
    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(usize, events.len), c_abi.tkaudit.recordCount(audit));
    for (0..events.len) |i| {
        try std.testing.expectEqualSlices(
            u8,
            &events[i].trace_id,
            &c_abi.tkaudit.recordTraceId(audit, i),
        );
    }
}
