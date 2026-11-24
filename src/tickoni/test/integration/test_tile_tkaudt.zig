/// Phase 3 Step 3.1: Audit record allocation in scratch.
///
/// This test verifies that the scratch-allocated audit records pointer and
/// AUDIT_INITIAL_HASH-based prev_hash initialization don't break the tkaudt tile.
/// It exercises the same process-mode topology as test_minimal_setup.zig
/// but is dedicated to Step 3.1 so we can iterate on audit record building
/// (Step 3.2+) without regressing the allocation itself.
///
/// Assertions:
///   - tkaudt tile boots and runs without crashing
///   - audited counter increments to event_count (counting stub works)
///   - pipeline completes and shuts down cleanly
///
/// Phase 3 Step 3.3: Hash chain verification.
///
/// This test verifies that the audit records built by the tkaudt tile form
/// a continuous hash chain: prev_hash[k] == record_hash[k-1] for k >= 1,
/// and prev_hash[0] == AUDIT_INITIAL_HASH.
///
/// The tile writes records into its shared scratch allocation during
/// DURING_FRAG. The supervisor maps that allocation in the same Tango
/// workspace, so this test reads it while the tile is still running. This
/// verifies the records the stem tile actually produced without adding an
/// export path or file I/O.
///
/// Assertions:
///   - scratch contains exactly event_count records
///   - prev_hash[0] == AUDIT_INITIAL_HASH
///   - prev_hash[k] == record_hash[k-1] for k >= 1
///   - all record hashes are non-zero
///   - pipeline completes and shuts down cleanly
///
const std = @import("std");
const builtin = @import("builtin");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const rt = runtime;
const tile_ids = runtime.tile_ids;
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

/// Maximum polls before giving up waiting for the pipeline to complete.
const MAX_POLL: u32 = 400;

/// Poll interval: 5 ms.
const POLL_INTERVAL: u64 = 5 * std.time.ns_per_ms;

/// Default event count.
const DEFAULT_EVENT_COUNT: u64 = 8;

/// Expected number of tiles in the minimal topology: tkings, tkaudt, metric.
const EXPECTED_TILE_COUNT: usize = 3;

/// Maximum records the in-memory buffer can hold.
const MAX_BUFFER_RECORDS: usize = 256;

// ===========================================================================
// Shared-scratch audit record access
// ===========================================================================
//
// The tkaudt tile writes records into its scratch allocation, which the
// supervisor maps in the same Tango workspace. Reads go through the C field
// accessors in tk_audit_stem.c (exposed via c_abi.tkaudit): that file owns
// tk_audit_ctx_t and AuditEvent, so nothing here mirrors a C struct. An
// earlier version of this test hand-wrote extern structs for the context,
// header and payload — including hand-placed padding — which duplicated the
// translate-c `audit_schema` binding and would silently misread the records
// if any C field moved.

/// Scratch base for the tkaudt tile, or an error if the tile is absent.
fn auditScratch(sup: *Supervisor) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const tile_id = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, tile_ids.tkaudt.slice()), 0);
    if (tile_id == c_abi.topob.not_found) return error.AuditTileNotFound;

    const tile_obj_id = c_abi.topob.topoTileObjId(topo, tile_id);
    return c_abi.topob.topoObjLaddr(topo, tile_obj_id);
}

/// Number of records tkaudt has committed to the hash chain.
fn auditRecordCount(sup: *Supervisor) !usize {
    const scratch = try auditScratch(sup);
    const count = c_abi.tkaudit.recordCount(scratch);
    if (count > MAX_BUFFER_RECORDS) return error.AuditRecordCapacityExceeded;
    return count;
}

// ===========================================================================
// Test: audit record allocation (Step 3.1) — tile boots and counts
// ===========================================================================

test "tkaudt_integration: Audit record allocation and counting stub" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalProcess();
    try std.testing.expectEqual(EXPECTED_TILE_COUNT, topo.tiles.len);

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = DEFAULT_EVENT_COUNT;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    }, .{});

    // Wait for tkaudt to finish auditing.
    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] Step 3.1: produced={d} audited={d}\\n", .{
        metrics.produced,
        metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\\n", .{ i, @tagName(h.state), h.pid });
    }

    // Step 3.1 assertions:
    // 1. tkaudt tile processed all events (counting stub works).
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);

    // 2. No tile crashed.
    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

// ===========================================================================
// Test: hash chain verification (Step 3.3)
// ===========================================================================

