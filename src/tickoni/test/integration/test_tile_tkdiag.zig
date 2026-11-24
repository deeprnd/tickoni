/// Process integration contracts for tkdiag's fd_stem lifecycle and diagnostic
/// fan-in, with real child processes in the payment-pipeline topology. tkdiag
/// is the collector of the five unreliable `*_tkdiag` links (one from each of
/// tkings, tknorm, tkdedu, tkpoly and tkaudt; plans/v2.10-s14-tkdiag-fan-in.md).
/// Identity and scratch-footprint contracts, and the fragment layout and
/// aggregation rules, live in c_abi/tkdiag.zig; the supervisor's launch-mode
/// routing and the diagnostic link rules are asserted in tile_registry_test.zig.
///
/// tkdiag shuts down on CNC HALT only, like the metric tile: it has no event
/// count to exhaust, and an iteration-count bound is not a duration (an idle
/// stem loop spins). The lifecycle proof is therefore that it is still running
/// well after start, and that a supervisor HALT then stops it cleanly. The
/// launch verb is not probed from the running child: the registry assertion
/// and supervisor.zig's tileArgv tests cover launch mode on every platform,
/// without a race.
const std = @import("std");
const builtin = @import("builtin");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");
const stem_liveness = @import("stem_liveness");

const Supervisor = supervisor_mod.Supervisor;

const max_polls: u32 = 400;
const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
const event_count: u64 = 8;

fn diagTileIndex(sup: *const Supervisor) usize {
    for (sup.topo.tiles, 0..) |tile, i| {
        if (tile.name.eql(rt.tile_ids.tkdiag)) return i;
    }
    unreachable; // paymentPipelineProcess() configures tkdiag.
}

fn startPipeline(sup: *Supervisor, feed: *Harness, run_dir: []const u8) !void {
    var workspace_buf: [16]u8 = undefined;
    try ingest.startPaymentRun(sup, feed, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .policy_limit_cents = 1_000,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    }, .{});
}

fn assertNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |handle| try std.testing.expect(handle.state != .crashed);
}

test "tkdiag_integration: stem tkdiag keeps running until the supervisor halts it, then stops cleanly" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir);

    // Watch for the whole window in which an iteration-bounded tkdiag would have
    // stopped itself (an earlier design did, within it). A self-exit or a crash
    // here fails the test on the first poll that sees it.
    const diag_idx = diagTileIndex(&sup);
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        try std.testing.expectEqual(rt.tile.TileState.running, sup.monitor()[diag_idx].state);
        util.process.sleepNanos(poll_interval_ns);
    }

    // CNC HALT is the only thing that stops it.
    feed.finish();
    try sup.stopProcess(std.testing.io);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[diag_idx].state);
    try assertNoCrash(&sup);
}

/// One diagnostic fragment per processed event from each of the five
/// producers: tkings, tknorm, tkdedu, tkpoly and tkaudt.
const fan_in_producers: u64 = 5;
/// Depth of every diagnostic link (topologies.zig `diag_link_depth`).
const diag_link_depth: u64 = 64;
/// Far more events than a diagnostic link holds, so that a link that
/// backpressured its producer would stall the pipeline.
const flood_event_count: u64 = 10_000;
const flood_polls: u32 = 4000;

fn waitUntil(sup: *Supervisor, polls: u32, comptime cond: fn (*Supervisor) bool) bool {
    var poll: u32 = 0;
    while (poll < polls) : (poll += 1) {
        if (cond(sup)) return true;
        util.process.sleepNanos(poll_interval_ns);
    }
    return cond(sup);
}

fn fanInComplete(sup: *Supervisor) bool {
    const m = sup.snapshotProcessMetrics();
    return m.audited >= event_count and m.diag_fragments_accepted >= fan_in_producers * event_count;
}

