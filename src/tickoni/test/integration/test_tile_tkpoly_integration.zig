/// Replay-stability contract for the tkpoly fd_stem tile.
///
/// test_tile_tkpoly.zig pins each decision branch, counter and shutdown path
/// for a single run. This file pins the cross-run property the framework
/// invariants require: the same authenticated input and the same signed
/// policy limit must produce the same hash-chained audit records, run after
/// run (no process-local timing or allocation order may leak into outcomes,
/// source-event hashes, or the chain).
///
/// The helpers are intentionally local: each integration file is its own test
/// root module, so it cannot import test_tile_tkpoly.zig.
const std = @import("std");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;

const max_polls: u32 = 400;
const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
const event_count: usize = 8;

/// One audit record's replay-relevant fields.
const ChainEntry = struct {
    seq: u64,
    source_offset: u64,
    outcome: u8,
    source_event_hash: u64,
    prev_hash: u64,
    hash: u64,
};

fn auditScratch(sup: *Supervisor) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const tile_id = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, "tkaudt"), 0);
    if (tile_id == c_abi.topob.not_found) return error.AuditTileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, tile_id));
}

fn waitForAudit(sup: *Supervisor, expected: u64) !void {
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= expected) return;
        util.process.sleepNanos(poll_interval_ns);
    }
    return error.AuditTimeout;
}

/// Runs the full pipeline once and returns its audit chain. Uses the same
/// fixed workspace name for every call, matching the cross-run reuse that the
/// "configuration does not leak between runs" test exercises.
fn runAndCaptureChain(run_dir: []const u8, config: ProcessPipelineConfig) ![event_count]ChainEntry {
    var run_config = config;
    run_config.run_dir = run_dir;
    run_config.tile_exe_path = "build/zig-out/bin/tickoni-supervisor";
    run_config.metric_port = util.nextMetricPort();

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    try sup.startPaymentPipelineProcess(std.testing.io, run_config);
    try waitForAudit(&sup, event_count);

    for (sup.monitor()) |handle| try std.testing.expect(handle.state != .crashed);
    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(event_count, c_abi.tkaudit.recordCount(scratch));

    var chain: [event_count]ChainEntry = undefined;
    for (&chain, 0..) |*entry, i| {
        entry.* = .{
            .seq = c_abi.tkaudit.recordSeq(scratch, i),
            .source_offset = c_abi.tkaudit.recordSourceOffset(scratch, i),
            .outcome = c_abi.tkaudit.recordOutcome(scratch, i),
            .source_event_hash = c_abi.tkaudit.recordSourceEventHash(scratch, i),
            .prev_hash = c_abi.tkaudit.recordPrevHash(scratch, i),
            .hash = c_abi.tkaudit.recordHash(scratch, i),
        };
    }
    return chain;
}

test "tkpoly_integration: identical input yields an identical audit chain across runs" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    // Every decision branch in one run: allow, deny (offset 7), duplicate
    // (offset 3 repeats offset 1), and malformed (offset 5).
    var workspace_buf: [16]u8 = undefined;
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = event_count,
        .duplicate = .{ .offset = 3, .source = 1 },
        .inject_malformed = true,
        .workspace_name = util.nextWorkspaceName(&workspace_buf),
    };

    const first = try runAndCaptureChain(run_dir, config);
    const second = try runAndCaptureChain(run_dir, config);

    // The chain must be well-formed in its own right (not trivially equal
    // because both runs are empty or zeroed).
    try std.testing.expectEqual(@as(u64, 0), first[0].prev_hash);
    for (first, 0..) |entry, i| {
        try std.testing.expectEqual(@as(u64, i), entry.seq);
        try std.testing.expect(entry.hash != 0);
        if (i > 0) try std.testing.expectEqual(first[i - 1].hash, entry.prev_hash);
    }
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_DENY, first[7].outcome);
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_DUPLICATE_DROP, first[3].outcome);
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_MALFORMED_DROP, first[5].outcome);

    // Replay stability: field-for-field identical, including the hash chain.
    for (first, second, 0..) |a, b, i| {
        std.testing.expectEqual(a, b) catch |err| {
            std.debug.print("audit chain diverged between runs at record {d}\n", .{i});
            return err;
        };
    }
}
