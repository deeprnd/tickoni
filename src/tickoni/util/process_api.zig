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
    failed: ?i32,
};

/// The exact force operation accepted by the current process shim.
pub const TerminationAction = enum {
    kill,
};

pub const TerminateResult = union(enum) {
    accepted: TerminationAction,
    failed,
};

/// Requests forceful termination.  Acceptance is recorded only when the
/// native operation succeeds; it is not evidence that the child was reaped.
pub fn forceTerminate(pid: std.process.Child.Id) TerminateResult {
    const numeric_pid = os_api.c.processId(pid) catch return .failed;
    os_api.c.killProcess(numeric_pid) catch return .failed;
    return .{ .accepted = .kill };
}

pub fn outcomeFromTerm(term: std.process.Child.Term, force_terminated: bool) ProcessOutcome {
    // Classification policy: only evidence supports intentional termination.
    // A clean exit (0) after SIGKILL is a clean result. A non-zero exit is
    // crash evidence regardless of whether a kill was attempted. A signal is
    // direct evidence of a kill; an unknown exit code alone is not.
    return switch (term) {
        .exited => |code| if (code == 0) if (force_terminated) .force_terminated else .exited_ok else .{ .exited_code = code },
        .signal => if (force_terminated) .force_terminated else .crashed,
        .stopped => .stopped,
        .unknown => .unknown,
    };
}

pub fn tryReapNoHang(child: *std.process.Child) PollResult {
    const pid = child.id orelse return .detached;
    const numeric_pid = os_api.c.processId(pid) catch return .{ .failed = null };
    // Cross-platform reap options: NOHANG on POSIX, non-blocking on Windows.
    // Determined at comptime so std.posix is never referenced on Windows.
    const nohang: c_int = if (builtin.target.os.tag == .windows) 0 else 1;
    const r = os_api.processReap(@intCast(numeric_pid), nohang);

    return switch (r.pid) {
        -1 => blk: {
            // ECHILD means the child was already reaped — it detached.
            // Uses the os_api.c.eChildErrno() shim for platform-specific values.
            const is_echild: bool = r.err == os_api.c.eChildErrno();
            if (is_echild) {
                child.id = null;
                break :blk .detached;
            }
            break :blk .{ .failed = @as(?i32, r.err) };
        },
        0 => .running,
        else => blk: {
            break :blk switch (r.kind) {
                1 => terminal: {
                    child.id = null;
                    break :terminal .{ .reaped = .{ .exited = @intCast(r.exit_code) } };
                },
                2 => terminal: {
                    child.id = null;
                    break :terminal .{ .reaped = .{ .signal = @fromBackingInt(@intCast(@as(u32, @intCast(r.signal)))) } };
                },
                // STOPPED and unknown observations are nonterminal.  In
                // particular, never discard the child handle for either.
                3 => .{ .reaped = .{ .stopped = @fromBackingInt(@intCast(@as(u32, @intCast(r.stop_signal)))) } },
                else => .{ .reaped = .{ .unknown = 0 } },
            };
        },
    };
}
