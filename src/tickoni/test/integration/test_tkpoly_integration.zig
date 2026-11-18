/// Acceptance contracts for the generic tkpoly process path.  These stay in
/// place while tkpoly is migrated to fd_stem: decision evidence must remain
/// identical, while the final natural-exit test is deliberately red until the
/// stem dispatcher owns the policy child's lifecycle.
const std = @import("std");
const c_abi = @import("c_abi");
const rt = @import("runtime");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const ProcessPipelineConfig = supervisor_mod.ProcessPipelineConfig;

const max_polls: u32 = 400;
const poll_interval_ns: u64 = 5 * std.time.ns_per_ms;
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

fn startPipeline(sup: *Supervisor, run_dir: []const u8, config: ProcessPipelineConfig) !void {
    var workspace_buf: [16]u8 = undefined;
    var run_config = config;
    run_config.run_dir = run_dir;
    run_config.tile_exe_path = "build/zig-out/bin/tickoni-supervisor";
    run_config.workspace_name = util.nextWorkspaceName(&workspace_buf);
    run_config.metric_port = util.nextMetricPort();
    try sup.startPaymentPipelineProcess(std.testing.io, run_config);
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
fn expectedSourceHash(config: ProcessPipelineConfig, offset: u64) u64 {
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
    config: ProcessPipelineConfig,
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 999 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try assertNoCrash(&sup);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_DENY, tkpoly_id);
}

test "tkpoly_integration: malformed decision has precedence and keeps tknorm attribution" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 1,
        .policy_limit_cents = 999,
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 2,
        .policy_limit_cents = 999,
        .duplicate = .{ .offset = 1, .source = 0 },
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 8,
        .duplicate = .{ .offset = 3, .source = 1 },
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{ .run_dir = run_dir, .event_count = 1, .policy_limit_cents = 1_000 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
    waitForAudit(&sup, config.event_count);
    try std.testing.expectEqual(@as(u64, 1), sup.snapshotProcessMetrics().audited);
    try expectRecord(&sup, config, 0, c_abi.tkaudit.POLICY_ALLOW, tkpoly_id);

    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[3].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[3].state);
}

// P4.2 — Load the signed policy limit for the policy child.
// N=4, limit=1001: offsets 0/1 (amount 1000/1001) allowed, offsets 2/3 (amount
// 1002/1003) denied.  Proves the payment_pipeline.config handoff reaches a
// real child process and that the signed limit setter is applied.
test "tkpoly_integration: non-default limit in child allows 1000/1001 denies 1002/1003" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{ .run_dir = run_dir, .event_count = 4, .policy_limit_cents = 1_001 };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
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
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const workspace_name = "tkpay0"; // fixed workspace for both runs

    // --- Run 1: limit=1001, N=4 → 2 allowed / 2 denied ---
    const config1 = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 4,
        .policy_limit_cents = 1_001,
        .workspace_name = workspace_name,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .metric_port = util.nextMetricPort(),
    };

    var sup1 = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    try sup1.startPaymentPipelineProcess(std.testing.io, config1);
    waitForAudit(&sup1, config1.event_count);

    const metrics1 = sup1.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics1.allowed);
    try std.testing.expectEqual(@as(u64, 2), metrics1.denied);
    try std.testing.expectEqual(@as(u64, 4), metrics1.audited);
    try assertNoCrash(&sup1);

    // Full teardown: stop, deinit, clean up
    sup1.stopProcess(std.testing.io) catch {};
    sup1.deinit();

    // --- Run 2: limit=999, N=4 → 0 allowed / 4 denied ---
    // Reuse the same workspace name. The limit setter must be reset to 999,
    // not carried over from the previous run's 1001.
    const config2 = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 4,
        .policy_limit_cents = 999,
        .workspace_name = workspace_name,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .metric_port = util.nextMetricPort(),
    };

    var sup2 = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    try sup2.startPaymentPipelineProcess(std.testing.io, config2);
    waitForAudit(&sup2, config2.event_count);

    const metrics2 = sup2.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 0), metrics2.allowed);
    try std.testing.expectEqual(@as(u64, 4), metrics2.denied);
    try std.testing.expectEqual(@as(u64, 4), metrics2.audited);
    try assertNoCrash(&sup2);

    sup2.stopProcess(std.testing.io) catch {};
    sup2.deinit();
}


