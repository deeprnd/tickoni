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

// ---------------------------------------------------------------------------
// Test: audit record allocation (Step 3.1) — tile boots and counts
// ---------------------------------------------------------------------------

test "tkaudt_integration: Step 3.1 audit record allocation and counting stub" {
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
    std.debug.print("[test] Step 3.1: produced={d} audited={d}\\n", .{ metrics.produced, metrics.audited });
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
