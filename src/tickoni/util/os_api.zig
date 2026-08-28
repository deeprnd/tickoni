/// Cross-platform OS abstraction — re-exports c_abi.os shim.
/// All platform-specific code is hidden behind src/tickoni/c_abi/shim/os.c.
const builtin = @import("builtin");
const std = @import("std");
pub const c = @import("c_abi").os;

pub const ProcessId = if (builtin.os.tag == .windows) u32 else std.posix.pid_t;
pub const FileDescriptor = if (builtin.os.tag == .windows) i32 else std.posix.fd_t;

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
pub fn kill(pid: ProcessId) void {
    c.killProcess(@intCast(pid));
}
pub fn write(fd: FileDescriptor, buf: []const u8) usize {
    return c.write(@intCast(fd), buf);
}

pub fn isatty(fd: FileDescriptor) bool {
    return c.isatty(@intCast(fd)) != 0;
}

pub fn fflush() void {
    c.fflush();
}

pub fn setEnv(name: []const u8, value: []const u8) void {
    _ = c.setenv(name.ptr, value.ptr, 1);
}

pub fn getEnv(name: []const u8) ?[]const u8 {
    const raw: ?[*]const u8 = @ptrCast(c.tk_getenv(name.ptr));
    if (raw == null) return null;
    const raw_ptr = raw.?;
    // Find the null terminator and return a slice.
    // The C shim (getenv / _getenv_s) returns a pointer to a stable
    // buffer — no heap allocation needed.
    var len: usize = 0;
    while (raw_ptr[len] != 0) : (len += 1) {}
    return raw_ptr[0..len];
}