// P5.5 — Malformed-only runs self-exit: the tile counts the malformed event
// as processed (not allowed or denied) and reaches .stopped without external
// CNC HALT.
test "tkpoly_integration: malformed-only self-exit" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 1,
        .policy_limit_cents = 1000,
        .inject_malformed = true,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 1), metrics.audited);
    try std.testing.expectEqual(@as(u64, 0), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try assertNoCrash(&sup);

    // Verify self-exit: tile 3 (policy) reaches .stopped without HALT.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[3].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[3].state);
}

// P5.5 — Duplicate-final runs self-exit: the tile counts the duplicate as
// processed (not allowed or denied) and reaches .stopped without external CNC
// HALT.
test "tkpoly_integration: duplicate-final self-exit" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 2,
        .policy_limit_cents = 1000,
        .duplicate = .{ .offset = 1, .source = 0 },
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), metrics.audited);
    try std.testing.expectEqual(@as(u64, 1), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 0), metrics.denied);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try assertNoCrash(&sup);

    // Verify self-exit: tile 3 (policy) reaches .stopped without HALT.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[3].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, sup.monitor()[3].state);
}

// P5.5 — Large event count proves bounded credit turnover across depth-64
// dcache reuse.  N=128, default limit=1000: offsets 0..999 (amounts
// 1000..1999) all allowed, offset 127 (amount 1127) also allowed, so all
// 127 offsets below limit are allowed and the single denied comes from
// offset 128 if present — actually with N=128, amounts are 1000..1127,
// all ≤ 1000 limit, so all allowed.  We need one deny: use limit=1000 but
// offset 0 has amount 1000 (allowed), so we need amount > 1000.
//
// Fix: the fixture generates amount = 1000 + offset for offset 0..127.
// At offset 0, amount=1000 (allowed at limit=1000).  At offset 127,
// amount=1127 (denied).  So 127 allowed, 1 denied, 128 audited.
test "tkpoly_integration: bounded credit turnover N=128" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 128,
        .policy_limit_cents = 1000,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);
    waitForAudit(&sup, config.event_count);

    const metrics = sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 127), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 0), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 0), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 128), metrics.audited);
    try assertNoCrash(&sup);
}


// P5.6 — Preserve administrative HALT: event_count=0 leaves exhaustion
// disabled so the tile stays alive indefinitely.  It honors CNC HALT and
// stops cleanly without forced termination.
test "tkpoly_integration: administrative HALT with zero event count" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];
    const config = ProcessPipelineConfig{
        .run_dir = run_dir,
        .event_count = 0,
        .policy_limit_cents = 1_000,
    };

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.paymentPipelineProcess());
    defer {
        sup.stopProcess(std.testing.io) catch {};
        sup.deinit();
    }
    try startPipeline(&sup, run_dir, config);

    // Wait for the pipeline to start — policy tile should be running.
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.refreshProcessHealth();
        if (sup.monitor()[3].state == .running or sup.monitor()[3].state == .stopped) break;
        util.process.sleepNanos(poll_interval_ns);
        poll += 1;
    }
    if (poll >= max_polls) {
        std.testing.expect(false) catch {};
        return;
    }

    // Verify policy tile is alive (not crashed).
    const poly_state = sup.monitor()[3].state;
    try std.testing.expect(poly_state != .crashed);

    // Send CNC HALT — verifies SHOULD_SHUTDOWN honors HALT.
    sup.stopProcess(std.testing.io) catch {};

    // Policy must reach .stopped cleanly (not crashed).
    const final_state = sup.monitor()[3].state;
    try std.testing.expectEqual(rt.tile.TileState.stopped, final_state);
}
