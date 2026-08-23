/// v2.14.S1 M4 acceptance proof: process-mode payment pipeline (real
/// supervisor-managed OS processes connected by Firedancer Tango shared
/// memory) produces the same decision counts as the thread-mode spike in
/// src/tickoni/tiles/payment_pipeline/runtime.zig for the same synthetic
/// input. Runs through production-like Tickoni internals (real
/// fork+exec, real mcache/dcache/fseq/cnc); the only substitution is a
/// scratch FD_SHMEM_PATH directory instead of an operator-managed host
/// workspace, per doc/execution/testing-tickoni.md's integration-lane
/// rule. No huge pages or sudo required.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const util = @import("util");
const topologies = @import("topologies");

const Supervisor = supervisor_mod.Supervisor;

test "process_pipeline_integration: process-mode payment pipeline matches expected decision counts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 32;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        // /proc/self/exe would resolve to this test binary, not
        // tickoni-supervisor; build.zig makes this test's run step
        // depend on the exe install step so this path is always
        // up to date. See ProcessPipelineConfig.tile_exe_path's doc
        // comment in src/app/tickoni/supervisor.zig.
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    // Poll for the real completion signal (audited count reaches
    // event_count) instead of a fixed sleep: process-mode tiles keep
    // heartbeating after finishing their bounded work until asked to
    // halt, so there is no other "done" event to wait on here.
    const max_polls: u32 = 400; // 2s bound at 5ms per poll
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    const metrics = sup.snapshotProcessMetrics();
    sup.stopProcess(std.testing.io);

    // Matches src/tickoni/tiles/payment_pipeline/runtime.zig's
    // syntheticPayment for event_count=32 with default policy/injection
    // config: offset 3 duplicates offset 1's idempotency key, offset 7
    // exceeds the default policy_limit_cents. See the equivalent
    // thread-mode assertions in
    // src/app/tickoni/supervisor.zig's "Supervisor starts and stops
    // Phase 0 pipeline without crashes" test for the shared expectation
    // shape (there event_count=16; here 32 to also exercise the deny
    // case at offset 7).
    try std.testing.expectEqual(@as(u64, 32), metrics.produced);
    try std.testing.expectEqual(@as(u64, 32), metrics.normalized);
    try std.testing.expectEqual(@as(u64, 0), metrics.invalid);
    try std.testing.expectEqual(@as(u64, 1), metrics.duplicates);
    try std.testing.expectEqual(@as(u64, 1), metrics.denied);
    try std.testing.expectEqual(@as(u64, 30), metrics.allowed);
    try std.testing.expectEqual(@as(u64, 32), metrics.audited);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
}

test "process_pipeline_integration: stopProcess prefers clean exit over transient stale classification" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(std.testing.io, &path_buf);
    const run_dir = path_buf[0..len];

    const topo = topologies.paymentPipelineProcess();
    var sup = try Supervisor.init(std.testing.allocator, topo);
    defer sup.deinit();

    const event_count: u64 = 8;
    try sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .heartbeat_interval_ns = 20 * std.time.ns_per_ms,
        .heartbeat_stale_after_ns = 1 * std.time.ns_per_ms,
        .tile_exe_path = "zig-out/bin/tickoni-supervisor",
    });

    const max_polls: u32 = 400;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (sup.snapshotProcessMetrics().audited >= event_count) break;
        util.process.sleepNanos(5 * std.time.ns_per_ms);
    }

    util.process.sleepNanos(5 * std.time.ns_per_ms);
    sup.stopProcess(std.testing.io);

    for (sup.monitor()) |h| {
        try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
        try std.testing.expectEqual(rt.tile.CrashReason.none, h.crashed_because);
    }
}
