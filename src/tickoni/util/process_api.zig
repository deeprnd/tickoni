/// Process reaping API — cross-platform via C shim.
///
/// All platform-specific reaping logic lives in `os.c` behind
/// `#if FD_HAS_LINUX` / `#elif FD_HAS_WINDOWS` guards. Zig callers
/// use `processReap()` uniformly.
const std = @import("std");
const builtin = @import("builtin");
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
    os_api.c.killProcess(numeric_pid) catch |err| {
        std.log.debug("process_api.termProcess: kill returned {any}", .{err});
    };
    return true;
}

pub fn forceKillProcess(pid: std.process.Child.Id) void {
    _ = termProcess(pid);
}

pub fn outcomeFromTerm(term: std.process.Child.Term, force_terminated: bool) ProcessOutcome {
    // When force_terminated is true, we already sent SIGKILL (or equivalent).
    // Any exit — even non-zero — is a consequence of that forced termination,
    // not a real crash.  The TOCTOU race between reap-check (.running) and
    // SIGKILL means the tile may have already exited (cleanly after observing
    // HALT, or mid-cleanup with a non-zero code) before the kill lands.
    return switch (term) {
        .exited => |code| if (code == 0) .exited_ok else if (force_terminated) .force_terminated else .{ .exited_code = code },
        .signal => if (force_terminated) .force_terminated else .crashed,
        .stopped => .stopped,
        .unknown => if (force_terminated) .force_terminated else .unknown,
    };
}

pub fn tryReapNoHang(child: *std.process.Child) PollResult {
    const pid = child.id orelse return .detached;
    const numeric_pid = os_api.c.processId(pid) catch return .failed;
    // NOHANG=1 on POSIX; 0 on Windows (WaitForSingleObject semantics use
    // options&1==0 → block, options&1!=0 → non-blocking).  Cross-platform
    // via comptime so std.posix is never referenced on Windows.
    const nohang: c_int = if (builtin.os.tag == .windows) 0 else 1;
    const r = os_api.processReap(@intCast(numeric_pid), nohang);

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
