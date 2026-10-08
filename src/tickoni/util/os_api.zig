/// Cross-platform OS abstraction — re-exports c_abi.os shim.
/// All platform-specific code is hidden behind src/tickoni/c_abi/shim/os.c.
const std = @import("std");
const c = @import("c_abi").os;

pub const ProcessReapResult = c.ProcessReapResult;
pub const ProcessTerminateResult = c.ProcessTerminateResult;

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

pub fn processToken(id: std.process.Child.Id) usize {
    return c.processToken(id);
}

pub fn processDiagnosticPid(id: std.process.Child.Id) u32 {
    return c.processDiagnosticPid(id);
}

pub fn processReapNoHang(process_token: usize) ProcessReapResult {
    return c.processReapNoHang(process_token);
}

pub fn processForceTerminate(process_token: usize) ProcessTerminateResult {
    return c.processForceTerminate(process_token);
}

pub fn processRelease(child: *std.process.Child) void {
    c.processRelease(child);
}