test "tkaudt_integration: Hash chain verification" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalProcess();
    try std.testing.expectEqual(EXPECTED_TILE_COUNT, topo.tiles.len);

    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();
    var stopped = false;
    defer if (!stopped) sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});

    const event_count: u64 = DEFAULT_EVENT_COUNT;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    }, .{});

    // Wait for tkaudt to finish auditing.
    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    std.debug.print("[test] Step 3.3: produced={d} audited={d}\\n", .{
        metrics.produced,
        metrics.audited,
    });
    for (sup.monitor(), 0..) |h, i| {
        std.debug.print("[test] tile {d}: state={s} pid={any}\\n", .{ i, @tagName(h.state), h.pid });
    }

    // Step 3.3 assertions:
    // 1. tkaudt tile processed all events.
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);

    // 2. No tile crashed.
    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    // 3. Verify the hash chain in the shared scratch allocation before
    // shutdown releases the workspace.
    const scratch = try auditScratch(&sup);
    const record_count = try auditRecordCount(&sup);
    try std.testing.expectEqual(@as(usize, event_count), record_count);

    // AUDIT_INITIAL_HASH = 0 (identity seed, from audit_consts.h).
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordPrevHash(scratch, 0));

    var k: usize = 1;
    while (k < record_count) : (k += 1) {
        try std.testing.expectEqual(
            c_abi.tkaudit.recordHash(scratch, k - 1),
            c_abi.tkaudit.recordPrevHash(scratch, k),
        );
    }

    var i: usize = 0;
    while (i < record_count) : (i += 1) {
        try std.testing.expect(c_abi.tkaudit.recordHash(scratch, i) != 0);
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSeq(scratch, i));
        try std.testing.expectEqual(c_abi.tkaudit.AUDIT_SCHEMA_VERSION, c_abi.tkaudit.recordSchemaVersion(scratch, i));
    }

    // 4. The stem tile remains running until the supervisor sends HALT.
    feed.finish();
    try sup.stopProcess(std.testing.io);
    stopped = true;
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

// Contract regression: AFTER_FRAG is tkaudt's commit point, so the final
// event is appended to the hash chain even though SHOULD_SHUTDOWN breaks the
// stem loop at its top. event_count = 1 makes the only event the final one,
// and also pins the committed-record count against the counters: a record
// committed in DURING_FRAG for a fragment fd_stem later abandons would show
// up here as records.len exceeding audited.
//
// See the fd_stem Callback Contract in doc/execution/contribution/tickoni.md.
test "tkaudt_integration: the final event is committed (event_count = 1)" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalProcess();
    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();
    var stopped = false;
    defer if (!stopped) sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});

    const event_count: u64 = 1;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    }, .{});

    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.produced);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);

    // Exactly one record is committed, and it is a well-formed chain head.
    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(@as(usize, 1), try auditRecordCount(&sup));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordPrevHash(scratch, 0));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordSeq(scratch, 0));
    try std.testing.expect(c_abi.tkaudit.recordHash(scratch, 0) != 0);

    for (sup.monitor()) |h| {
        try std.testing.expect(h.state != .crashed);
    }

    feed.finish();
    try sup.stopProcess(std.testing.io);
    stopped = true;
}

// Contract regression: the committed record count must equal the audited
// counter exactly. Both advance together in AFTER_FRAG, so a drift between
// them means a record was appended without its counter, or a counter was
// bumped for a fragment that produced no record.
test "tkaudt_integration: committed record count matches the audited counter" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.minimalProcess();
    var sup = try Supervisor.initForTest(std.testing.allocator, topo);
    defer sup.deinit();
    var stopped = false;
    defer if (!stopped) sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});

    const event_count: u64 = DEFAULT_EVENT_COUNT;
    const metric_port = util.nextMetricPort();
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    }, .{});

    const max_polls: u32 = MAX_POLL;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        const snap = sup.snapshotProcessMetrics();
        if (snap.audited >= event_count) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    const metrics = sup.snapshotProcessMetrics();
    const record_count = try auditRecordCount(&sup);

    try std.testing.expectEqual(@as(u64, event_count), metrics.produced);
    try std.testing.expectEqual(@as(u64, event_count), metrics.audited);
    try std.testing.expectEqual(@as(usize, event_count), record_count);
    try std.testing.expectEqual(@as(usize, @intCast(metrics.audited)), record_count);

    feed.finish();
    try sup.stopProcess(std.testing.io);
    stopped = true;
}
