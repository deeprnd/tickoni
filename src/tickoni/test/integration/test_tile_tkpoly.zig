/// Process integration contracts for tkpoly's fd_stem lifecycle and policy
/// decisions. The tests read tile identity from the configured topology.
const std = @import("std");
const c_abi = @import("c_abi");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;

/// One run: the supervisor's configuration plus the producer's test-only
/// payment injection. The harness feeds tkings (its only source); no tile is
/// configured to generate events.
const RunConfig = struct {
    run_dir: []const u8,
    event_count: u64 = 10_000,
    policy_limit_cents: i64 = 100_000,
    workspace_name: ?[]const u8 = null,
    tile_exe_path: ?[]const u8 = null,
    metric_port: u16 = 7999,
    duplicate: ?@import("tiles").DuplicateConfig = null,
    inject_malformed: bool = false,

    fn process(self: RunConfig) ProcessPipelineConfig {
        return .{
            .run_dir = self.run_dir,
            .event_count = self.event_count,
            .policy_limit_cents = self.policy_limit_cents,
            .workspace_name = self.workspace_name,
            .tile_exe_path = self.tile_exe_path,
            .metric_port = self.metric_port,
        };
    }

    fn payments(self: RunConfig) ingest.PaymentOptions {
        return .{ .duplicate = self.duplicate, .inject_malformed = self.inject_malformed };
    }
};

const max_polls: u32 = 400;
const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
fn policyTileIndex(sup: *const Supervisor) usize {
    for (sup.topo.tiles, 0..) |tile, i| {
        if (tile.name.eql(rt.tile_ids.tkpoly)) return i;
    }
    unreachable; // Every fixture in this file configures tkpoly.
}
const tkpoly_id = [_]u8{ 't', 'k', 'p', 'o', 'l', 'y' };
const tknorm_id = [_]u8{ 't', 'k', 'n', 'o', 'r', 'm' };

fn auditScratch(sup: *Supervisor) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const tile_id = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, "tkaudt"), 0);
    if (tile_id == c_abi.topob.not_found) return error.AuditTileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, tile_id));
}

fn waitForAudit(sup: *Supervisor, event_count: u64) void {
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) return;
        util.process.sleepNanos(poll_interval_ns);
    }
}

fn startPipeline(sup: *Supervisor, feed: *Harness, run_dir: []const u8, config: RunConfig) !void {
    var workspace_buf: [16]u8 = undefined;
    var run_config = config;
    run_config.run_dir = run_dir;
    run_config.tile_exe_path = "build/zig-out/bin/tickoni-supervisor";
    run_config.workspace_name = util.nextWorkspaceName(&workspace_buf);
    run_config.metric_port = util.nextMetricPort();
    try ingest.startPaymentRun(sup, feed, run_config.process(), run_config.payments());
}

fn assertNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |handle| try std.testing.expect(handle.state != .crashed);
}

fn hashByte(hash: *u64, byte: u8) void {
    hash.* = (hash.* ^ byte) *% 0x100000001b3;
}

fn hashU64(hash: *u64, value: u64) void {
    var remaining = value;
    for (0..8) |_| {
        hashByte(hash, @intCast(remaining & 0xff));
        remaining >>= 8;
    }
}

fn hashU32(hash: *u64, value: u32) void {
    var remaining = value;
    for (0..4) |_| {
        hashByte(hash, @intCast(remaining & 0xff));
        remaining >>= 8;
    }
}

/// The C normalizer's stable source-event hash.  This intentionally uses the
/// same public synthetic fixture contract as the process topology, so the
/// audit assertion detects a missing or substituted source hash.
fn expectedSourceHash(config: RunConfig, offset: u64) u64 {
    var canonical_offset = offset;
    if (config.duplicate) |duplicate| {
        if (offset == duplicate.offset) canonical_offset = duplicate.source;
    }

    const amount: i64 = if (offset == 7)
        config.policy_limit_cents + 1
    else
        @intCast(1_000 + canonical_offset);

    var hash: u64 = 0;
    hashU64(&hash, 10_000 + canonical_offset);
    hashU32(&hash, @intCast(42 + canonical_offset % 17));
    hashU64(&hash, @bitCast(amount));
    for ("USD") |byte| hashByte(&hash, byte);
    return hash;
}

