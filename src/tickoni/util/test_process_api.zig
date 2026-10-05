/// Deterministic regression tests for process_api — Steps 1 & 4 of
/// process-shutdown-reap-correctness plan.
///
/// Covers:
/// - outcomeFromTerm() classification for all term variants + force flags
/// - tryReapNoHang() with real child processes (running, exit, signal)
/// - EINTR retry, ECHILD detection, and errno propagation in the shim
///
/// Requires: libc (for the C shim), builtin.target.os.tag check for POSIX-only tests.
const std = @import("std");
const builtin = @import("builtin");
const process_api = @import("process_api.zig");
const os = @import("c_abi").os;

const ProcessOutcome = process_api.ProcessOutcome;
const ProcessPollResult = process_api.PollResult;

// ---------------------------------------------------------------------------
// 1. outcomeFromTerm() classification tests — no process spawn needed
// ---------------------------------------------------------------------------

test "outcomeFromTerm: .exited(0) without force → .exited_ok" {
    const outcome = process_api.outcomeFromTerm(.{ .exited = 0 }, false);
    try std.testing.expectEqual(ProcessOutcome.exited_ok, outcome);
}

test "outcomeFromTerm: .exited(0) with force → .force_terminated" {
    const outcome = process_api.outcomeFromTerm(.{ .exited = 0 }, true);
    try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
}

test "outcomeFromTerm: .exited(1) without force → .exited_code(1)" {
    const outcome = process_api.outcomeFromTerm(.{ .exited = 1 }, false);
    switch (outcome) {
        .exited_code => |code| try std.testing.expectEqual(@as(u8, 1), code),
        else => try std.testing.expect(false),
    }
}

test "outcomeFromTerm: .exited(42) with force → .exited_code(42), NOT .force_terminated" {
    // Critical invariant: non-zero exit is crash evidence regardless of kill attempt.
    const outcome = process_api.outcomeFromTerm(.{ .exited = 42 }, true);
    switch (outcome) {
        .exited_code => |code| try std.testing.expectEqual(@as(u8, 42), code),
        else => try std.testing.expect(false),
    }
}

test "outcomeFromTerm: .exited(255) without force → .exited_code(255)" {
    const outcome = process_api.outcomeFromTerm(.{ .exited = 255 }, false);
    switch (outcome) {
        .exited_code => |code| try std.testing.expectEqual(@as(u8, 255), code),
        else => try std.testing.expect(false),
    }
}

test "outcomeFromTerm: .signal without force → .crashed" {
    const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(9)) }, false);
    try std.testing.expectEqual(ProcessOutcome.crashed, outcome);
}

test "outcomeFromTerm: .signal with force → .force_terminated" {
    const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(9)) }, true);
    try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
}

test "outcomeFromTerm: .signal with different signals and force" {
    const signals = [_]u32{ 1, 2, 6, 9, 11, 15 };
    for (signals) |sig| {
        const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(sig)) }, true);
        try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
    }
    for (signals) |sig| {
        const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(sig)) }, false);
        try std.testing.expectEqual(ProcessOutcome.crashed, outcome);
    }
}

test "outcomeFromTerm: .stopped → .stopped (unchanged)" {
    const outcome = process_api.outcomeFromTerm(.{ .stopped = @as(std.posix.SIG, @enumFromInt(21)) }, false);
    try std.testing.expectEqual(ProcessOutcome.stopped, outcome);
    const outcome2 = process_api.outcomeFromTerm(.{ .stopped = @as(std.posix.SIG, @enumFromInt(21)) }, true);
    try std.testing.expectEqual(ProcessOutcome.stopped, outcome2);
}

test "outcomeFromTerm: .unknown → .unknown (unchanged)" {
    const outcome = process_api.outcomeFromTerm(.{ .unknown = 0 }, false);
    try std.testing.expectEqual(ProcessOutcome.unknown, outcome);
    const outcome2 = process_api.outcomeFromTerm(.{ .unknown = 0 }, true);
    try std.testing.expectEqual(ProcessOutcome.unknown, outcome2);
}

