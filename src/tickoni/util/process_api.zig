const builtin = @import("builtin");
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

pub fn forceTerminate(pid: std.process.Child.Id) void {
    termProcess(pid);
}

pub fn termProcess(pid: std.process.Child.Id) void {
    // Unified: processId() converts HANDLE→PID on Windows, passes through on POSIX.
    const numeric_pid = os_api.c.processId(pid) catch return;
    os_api.c.killProcess(numeric_pid);
}

pub fn forceKillProcess(pid: std.process.Child.Id) void {
    termProcess(pid);
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
    if (builtin.os.tag == .windows) {
        const numeric_pid = os_api.c.processId(pid) catch return .failed;
        const status = os_api.processPoll(numeric_pid);
        if (status == -1) return .running;
        if (status < 0) return .failed;
        child.id = null;
        if (status == 255) return .{ .reaped = .{ .signal = @fromBackingInt(@intCast(9)) } };
        return .{ .reaped = .{ .exited = @intCast(status) } };
    }

    var status: c_int = 0;
    while (true) {
        const rc = std.posix.system.waitpid(pid, &status, std.posix.W.NOHANG);
        switch (std.posix.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return .running;
                child.id = null;
                return .{ .reaped = termFromWaitStatus(@bitCast(@as(c_uint, @intCast(status)))) };
            },
            .INTR => continue,
            .CHILD => {
                child.id = null;
                return .detached;
            },
            else => return .failed,
        }
    }
}

fn termFromWaitStatus(status: u32) std.process.Child.Term {
    return if (std.posix.W.IFEXITED(status))
        .{ .exited = std.posix.W.EXITSTATUS(status) }
    else if (std.posix.W.IFSIGNALED(status))
        .{ .signal = std.posix.W.TERMSIG(status) }
    else if (std.posix.W.IFSTOPPED(status))
        .{ .stopped = std.posix.W.STOPSIG(status) }
    else
        .{ .unknown = status };
}