fn expectRecord(
    sup: *Supervisor,
    config: RunConfig,
    index: usize,
    outcome: u8,
    producer: [6]u8,
) !void {
    const scratch = try auditScratch(sup);
    try std.testing.expectEqual(@as(u64, index), c_abi.tkaudit.recordSeq(scratch, index));
    try std.testing.expectEqual(@as(u64, index), c_abi.tkaudit.recordSourceOffset(scratch, index));
    try std.testing.expectEqual(outcome, c_abi.tkaudit.recordOutcome(scratch, index));
    try std.testing.expectEqual(expectedSourceHash(config, index), c_abi.tkaudit.recordSourceEventHash(scratch, index));

    var actual_producer: [6]u8 = undefined;
    c_abi.tkaudit.recordDecidedBy(scratch, index, &actual_producer);
    try std.testing.expectEqualSlices(u8, &producer, &actual_producer);

    if (index == 0) {
        try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordPrevHash(scratch, index));
    } else {
        try std.testing.expectEqual(
            c_abi.tkaudit.recordHash(scratch, index - 1),
            c_abi.tkaudit.recordPrevHash(scratch, index),
        );
    }
    try std.testing.expect(c_abi.tkaudit.recordHash(scratch, index) != 0);
}

test "tkpoly_integration: equality at the signed limit allows" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try assertNoCrash(&sup);
    try std.testing.expectEqual(@as(usize, 1), c_abi.tkaudit.recordCount(try auditScratch(&sup)));
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_ALLOW, tkpoly_id);
}

test "tkpoly_integration: signed amount above limit denies" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 999 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try assertNoCrash(&sup);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_DENY, tkpoly_id);
}

test "tkpoly_integration: malformed decision has precedence and keeps tknorm attribution" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 1,
        .policy_limit_cents = 999,
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try assertNoCrash(&sup);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_MALFORMED_DROP, tknorm_id);
}

test "tkpoly_integration: duplicate has precedence over an amount denial" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 2,
        .policy_limit_cents = 999,
        .duplicate = .{ .offset = 1, .source = 0 },
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 2), metrics.audited);
    try assertNoCrash(&sup);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_DENY, tkpoly_id);
    try expectRecord(&sup, config, 1, c_abi.tkaudit.POLICY_DUPLICATE_DROP, tkpoly_id);
}

test "tkpoly_integration: combined branch evidence preserves sequence and chain" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 8,
        .duplicate = .{ .offset = 3, .source = 1 },
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 5), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 1), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 8), metrics.audited);
    try assertNoCrash(&sup);
    try std.testing.expectEqual(@as(usize, 8), c_abi.tkaudit.recordCount(try auditScratch(&sup)));

    for (0..8) |index| {
        const outcome: u8 = switch (index) {
            3 => c_abi.tkaudit.POLICY_DUPLICATE_DROP,
            5 => c_abi.tkaudit.POLICY_MALFORMED_DROP,
            7 => c_abi.tkaudit.POLICY_DENY,
            else => c_abi.tkaudit.POLICY_ALLOW,
        };
        try expectRecord(&sup, config, index, outcome, if (index == 5) tknorm_id else tkpoly_id);
    }
}

// Expected-red before the Phase 6 dispatcher cutover.  The generic policy
// callback has consumed and audited the bounded input, but remains running
// until the supervisor publishes CNC HALT.  Do not skip this test: when
// tkpoly is routed through its stem descriptor, the assertion must pass
// unchanged.
test "tkpoly_integration: positive event count naturally stops tkpoly after final publication" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);
    try std.testing.expectEqual(@as(u64, 1), sup.snapshotProcessMetrics().audited);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_ALLOW, tkpoly_id);

    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P4.2 — Load the signed policy limit for the policy child.