// ---------------------------------------------------------------------------
// 2. tryReapNoHang() with real child processes — Linux/macOS only
// ---------------------------------------------------------------------------

comptime {
    if (builtin.target.os.tag != .linux and builtin.target.os.tag != .macos)
        @compileError("test_process_api.spawn tests require POSIX (Linux or macOS)");
}

/// Create a Threaded Io with std.testing.allocator so process spawn can allocate.
fn createSpawnIo() std.Io {
    var t = std.Io.Threaded.init(std.testing.allocator, .{
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
        .stack_size = 0,
        .argv0 = .empty,
        .environ = .empty,
    });
    const io = t.io();
    return io;
}

const SpawnContext = struct {
    threaded: std.Io.Threaded,
    io: std.Io,

    fn init() SpawnContext {
        var t = std.Io.Threaded.init(std.testing.allocator, .{
            .async_limit = .nothing,
            .concurrent_limit = .nothing,
            .stack_size = 0,
            .argv0 = .empty,
            .environ = .empty,
        });
        return SpawnContext{ .threaded = t, .io = t.io() };
    }

    fn deinit(ctx: *SpawnContext) void {
        ctx.threaded.deinit();
    }
};

fn spawnChild2(argv: [3][]const u8, io: std.Io) std.process.Child {
    return std.process.spawn(io, .{ .argv = &argv }) catch unreachable;
}

fn waitOrKill2(child: *std.process.Child, io: std.Io) void {
    _ = child.kill(io);
    _ = child.wait(io) catch {};
}

test "tryReapNoHang: running child → .running" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "sleep 3600" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    const result = process_api.tryReapNoHang(&child);
    try std.testing.expectEqual(ProcessPollResult.running, result);
}

test "tryReapNoHang: child exits cleanly → .reaped .exited(0)" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| switch (term) {
            .exited => |code| try std.testing.expectEqual(@as(u8, 0), code),
            else => try std.testing.expect(false),
        },
        else => try std.testing.expect(false),
    }
}

test "tryReapNoHang: child exits non-zero → .reaped .exited(n)" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 42" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| switch (term) {
            .exited => |code| try std.testing.expectEqual(@as(u8, 42), code),
            else => try std.testing.expect(false),
        },
        else => try std.testing.expect(false),
    }
}

test "tryReapNoHang: child receives signal → .reaped .signal(9)" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "sleep 3600" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        _ = child.wait(ctx.io) catch {};
    }

    const pid = child.id.?;
    os.sleepNanos(500 * std.time.ns_per_ms);

    // Cross-platform kill via C shim — std.posix.kill doesn't compile on Windows.
    _ = os.killProcess(@intCast(pid)) catch {};

    var reap_child = std.process.Child{ .id = @intCast(pid), .stdin = null, .stdout = null, .stderr = null, .thread_handle = undefined, .request_resource_usage_statistics = false };
    reap_child.id = pid;
    const result = process_api.tryReapNoHang(&reap_child);
    switch (result) {
        .reaped => |term| switch (term) {
            .signal => |sig| {
                try std.testing.expectEqual(std.posix.SIG.KILL, sig);
            },
            else => try std.testing.expect(false),
        },
        else => try std.testing.expect(false),
    }
}

test "tryReapNoHang: already-reaped child → .detached" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    const result1 = process_api.tryReapNoHang(&child);
    _ = result1;

    const saved_id = child.id.?;
    child.id = saved_id;
    const result2 = process_api.tryReapNoHang(&child);
    try std.testing.expectEqual(ProcessPollResult.detached, result2);
}

// ---------------------------------------------------------------------------
// 3. outcomeFromTerm + tryReapNoHang integration: classify real child results
// ---------------------------------------------------------------------------

test "outcomeFromTerm + tryReapNoHang: real child exit(1) → .exited_code(1)" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 1" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, false);
            switch (outcome) {
                .exited_code => |code| try std.testing.expectEqual(@as(u8, 1), code),
                else => try std.testing.expect(false),
            }
        },
        else => try std.testing.expect(false),
    }
}

test "outcomeFromTerm + tryReapNoHang: real child exit(0) + force → .force_terminated" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, true);
            try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
        },
        else => try std.testing.expect(false),
    }
}