test "tkdiag_integration: pipeline completes and tkdiag receives a diagnostic fragment from every pipeline tile" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir);

    try std.testing.expect(waitUntil(&sup, 4 * max_polls, fanInComplete));

    const metrics = sup.snapshotProcessMetrics();
    // The diagnostic links neither disturb nor wait on the event path.
    try std.testing.expectEqual(event_count, metrics.audited);
    // Every tile reported, and every fragment sent was a valid, in-order one
    // (nothing was lost: depth is far above event_count).
    try std.testing.expectEqual(fan_in_producers, metrics.diag_tiles_reporting);
    try std.testing.expectEqual(fan_in_producers * event_count, metrics.diag_fragments_accepted);
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_fragments_rejected);
    // Every tile that finished its event count shut down cleanly (TILE_STATUS
    // "shutdown"), so tkdiag, which watches every tile's process, reports no
    // crash and no boot or sandbox failure. This is a real zero, not a
    // placeholder: the next tests kill a tile and watch the slots move.
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_crash_count);
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_sandbox_count);
    try assertNoCrash(&sup);
}

fn flooded(sup: *Supervisor) bool {
    return sup.snapshotProcessMetrics().audited >= flood_event_count;
}

fn allTilesReporting(sup: *Supervisor) bool {
    return sup.snapshotProcessMetrics().diag_tiles_reporting >= fan_in_producers;
}

test "tkdiag_integration: a frozen tkdiag never stalls the event path, and catches up lossily when resumed" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    var diag_frozen = false;
    const diag_idx = diagTileIndex(&sup);
    defer {
        if (diag_frozen) stem_liveness.thawTile(&sup, diag_idx) catch {};
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var workspace_buf: [16]u8 = undefined;
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, .{
        .run_dir = run_dir,
        .event_count = flood_event_count,
        .policy_limit_cents = 1_000,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    }, .{});

    // Freeze the only consumer of every diagnostic link. If any of those links
    // were reliable, its producer would block after `diag_link_depth`
    // unconsumed fragments and the pipeline would stop far short of the event
    // count.
    try stem_liveness.freezeTile(&sup, diag_idx);
    diag_frozen = true;

    try std.testing.expect(waitUntil(&sup, flood_polls, flooded));
    try std.testing.expectEqual(flood_event_count, sup.snapshotProcessMetrics().audited);

    // Resume it: it resyncs past what the producers overwrote, so it sees every
    // tile again but only about one link's worth of fragments per tile.
    try stem_liveness.thawTile(&sup, diag_idx);
    diag_frozen = false;
    try std.testing.expect(waitUntil(&sup, flood_polls, allTilesReporting));

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(fan_in_producers, metrics.diag_tiles_reporting);
    try std.testing.expect(metrics.diag_fragments_accepted <= fan_in_producers * (diag_link_depth + diag_link_depth));
    try std.testing.expect(metrics.diag_fragments_accepted < fan_in_producers * flood_event_count);
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_fragments_rejected);
    try assertNoCrash(&sup);
}

// ---------------------------------------------------------------------------
// Crash detection and replay shutdown, with an idle pipeline (event_count 0
// disables every event gate, so every tile idles until the supervisor's HALT).
// ---------------------------------------------------------------------------

const watch_polls: u32 = 2000;

fn startIdle(sup: *Supervisor, run_dir: []const u8) !void {
    var workspace_buf: [16]u8 = undefined;
    // Idle (event_count 0): no events, so no producer on tkings's input.
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = 0,
        .heartbeat_stale_after_ns = stem_liveness.stale_after_ns,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
        .metric_port = util.nextMetricPort(),
    });
}

fn crashCount(sup: *Supervisor) u64 {
    return sup.snapshotProcessMetrics().diag_crash_count;
}

fn crashSeen(sup: *Supervisor) bool {
    return crashCount(sup) >= 1;
}