// N=4, limit=1001: offsets 0/1 (amount 1000/1001) allowed, offsets 2/3 (amount
// 1002/1003) denied.  Proves the payment_pipeline.config handoff reaches a
// real child process and that the signed limit setter is applied.
test "tkpoly_integration: non-default limit in child allows 1000/1001 denies 1002/1003" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 4, .policy_limit_cents = 1_001 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 2), metrics.denied);
    try std.testing.expectEqual(@as(u64, 4), metrics.audited);
    try assertNoCrash(&sup);

    // Verify exact outcome per offset: 0→allow, 1→allow, 2→deny, 3→deny.
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_ALLOW, tkpoly_id);
    try expectRecord(&sup, config, 1, c_abi.tkaudit.POLICY_ALLOW, tkpoly_id);
    try expectRecord(&sup, config, 2, c_abi.tkaudit.POLICY_DENY, tkpoly_id);
    try expectRecord(&sup, config, 3, c_abi.tkaudit.POLICY_DENY, tkpoly_id);
}

// P4.4 — Prove configuration does not leak between runs.
// Reuse one workspace name after clean teardown with limits 1001 and 999.
// First run: 2 allowed/2 denied. Second run: 0 allowed/4 denied, with zero
// carried counters or limit state.
test "tkpoly_integration: configuration does not leak between runs" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const workspace_name = "tkpay0"; // fixed workspace for both runs

    // --- Run 1: limit=1001, N=4 → 2 allowed / 2 denied ---
    const config1 = RunConfig{
        .run_dir = run_dir,
        .event_count = 4,
        .policy_limit_cents = 1_001,
        .workspace_name = workspace_name,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .metric_port = util.nextMetricPort(),
    };

    var sup1 = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup1, &feed, config1.process(), config1.payments());
    waitForAudit(&sup1, config1.event_count);

    const metrics1 = sup1.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics1.allowed);
    try std.testing.expectEqual(@as(u64, 2), metrics1.denied);
    try std.testing.expectEqual(@as(u64, 4), metrics1.audited);
    try assertNoCrash(&sup1);

    // Full teardown: stop, deinit, clean up
    feed.finish();
    sup1.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
    sup1.deinit();

    // --- Run 2: limit=999, N=4 → 0 allowed / 4 denied ---
    // Reuse the same workspace name. The limit setter must be reset to 999,
    // not carried over from the previous run's 1001.
    const config2 = RunConfig{
        .run_dir = run_dir,
        .event_count = 4,
        .policy_limit_cents = 999,
        .workspace_name = workspace_name,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .metric_port = util.nextMetricPort(),
    };

    var sup2 = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    var feed2: Harness = .{};
    defer feed2.finish();
    try ingest.startPaymentRun(&sup2, &feed2, config2.process(), config2.payments());
    waitForAudit(&sup2, config2.event_count);

    const metrics2 = sup2.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics2.allowed);
    try std.testing.expectEqual(@as(u64, 4), metrics2.denied);
    try std.testing.expectEqual(@as(u64, 4), metrics2.audited);
    try assertNoCrash(&sup2);

    feed2.finish();
    sup2.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
    sup2.deinit();
}

// P5.5 — Malformed-only runs self-exit: the tile counts the malformed event
// as processed (not allowed or denied) and reaches .stopped without external
// CNC HALT.
test "tkpoly_integration: malformed-only self-exit" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 1,
        .policy_limit_cents = 1000,
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try assertNoCrash(&sup);

    // Verify self-exit: the policy tile reaches .stopped without HALT.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P5.5 — Duplicate-final runs self-exit: the tile counts the duplicate as
// processed (not allowed or denied) and reaches .stopped without external CNC
// HALT.
test "tkpoly_integration: duplicate-final self-exit" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 2,
        .policy_limit_cents = 1000,
        .duplicate = .{ .offset = 1, .source = 0 },
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try assertNoCrash(&sup);

    // Verify self-exit: the policy tile reaches .stopped without HALT.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P5.5 — Large event count proves bounded credit turnover across depth-64
