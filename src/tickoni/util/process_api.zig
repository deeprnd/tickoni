/// Process reaping API — cross-platform via C shim.
///
/// All platform-specific reaping logic lives in `os.c` behind
/// `#if FD_HAS_LINUX` / `#elif FD_HAS_WINDOWS` guards. Zig callers
/// use `processReap()` uniformly.
const std = @import("std");
const os_api = @import("os_api.zig");

pub const ProcessOutcome = union(enum) {
    exited_ok,
    exited_code: u8,
    crashed,
    force_terminated,
    stopped,
    unknown,
};

pub const PollResult = union(enum) {
    running,
    reaped: std.process.Child.Term,
    detached,
    failed,
};

pub fn forceTerminate(pid: std.process.Child.Id) bool {
    return termProcess(pid);
}

pub fn termProcess(pid: std.process.Child.Id) bool {
    // Unified: processId() converts HANDLE→PID on Windows, passes through on POSIX.
    const numeric_pid = os_api.c.processId(pid) catch return false;
    _ = os_api.c.killProcess(numeric_pid) catch {};
    return true;
}

pub fn forceKillProcess(pid: std.process.Child.Id) void {
    _ = termProcess(pid);
}

pub fn outcomeFromTerm(term: std.process.Child.Term, force_terminated: bool) ProcessOutcome {
    // Never mask a real exit code with .force_terminated — if the child
    // already exited (cleanly or with a non-zero code), that outcome is the
    // ground truth.  force_terminated only matters for signals / unknown
    // where the kill is what caused the termination.
    return switch (term) {
        .exited => |code| if (code == 0) .exited_ok else .{ .exited_code = code },
        .signal => if (force_terminated) .force_terminated else .crashed,
        .stopped => .stopped,
        .unknown => if (force_terminated) .force_terminated else .unknown,
    };
}

pub fn tryReapNoHang(child: *std.process.Child) PollResult {
    const pid = child.id orelse return .detached;
    const numeric_pid = os_api.c.processId(pid) catch return .failed;
    const r = os_api.processReap(@intCast(numeric_pid), std.posix.W.NOHANG);

    return switch (r.pid) {
        -1 => .failed,
        0 => .running,
        else => blk: {
            child.id = null;
            break :blk switch (r.kind) {
                1 => .{ .reaped = .{ .exited = @intCast(r.exit_code) } },
                2 => .{ .reaped = .{ .signal = @fromBackingInt(@intCast(@as(u32, @intCast(r.signal)))) } },
                3 => .{ .reaped = .{ .stopped = @fromBackingInt(@intCast(@as(u32, @intCast(r.stop_signal)))) } },
                else => .{ .reaped = .{ .unknown = 0 } },
            };
        },
    };
}
