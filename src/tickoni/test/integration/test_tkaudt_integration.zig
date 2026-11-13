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
// Shared-scratch audit record layout
// ===========================================================================

const AuditHeader = extern struct {
    schema_version: u16,
    _pad0: [14]u8,
    run_id: u64,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    _pad1: [2]u8,
    logical_actor_id: u64,
    policy_version: [32]u8,
    _pad2: [8]u8,
    capability_envelope_id: u64,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
    version: [64]u8,
    platform_tier: [64]u8,
    isolation_tier: [64]u8,
    release_digest: [64]u8,
    manifest_id: [64]u8,
};

const PolicyDecisionPayload = extern struct {
    outcome: u8,
    _pad0: [7]u8,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    _pad1: [4]u8,
    source_event_hash: u64,
    catalog_schema_version: u32,
    _pad2: [4]u8,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
    _pad3: [4]u8,
};

/// Mirrors audit_schema.h's AuditEvent. The explicit seven-byte padding after
/// record_type accounts for the C compiler's three-byte alignment gap before
/// PolicyDecisionPayload in addition to AuditEvent._pad[4].
const AuditRecord = extern struct {
    header: AuditHeader,
    record_type: u8,
    _pad: [7]u8,
    policy_decision: PolicyDecisionPayload,
};

/// Prefix of tk_audit_ctx_t. The scratch record array begins directly after
/// this context and both C and Zig give it eight-byte alignment.
const AuditContext = extern struct {
    audited: u64,
    cnc: ?*anyopaque,
    audit_count: u64,
    prev_hash: u64,
    tile: ?*anyopaque,
    audit_records: ?*anyopaque,
    wksp: ?*anyopaque,
    event_count: u64,
    input_exhausted: i32,
};

fn auditRecords(sup: *Supervisor) ![]const AuditRecord {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const tile_id = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, tile_ids.tkaudt.slice()), 0);
    if (tile_id == c_abi.topob.not_found) return error.AuditTileNotFound;

    const tile_obj_id = c_abi.topob.topoTileObjId(topo, tile_id);
    const scratch = c_abi.topob.topoObjLaddr(topo, tile_obj_id);
    const ctx: *const AuditContext = @ptrCast(@alignCast(scratch));
    if (ctx.audit_count > MAX_BUFFER_RECORDS) return error.AuditRecordCapacityExceeded;

    const records_addr = @intFromPtr(scratch) + @sizeOf(AuditContext);
    const records: [*]const AuditRecord = @ptrFromInt(records_addr);
    return records[0..@intCast(ctx.audit_count)];
}

comptime {
    std.debug.assert(@sizeOf(AuditHeader) == 448);
    std.debug.assert(@sizeOf(PolicyDecisionPayload) == 136);
    std.debug.assert(@sizeOf(AuditRecord) == 592);
    std.debug.assert(@sizeOf(AuditContext) == 72);
}

// ===========================================================================
// Test: audit record allocation (Step 3.1) — tile boots and counts
// ===========================================================================

test "tkaudt_integration: Audit record allocation and counting stub" {
    if (false) return error.SkipZigTest;
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
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    });

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

    sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}

// ===========================================================================
// Test: hash chain verification (Step 3.3)
// ===========================================================================

test "tkaudt_integration: Hash chain verification" {
    if (false) return error.SkipZigTest;
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
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = metric_port,
    });

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
    const records = try auditRecords(&sup);
    try std.testing.expectEqual(@as(usize, event_count), records.len);

    // AUDIT_INITIAL_HASH = 0 (identity seed, from audit_consts.h).
    try std.testing.expectEqual(@as(u64, 0), records[0].header.prev_hash);

    var k: usize = 1;
    while (k < records.len) : (k += 1) {
        try std.testing.expectEqual(
            records[k - 1].header.record_hash,
            records[k].header.prev_hash,
        );
    }

    var i: usize = 0;
    while (i < records.len) : (i += 1) {
        try std.testing.expect(records[i].header.record_hash != 0);
        try std.testing.expectEqual(@as(u64, i), records[i].header.seq);
        try std.testing.expectEqual(@as(u16, 2), records[i].header.schema_version);
    }

    // 4. The stem tile remains running until the supervisor sends HALT.
    try sup.stopProcess(std.testing.io);
    stopped = true;
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}