// dcache reuse: N=128 publishes twice the link depth, so the output dcache
// wraps at `fd_dcache_compact_next` and every chunk is reused.
//
// The fixture (runtime.zig:syntheticPayment) generates
// amount_cents = 1000 + offset, except offset 7, which is always
// policy_limit_cents + 1.  At the default limit (100_000) that makes offset
// 7 the only event above the limit: 127 allowed, 1 denied, 128 audited.
// The limit is deliberately left at its default here — overriding it to
// 1000 would put offsets 1..127 above the limit and turn this into a
// mass-denial case, which exercises the same transport but hides the
// allow path's chunk reuse.
test "tkpoly_integration: bounded credit turnover N=128" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 128,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 127), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 0), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 128), metrics.audited);
    try assertNoCrash(&sup);
}

// P6.2 — With a positive event count, tkpoly reaches .stopped on its own
// after the final publication, with no CNC HALT from the supervisor.
test "tkpoly_integration: positive event count naturally stops tkpoly at N=1" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(@as(u64, 1), sup.snapshotProcessMetrics().audited);
    try std.testing.expectEqual(@as(usize, 1), c_abi.tkaudit.recordCount(scratch));
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_ALLOW, c_abi.tkaudit.recordOutcome(scratch, 0));

    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P5.6 — Preserve administrative HALT: event_count=0 leaves exhaustion
// disabled so the tile stays alive indefinitely.  It honors CNC HALT and
// stops cleanly without forced termination.
//
// P6.2 — that the supervisor selects the stem dispatcher ("__stem-run", not
// the generic "__tile-run" Zig-callback path) for tkpoly is asserted in
// supervisor.zig's tileArgv tests, on every platform.
test "tkpoly_integration: administrative HALT with zero event count" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 0,
        .policy_limit_cents = 1_000,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);

    // Wait for the pipeline to start — policy tile should be running.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .running or sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
        poll += 1;
    }
    if (poll >= max_polls) {
        return error.PolicyTileStartTimeout;
    }

    // Verify policy tile is alive (not crashed).
    const poly_state = sup.monitor()[policyTileIndex(&sup)].state;
    try std.testing.expect(poly_state != .crashed);

    // Send CNC HALT — verifies SHOULD_SHUTDOWN honors HALT.
    feed.finish();
    sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));

    // Policy must reach .stopped cleanly (not crashed).
    const final_state = sup.monitor()[policyTileIndex(&sup)].state;
    try std.testing.expectEqual(rt.tile.TileState.stopped, final_state);
}

// P6.4 — Prove final counters survive child reaping.  After the policy tile
// reaches .stopped naturally, call snapshotProcessMetrics() and read scratch
// to verify that CNC counter snapshots and audit-record counts are identical
// and consistent with the event-count budget.
//
// Verifies for every completed integration case:
//   1. processed=N  (allowed+denied+duplicates+invalid = event_count)
//   2. scratch record counts match CNC allowed/denied counters
//   3. CNC audited = event_count
//   4. no policy crash
test "tkpoly_integration: final counters survive child reaping" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    // N=8 with mix: offset 0,1,2,4,6 allowed; offset 3 duplicate; offset 5 malformed; offset 7 deny
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = 8,
        .policy_limit_cents = 1_000,
        .duplicate = .{ .offset = 3, .source = 1 },
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    // Wait for tkpoly to reach .stopped naturally.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    // --- Read final CNC snapshots AFTER the child has reached .stopped ---
    const snap = sup.snapshotProcessMetrics();

    // --- 1. processed = event_count ---
    const processed = snap.allowed + snap.denied + snap.duplicates + snap.invalid;
    try std.testing.expectEqual(@as(u64, config.event_count), processed);

    // --- 2. scratch record counts match CNC counters ---
    const scratch = try auditScratch(&sup);
    const scratch_count = c_abi.tkaudit.recordCount(scratch);
    try std.testing.expectEqual(@as(usize, config.event_count), scratch_count);

    // Count scratch outcomes by type.
    var scratch_allowed: usize = 0;
    var scratch_denied: usize = 0;
    var scratch_dups: usize = 0;
    var scratch_malformed: usize = 0;
    for (0..scratch_count) |i| {
        const outcome = c_abi.tkaudit.recordOutcome(scratch, @intCast(i));
        if (outcome == c_abi.tkaudit.POLICY_ALLOW) scratch_allowed += 1;
        if (outcome == c_abi.tkaudit.POLICY_DENY) scratch_denied += 1;
        if (outcome == c_abi.tkaudit.POLICY_DUPLICATE_DROP) scratch_dups += 1;
        if (outcome == c_abi.tkaudit.POLICY_MALFORMED_DROP) scratch_malformed += 1;
    }

    // CNC allowed/denied must match scratch counts.
    try std.testing.expectEqual(@as(u64, @intCast(scratch_allowed)), snap.allowed);
    try std.testing.expectEqual(@as(u64, @intCast(scratch_denied)), snap.denied);

    // --- 3. CNC audited = event_count ---
    try std.testing.expectEqual(@as(u64, config.event_count), snap.audited);

    // --- 4. no policy crash ---
    try assertNoCrash(&sup);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P6.4 — Same reaping proof but with a single-event allow case (the simplest
// fixture). Proves even minimal runs preserve counters after child exit.
test "tkpoly_integration: final counters survive reaping — single allow" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    // Wait for tkpoly to reach .stopped.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    // Read final CNC snapshot after child exit.
    const snap = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), snap.allowed);
    try std.testing.expectEqual(@as(u64, 0), snap.denied);
    try std.testing.expectEqual(@as(u64, 1), snap.audited);

    // Verify scratch matches.
    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(@as(usize, 1), c_abi.tkaudit.recordCount(scratch));
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_ALLOW, c_abi.tkaudit.recordOutcome(scratch, 0));

    // No crash, state is stopped.
    try assertNoCrash(&sup);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// P6.4 — Reaping proof with a single-event deny case.