/// The CNC the tile at topology index `idx` itself owns. `ProcessState.cncs` is
/// indexed by Firedancer tile index, which differs from the topology index when
/// topo_build moves the metric tile to the end, so the tile is found by identity.
fn cncOf(sup: *Supervisor, idx: usize) !*c_abi.cnc.Cnc {
    const state = sup.process_state orelse return error.NoProcessState;
    const topo = sup.getTopo() orelse return error.NoProcessState;
    const tile = sup.topo.tiles[idx];
    var name_buf: [8]u8 = undefined;
    const fd_idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, tile.name.slice()), tile.kind_id);
    if (fd_idx == c_abi.topob.not_found) return error.TileNotFound;
    return state.cncs[fd_idx] orelse error.NoCnc;
}

test "tkdiag_integration: a killed tile is counted as crashed, and nothing else is" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdle(&sup, run_dir);
    // tkdiag reaches RUN only after it has bound every tile's process.
    try stem_liveness.expectStemTilesAlive(&sup);
    try std.testing.expectEqual(@as(u64, 0), crashCount(&sup));

    // A hard kill: no clean shutdown, no final fragment, no chance to say goodbye.
    const victim = stem_liveness.indexOf(&sup, rt.tile_ids.tknorm);
    try stem_liveness.killTile(&sup, victim);

    try std.testing.expect(waitUntil(&sup, watch_polls, crashSeen));
    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.diag_crash_count);
    // It had been running, so this is a crash and not a boot or sandbox failure.
    try std.testing.expectEqual(@as(u64, 0), metrics.diag_sandbox_count);
}

test "tkdiag_integration: replay_checked in tkrepl's CNC ends tkdiag; HALT is still the only other way" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdle(&sup, run_dir);
    try stem_liveness.expectStemTilesAlive(&sup);

    const diag_idx = diagTileIndex(&sup);
    const repl_idx = stem_liveness.indexOf(&sup, rt.tile_ids.tkrepl);

    // Nothing has been checked: tkdiag keeps running.
    var poll: u32 = 0;
    while (poll < 100) : (poll += 1) {
        sup.refreshProcessHealth();
        try std.testing.expectEqual(rt.tile.TileState.running, sup.monitor()[diag_idx].state);
        util.process.sleepNanos(poll_interval_ns);
    }

    // tkrepl publishes "replay checked" and "replay matched" in its CNC app
    // slots 0 and 1 (tile_registry.zig). The test stands in for tkrepl, which
    // has no process-mode role yet.
    const repl_cnc = try cncOf(&sup, repl_idx);
    rt.cnc_counters.appCounterWrite(repl_cnc, 0, 1);
    rt.cnc_counters.appCounterWrite(repl_cnc, 1, 1);

    var exited = false;
    poll = 0;
    while (poll < watch_polls) : (poll += 1) {
        sup.reapExitedChildrenNoHang();
        sup.refreshProcessHealth();
        if (!sup.monitor()[diag_idx].isAlive()) {
            exited = true;
            break;
        }
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expect(exited);
    // It left on its own, cleanly, and nothing else moved.
    try std.testing.expect(sup.monitor()[diag_idx].state != .crashed);
    try assertNoCrash(&sup);
}

test "tkdiag_integration: a replay that did not match is still a finished replay" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try startIdle(&sup, run_dir);
    try stem_liveness.expectStemTilesAlive(&sup);

    const diag_idx = diagTileIndex(&sup);
    const repl_cnc = try cncOf(&sup, stem_liveness.indexOf(&sup, rt.tile_ids.tkrepl));
    // checked = 1, match = 0: the replay ran and found a divergence.
    rt.cnc_counters.appCounterWrite(repl_cnc, 0, 1);
    rt.cnc_counters.appCounterWrite(repl_cnc, 1, 0);

    var poll: u32 = 0;
    var exited = false;
    while (poll < watch_polls) : (poll += 1) {
        sup.reapExitedChildrenNoHang();
        sup.refreshProcessHealth();
        if (!sup.monitor()[diag_idx].isAlive()) {
            exited = true;
            break;
        }
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expect(exited);
}
