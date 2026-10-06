const std = @import("std");
const builtin = @import("builtin");
const process_api = @import("process_api.zig");
const os = @import("c_abi").os;

fn expectOutcome(expected: process_api.ProcessOutcome, actual: process_api.ProcessOutcome) !void {
    try std.testing.expectEqualDeep(expected, actual);
}

test "classify applies the complete exact-action table" {
    try expectOutcome(.clean_stop, process_api.classify(.{ .exited = 0 }, null));
    try expectOutcome(.clean_stop, process_api.classify(.{ .exited = 0 }, .{ .exit_code = 7 }));
    try expectOutcome(.{ .crash_exit = 7 }, process_api.classify(.{ .exited = 7 }, null));
    try expectOutcome(.intentional_termination, process_api.classify(.{ .exited = 7 }, .{ .exit_code = 7 }));
    try expectOutcome(.{ .crash_exit = 7 }, process_api.classify(.{ .exited = 7 }, .{ .exit_code = 8 }));
    try expectOutcome(.{ .crash_exit = 0x12345678 }, process_api.classify(.{ .exited = 0x12345678 }, null));
    try expectOutcome(.{ .crash_signal = 9 }, process_api.classify(.{ .signaled = 9 }, null));
    try expectOutcome(.intentional_termination, process_api.classify(.{ .signaled = 9 }, .{ .signal = 9 }));
    try expectOutcome(.{ .crash_signal = 15 }, process_api.classify(.{ .signaled = 15 }, .{ .signal = 9 }));
    try expectOutcome(.{ .nonterminal_stop = 19 }, process_api.classify(.{ .stopped = 19 }, .{ .signal = 19 }));
}

test "C process ABI preserves widths and alignment" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(os.ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(os.ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(os.ProcessTerminateResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(os.ProcessTerminateResult));
}

test "reap shim retries EINTR twice before returning exit 7" {
    os.processTestEintrThenExit(7);
    const result = os.processReapNoHang(1);
    try std.testing.expectEqual(@as(u32, @backingInt(os.ProcessReapKind.exited)), result.kind);
    try std.testing.expectEqual(@as(u32, 7), result.exit_code);
    try std.testing.expectEqual(@as(u32, 3), os.processTestNativeCallCount());
}

const SpawnContext = struct {
    threaded: std.Io.Threaded,

    fn init() SpawnContext {
        return .{ .threaded = std.Io.Threaded.init(std.testing.allocator, .{
            .async_limit = .nothing,
            .concurrent_limit = .nothing,
            .stack_size = 0,
            .argv0 = .empty,
            .environ = .empty,
        }) };
    }

    fn deinit(self: *SpawnContext) void {
        self.threaded.deinit();
    }

    fn io(self: *SpawnContext) std.Io {
        return self.threaded.io();
    }
};

fn spawnLongLived(io: std.Io) !std.process.Child {
    if (builtin.os.tag == .windows) {
        const argv = [_][]const u8{ "cmd.exe", "/C", "ping -n 31 127.0.0.1 >NUL" };
        return std.process.spawn(io, .{ .argv = &argv });
    }
    const argv = [_][]const u8{ "sh", "-c", "sleep 30" };
    return std.process.spawn(io, .{ .argv = &argv });
}

fn spawnExit(io: std.Io, code: u8) !std.process.Child {
    var command_buf: [32]u8 = undefined;
    const command = try std.fmt.bufPrint(&command_buf, "exit {d}", .{code});
    if (builtin.os.tag == .windows) {
        const argv = [_][]const u8{ "cmd.exe", "/C", command };
        return std.process.spawn(io, .{ .argv = &argv });
    }
    const argv = [_][]const u8{ "sh", "-c", command };
    return std.process.spawn(io, .{ .argv = &argv });
}

fn cleanupChild(child: *std.process.Child, io: std.Io) void {
    if (child.id != null) child.kill(io);
}

fn waitForObservation(child: *std.process.Child) !process_api.Observation {
    const deadline = os.monotonicNanos() + 2 * std.time.ns_per_s;
    while (os.monotonicNanos() < deadline) {
        switch (process_api.tryReapNoHang(child)) {
            .running => os.sleepNanos(std.time.ns_per_ms),
            .observation => |observation| return observation,
            .no_child => return error.UnexpectedNoChild,
            .failed => return error.ReapFailed,
        }
    }
    return error.ReapTimedOut;
}

test "tryReapNoHang returns running promptly without losing ownership" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();
    var child = try spawnLongLived(ctx.io());
    defer cleanupChild(&child, ctx.io());

    const before = os.monotonicNanos();
    const result = process_api.tryReapNoHang(&child);
    const elapsed = os.monotonicNanos() - before;

    try std.testing.expectEqual(process_api.PollResult.running, result);
    try std.testing.expect(child.id != null);
    try std.testing.expect(elapsed < 250 * std.time.ns_per_ms);
}

test "tryReapNoHang preserves clean and nonzero exits" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();

    var clean = try spawnExit(ctx.io(), 0);
    defer cleanupChild(&clean, ctx.io());
    try std.testing.expectEqualDeep(process_api.Observation{ .exited = 0 }, try waitForObservation(&clean));
    try std.testing.expect(clean.id == null);

    var failed = try spawnExit(ctx.io(), 42);
    defer cleanupChild(&failed, ctx.io());
    try std.testing.expectEqualDeep(process_api.Observation{ .exited = 42 }, try waitForObservation(&failed));
    try std.testing.expect(failed.id == null);
}

test "tryReapNoHang returns no_child for an empty child record" {
    var child = std.process.Child{
        .id = null,
        .thread_handle = if (builtin.os.tag == .windows) undefined else {},
        .stdin = null,
        .stdout = null,
        .stderr = null,
        .request_resource_usage_statistics = false,
    };
    try std.testing.expectEqual(process_api.PollResult.no_child, process_api.tryReapNoHang(&child));
}

test "forceTerminate records an accepted action before the matching terminal observation" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();
    var child = try spawnLongLived(ctx.io());
    defer cleanupChild(&child, ctx.io());

    const id = child.id orelse return error.MissingChildId;
    const action = switch (process_api.forceTerminate(id)) {
        .accepted => |accepted| accepted,
        .failed => return error.ForceTerminateFailed,
    };
    const observation = try waitForObservation(&child);

    try expectOutcome(.intentional_termination, process_api.classify(observation, action));
    try std.testing.expect(child.id == null);
}

test "forceTerminate preserves a native failure without recording an action" {
    var ctx = SpawnContext.init();
    defer ctx.deinit();
    var child = try spawnLongLived(ctx.io());
    defer cleanupChild(&child, ctx.io());

    os.processTestForceFailure(@backingInt(process_api.ErrorCategory.access_denied), 5);
    const id = child.id orelse return error.MissingChildId;
    const result = process_api.forceTerminate(id);

    switch (result) {
        .accepted => return error.UnexpectedForceSuccess,
        .failed => |err| {
            try std.testing.expectEqual(process_api.ErrorCategory.access_denied, err.category);
            try std.testing.expectEqual(@as(u32, 5), err.native_code);
        },
    }
    try std.testing.expect(child.id != null);
}