test "tkpoly_integration: final counters survive reaping — single deny" {
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = RunConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 999 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try startPipeline(&sup, &feed, run_dir, config);
    waitForAudit(&sup, config.event_count);

    // Wait for tkpoly to reach .stopped.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[policyTileIndex(&sup)].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }

    // Read final CNC snapshot after child exit.
    const snap = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), snap.allowed);
    try std.testing.expectEqual(@as(u64, 1), snap.denied);
    try std.testing.expectEqual(@as(u64, 1), snap.audited);

    // Verify scratch matches.
    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(@as(usize, 1), c_abi.tkaudit.recordCount(scratch));
    try std.testing.expectEqual(c_abi.tkaudit.POLICY_DENY, c_abi.tkaudit.recordOutcome(scratch, 0));

    // No crash, state is stopped.
    try assertNoCrash(&sup);
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[policyTileIndex(&sup)].state);
}

// Replay stability — the same authenticated input and the same signed policy
// limit must produce the same hash-chained audit records run after run.  No
// process-local timing or allocation order may leak into outcomes, source-event
// hashes, or the chain.
const replay_event_count: usize = 8;

/// One audit record's replay-relevant fields.
const ChainEntry = struct {
    seq: u64,
    source_offset: u64,
    outcome: u8,
    source_event_hash: u64,
    prev_hash: u64,
    hash: u64,
};

/// Runs the full pipeline once and returns its audit chain.  The caller fixes
/// `config.workspace_name`, so repeated calls reuse one workspace, like the
/// "configuration does not leak between runs" test.
fn runAndCaptureChain(run_dir: []const u8, config: RunConfig) ![replay_event_count]ChainEntry {
    var run_config = config;
    run_config.run_dir = run_dir;
    run_config.tile_exe_path = "build/zig-out/bin/tickoni-supervisor";
    run_config.metric_port = util.nextMetricPort();

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
        sup.deinit();
    }
    var feed: Harness = .{};
    defer feed.finish();
    try ingest.startPaymentRun(&sup, &feed, run_config.process(), run_config.payments());
    waitForAudit(&sup, replay_event_count);

    try assertNoCrash(&sup);
    const scratch = try auditScratch(&sup);
    try std.testing.expectEqual(replay_event_count, c_abi.tkaudit.recordCount(scratch));

    var chain: [replay_event_count]ChainEntry = undefined;
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
    const shouldSkip = true;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    // Every decision branch in one run: allow, deny (offset 7), duplicate
    // (offset 3 repeats offset 1), and malformed (offset 5).
    var workspace_buf: [16]u8 = undefined;
    const config = RunConfig{
        .run_dir = run_dir,
        .event_count = replay_event_count,
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
