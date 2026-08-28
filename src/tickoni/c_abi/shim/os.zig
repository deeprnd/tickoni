/// Zig extern declarations for os.c cross-platform OS operations shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
pub const c = struct {
    pub extern fn tk_monotonic_nanos() i64;
    pub extern fn tk_sleep_nanos(ns: u64) void;
    pub extern fn tk_self_exe_path(buf: [*]u8, buf_len: usize) c_int;
    pub extern fn tk_parent_pid(pid: c_int) c_int;
    pub extern fn tk_kill_process(pid: c_int) c_int;
    pub extern fn tk_write(fd: c_int, buf: [*]const u8, count: usize) usize;
    pub extern fn tk_isatty(fd: c_int) c_int;
    pub extern fn tk_fflush() void;
    pub extern fn tk_setenv(name: [*]const u8, value: [*]const u8, overwrite: c_int) c_int;
    pub extern fn tk_getenv(name: [*]const u8) [*:0]const u8;
};

pub fn monotonicNanos() i64 {
    return c.tk_monotonic_nanos();
}

pub fn sleepNanos(ns: u64) void {
    c.tk_sleep_nanos(ns);
}

pub fn selfExePath(buf: []u8) ![]const u8 {
    const n = c.tk_self_exe_path(buf.ptr, @intCast(buf.len));
    if (n < 0) return error.SelfExePathFailed;
    return buf[0..@as(usize, @intCast(n))];
}

pub fn parentPid(pid: c_int) !c_int {
    const r = c.tk_parent_pid(pid);
    if (r < 0) return error.PPidNotFound;
    return r;
}

pub fn killProcess(pid: c_int) void {
    _ = c.tk_kill_process(pid);
}

pub fn write(fd: c_int, buf: []const u8) usize {
    return c.tk_write(fd, buf.ptr, buf.len);
}

pub fn isatty(fd: c_int) c_int {
    return c.tk_isatty(fd);
}

pub fn fflush() void {
    c.tk_fflush();
}

pub fn setenv(name: [*]const u8, value: [*]const u8, overwrite: c_int) c_int {
    return c.tk_setenv(name, value, overwrite);
}

pub fn tk_getenv(name: [*]const u8) ?[*:0]const u8 {
    return c.tk_getenv(name);
}
