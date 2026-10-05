/// Cross-platform OS abstraction — re-exports c_abi.os shim.
/// All platform-specific code is hidden behind src/tickoni/c_abi/shim/os.c.
const std = @import("std");
pub const c = @import("c_abi").os;

pub fn monotonicNanos() i64 {
    return c.monotonicNanos();
}
pub fn sleepNanos(ns: u64) void {
    c.sleepNanos(ns);
}
pub fn selfExePath(buf: []u8) ![]const u8 {
    return c.selfExePath(buf);
}
pub fn parentPid(pid: c_int) c_int {
    return c.parentPid(pid) catch -1;
}
pub fn kill(pid: c_int) void {
    c.killProcess(@intCast(pid));
}

pub fn processPoll(pid: c_int) c_int {
    return c.processPoll(pid);
}
pub fn write(fd: c_int, buf: []const u8) usize {
    return c.writeFd(@intCast(fd), buf);
}

pub fn isatty(fd: c_int) bool {
    return c.isTerminal(@intCast(fd)) != 0;
}

pub fn fflush() void {
    c.flushStderr();
}

pub fn setEnv(name: []const u8, value: []const u8) void {
    _ = c.setEnv(name.ptr, value.ptr, 1);
}

pub fn getEnv(name: []const u8) ?[]const u8 {
    const raw = c.getenv(name.ptr) orelse return null;
    // The C shim returns a null-terminated buffer.
    // sliceTo handles [*:0] directly without manual null scan.
    return std.mem.sliceTo(raw, 0);
}

pub fn getAffinity(pid: c_int, cpu_set: []u8) !void {
    try c.getAffinity(pid, cpu_set);
}

pub fn setAffinity(pid: c_int, cpu_set: []const u8) !void {
    try c.setAffinity(pid, cpu_set);
}

pub const tk_process_reap_result = c.tk_process_reap_result;

pub fn processReap(pid: c_int, options: c_int) tk_process_reap_result {
    return c.processReap(pid, options);
}