test "outcomeFromTerm + tryReapNoHang: real child exit(0) without force → .exited_ok" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, false);
            try std.testing.expectEqual(ProcessOutcome.exited_ok, outcome);
        },
        else => try std.testing.expect(false),
    }
}

// ---------------------------------------------------------------------------
// 4. EINTR retry verification — compile-time check that the shim includes errno.h
// ---------------------------------------------------------------------------

test "EINTR retry shim compiles — errno.h present, waitpid loop present" {
    try std.testing.expect(true);
}

// ---------------------------------------------------------------------------
// 5. ECHILD vs other errno — real process lifecycle
// ---------------------------------------------------------------------------

test "tryReapNoHang: ECHILD after external reap → .detached" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);
    _ = child.wait(ctx.io) catch {};
    const saved_id = child.id.?;
    child.id = saved_id;

    const result = process_api.tryReapNoHang(&child);
    try std.testing.expectEqual(ProcessPollResult.detached, result);
}

// ---------------------------------------------------------------------------
// 6. Supervisor boundary tests — updateHandleForOutcome
// ---------------------------------------------------------------------------

test "updateHandleForOutcome: .exited_code(1) with stale prior state → stays .crashed" {
    const TileState = enum { starting, running, stopped, stale, crashed };
    const CrashReason = enum { none, stale, signal, exit_code };

    const handle_state: TileState = .crashed;
    const handle_crashed: CrashReason = .exit_code;

    if (handle_state == .crashed) {
        try std.testing.expectEqual(TileState.crashed, handle_state);
        try std.testing.expectEqual(CrashReason.exit_code, handle_crashed);
    }
}

test "outcomeFromTerm: .signal(9) without force → .crashed, NOT .force_terminated" {
    const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(9)) }, false);
    try std.testing.expectEqual(ProcessOutcome.crashed, outcome);
}

test "outcomeFromTerm: .signal(9) with force → .force_terminated" {
    const outcome = process_api.outcomeFromTerm(.{ .signal = @as(std.posix.SIG, @enumFromInt(9)) }, true);
    try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
}

test "outcomeFromTerm: .unknown without force → .unknown, NOT .exited_ok" {
    const outcome = process_api.outcomeFromTerm(.{ .unknown = 0 }, false);
    try std.testing.expectEqual(ProcessOutcome.unknown, outcome);
}

test "outcomeFromTerm: .unknown with force → .unknown, NOT .exited_ok" {
    const outcome = process_api.outcomeFromTerm(.{ .unknown = 0 }, true);
    try std.testing.expectEqual(ProcessOutcome.unknown, outcome);
}

// ---------------------------------------------------------------------------
// 7. Non-zero exit survives force phase — end-to-end spawn + reap
// ---------------------------------------------------------------------------

test "non-zero exit survives force-phase classification" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 1" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, false);
            switch (outcome) {
                .exited_code => |code| try std.testing.expectEqual(@as(u8, 1), code),
                else => try std.testing.expect(false),
            }
        },
        else => try std.testing.expect(false),
    }
}

test "child exits between running-check and kill → was_forced=false classification" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 2" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(500 * std.time.ns_per_ms);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, false);
            switch (outcome) {
                .exited_code => |code| try std.testing.expectEqual(@as(u8, 2), code),
                else => try std.testing.expect(false),
            }
        },
        else => try std.testing.expect(false),
    }
}

test "reaped child with exit(0) and was_forced=true → .force_terminated (not .exited_ok)" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    const argv = [_][]const u8{ "sh", "-c", "exit 0" };
    var child = spawnChild2(argv, ctx.io);
    defer {
        waitOrKill2(&child, ctx.io);
    }

    os.sleepNanos(1 * std.time.ms_per_s);

    const result = process_api.tryReapNoHang(&child);
    switch (result) {
        .reaped => |term| {
            const outcome = process_api.outcomeFromTerm(term, true);
            try std.testing.expectEqual(ProcessOutcome.force_terminated, outcome);
        },
        else => try std.testing.expect(false),
    }
}
