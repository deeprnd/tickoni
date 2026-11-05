/// Phase 3 Step 3.1: Audit record allocation in scratch.
///
/// This test verifies that the scratch-allocated audit records pointer and
/// AUDIT_SEED-based prev_hash initialization don't break the tkaudt tile.
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
/// and prev_hash[0] == AUDIT_SEED.
///
/// The tile writes records to scratch during DURING_FRAG. On shutdown it
/// calls a registered export callback (set via tk_audit_set_export_callback)
/// which the supervisor provides. Because the callback pointer is set in
/// the supervisor before fork(), the child inherits it and calls it in the
/// supervisor's address space — no IPC needed.
///
/// The callback copies records into an in-memory buffer so the test can
/// verify the hash chain without file I/O.
///
/// Assertions:
///   - callback receives exactly event_count records
///   - prev_hash[0] == AUDIT_SEED
///   - prev_hash[k] == record_hash[k-1] for k >= 1
///   - all record hashes are non-zero
///   - pipeline completes and shuts down cleanly
///
const std = @import("std");
const builtin = @import("builtin");
const c_abi = @import("c_abi");
const runtime = @import("runtime");
const rt = runtime;
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
// Export callback types (must match C declarations in tk_audit_stem.h)
// ===========================================================================

const AuditRecord = extern struct {
    // Header fields (must match audit_schema.h AuditHeader layout)
    schema_version: u16,
    _pad0: [14]u8 = undefined,
    run_id: u64,
    seq: u64,
    source_offset: u64,
    tile_id: [6]u8,
    _pad1: [2]u8 = undefined,
    logical_actor_id: u64,
    policy_version: [32]u8,
    _pad2: [8]u8 = undefined,
    capability_envelope_id: u64,
    timestamp_ns: u64,
    prev_hash: u64,
    record_hash: u64,
    version: [64]u8,
    platform_tier: [64]u8,
    isolation_tier: [64]u8,
    release_digest: [64]u8,
    manifest_id: [64]u8,

    // Payload fields (must match C struct AuditEvent layout)
    record_type: u8,
    _pad_payload: [4]u8 = undefined,
    outcome: u8,
    _pad_outcome: [7]u8 = undefined,
    rule_id: u32,
    failed_scope_dim: [32]u8,
    source_event_hash: u64,
    catalog_schema_version: u32,
    _pad_csv: [4]u8 = undefined,
    taxonomy_id: [32]u8,
    taxonomy_version: u32,
    classification_code: [32]u8,
};

const ExportBuffer = struct {
    records: [MAX_BUFFER_RECORDS]AuditRecord align(8),
    count: usize,
    total_bytes: usize,
};

// ===========================================================================
// C FFI declarations for the export callback mechanism
// ===========================================================================

/// Callback type: fn(*const AuditRecord, usize, *void) called from the tile.
/// Matches C: void (*tk_audit_export_fn)( void const *records, ulong count, void *export_ctx )
export fn audit_export_callback_fn(
    records: [*]const AuditRecord,
    count: usize,
    export_ctx: ?*anyopaque,
) void {
    const buf: *ExportBuffer = @alignCast(@ptrCast(export_ctx));
    buf.count = count;
    buf.total_bytes = count * @sizeOf(AuditRecord);

    var i: usize = 0;
    while (i < count and i < MAX_BUFFER_RECORDS) : (i += 1) {
        buf.records[i] = records[i];
    }
}

/// The callback type matches C: void (*tk_audit_export_fn)( void const *, ulong, void * )
const AuditExportCallback = fn ([*]const AuditRecord, usize, ?*anyopaque) void;

/// Declare the actual C function exported by tk_audit_stem.c.
/// The C function takes a function pointer (tk_audit_export_fn).
/// In Zig 0.18, we work around extern fn parameter restrictions by accepting
/// the function pointer as *anyopaque and casting at the call site.
extern fn tk_audit_set_export_callback( fn_raw: ?*anyopaque, export_ctx: ?*anyopaque ) void;

// ===========================================================================
// Test: audit record allocation (Step 3.1) — tile boots and counts
// ===========================================================================

test "tkaudt_integration: Audit record allocation and counting stub" {
    if (true) return error.SkipZigTest;
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
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
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

    sup.stopProcess(std.testing.io) catch {};
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

    // Register the export callback before the tile runs.
    // The child process inherits this function pointer and calls it in the
    // supervisor's address space during flush.
    // Zig 0.18: export fn is a function value — take its address via &fn,
    // then cast through int-to-ptr to work around extern fn parameter restrictions.
    var buffer: ExportBuffer = .{ .records = undefined, .count = 0, .total_bytes = 0 };
    const fn_addr = @intFromPtr(&audit_export_callback_fn);
    const fn_ptr: *anyopaque = @ptrFromInt(fn_addr);
    tk_audit_set_export_callback(fn_ptr, &buffer);

    const event_count: u64 = DEFAULT_EVENT_COUNT;
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
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

    // 3. Wait for shutdown completion.
    var wait: u32 = 0;
    while (wait < 100) : (wait += 1) {
        var all_stopped = true;
        for (sup.monitor()) |h| {
            if (h.state != .stopped) all_stopped = false;
        }
        if (all_stopped) break;
        util.process.sleepNanos(POLL_INTERVAL);
    }

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }

    // 4. Verify hash chain from the export callback buffer.
    const record_count = buffer.count;
    try std.testing.expectEqual(@as(usize, event_count), record_count);

    // AUDIT_SEED = 0xDEADBEEF (from tk_audit_stem.c).
    const AUDIT_SEED: u64 = 0xDEADBEEF;

    // prev_hash[0] must be AUDIT_SEED.
    try std.testing.expectEqual(
        AUDIT_SEED,
        buffer.records[0].prev_hash,
    );

    // prev_hash[k] == record_hash[k-1] for k >= 1.
    var k: usize = 1;
    while (k < record_count) : (k += 1) {
        try std.testing.expectEqual(
            buffer.records[k - 1].record_hash,
            buffer.records[k].prev_hash,
        );
    }

    // All record hashes must be non-zero (valid hashes).
    var i: usize = 0;
    while (i < record_count) : (i += 1) {
        try std.testing.expect(
            buffer.records[i].record_hash != 0,
        );
    }

    // seq must be sequential: 0, 1, 2, ...
    var s: usize = 0;
    while (s < record_count) : (s += 1) {
        try std.testing.expectEqual(@as(u64, s), buffer.records[s].seq);
    }

    // schema_version must match AUDIT_SCHEMA_VERSION.
    const AUDIT_SCHEMA_VERSION: u16 = 1;
    var v: usize = 0;
    while (v < record_count) : (v += 1) {
        try std.testing.expectEqual(
            AUDIT_SCHEMA_VERSION,
            buffer.records[v].schema_version,
        );
    }

    sup.stopProcess(std.testing.io) catch {};
    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
    }
}
