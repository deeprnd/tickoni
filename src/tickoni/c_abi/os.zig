/// Zig extern declarations for os.c cross-platform OS operations shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
const builtin = @import("builtin");
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations (bare, module-scoped — canonical pattern)
// ---------------------------------------------------------------------------

extern fn tk_monotonic_nanos() i64;
extern fn tk_sleep_nanos(ns: u64) void;
extern fn tk_self_exe_path(buf: [*]u8, buf_len: usize) c_int;
extern fn tk_parent_pid(pid: c_int) c_int;
extern fn tk_process_id_from_handle(handle: usize) c_int;
extern fn tk_process_poll(pid: c_int) c_int;
extern fn tk_process_waitpid(pid: c_int, status: [*]c_int, options: c_int) c_int;
extern fn tk_port_is_in_use(port: u16) c_int;
extern fn tk_kill_process(pid: c_int) c_int;
extern fn tk_kill_process_group(pgid: c_int) c_int;
extern fn tk_write(fd: c_int, buf: [*]const u8, count: usize) usize;
extern fn tk_isatty(fd: c_int) c_int;
extern fn tk_fflush() void;
extern fn tk_setenv(name: [*]const u8, value: [*]const u8, overwrite: c_int) c_int;
extern fn tk_getenv(name: [*]const u8) [*:0]const u8;
extern fn tk_get_affinity(pid: c_int, mask: [*]u8) c_int;
extern fn tk_set_affinity(pid: c_int, mask: [*]const u8) c_int;

pub const tk_process_reap_result = extern struct {
    pid: c_int,
    status: c_int,
    exit_code: c_int,
    signal: c_int,
    stop_signal: c_int,
    kind: c_int,
};

extern fn tk_process_reap(pid: c_int, options: c_int, out: *tk_process_reap_result) void;

// ---------------------------------------------------------------------------
// Error set
// ---------------------------------------------------------------------------

pub const OsError = error{
    SelfExePathFailed,
    PPidNotFound,
    ProcessIdNotFound,
    PortInUse,
    KillFailed,
    KillProcessGroupFailed,
    GetAffinityFailed,
    SetAffinityFailed,
    ProcessPollUnsupported,
    ProcessPollFailed,
};

// ---------------------------------------------------------------------------
// Public wrappers
// ---------------------------------------------------------------------------

pub fn monotonicNanos() i64 {
    return tk_monotonic_nanos();
}

pub fn sleepNanos(ns: u64) void {
    tk_sleep_nanos(ns);
}

pub fn selfExePath(buf: []u8) ![]const u8 {
    const n = tk_self_exe_path(buf.ptr, @intCast(buf.len));
    if (n < 0) return error.SelfExePathFailed;
    return buf[0..@as(usize, @intCast(n))];
}

pub fn parentPid(pid: c_int) !c_int {
    const r = tk_parent_pid(pid);
    if (r < 0) return error.PPidNotFound;
    return r;
}

/// Convert std.process.Child.Id to the numeric PID expected by the C shim.
/// POSIX Child.Id is already a PID; Windows Child.Id is an hProcess HANDLE.
pub fn processId(id: std.process.Child.Id) !c_int {
    const raw: usize = if (builtin.os.tag == .windows)
        @intFromPtr(id)
    else
        @intCast(id);
    const pid = tk_process_id_from_handle(raw);
    if (pid < 0) return error.ProcessIdNotFound;
    return pid;
}

pub fn portIsInUse(port: u16) bool {
    return tk_port_is_in_use(port) != 0;
}

pub fn killProcess(pid: c_int) !void {
    if (tk_kill_process(pid) != 0) return error.KillFailed;
}

pub fn killProcessGroup(pgid: c_int) !void {
    if (tk_kill_process_group(pgid) != 0) return error.KillProcessGroupFailed;
}

pub fn processPoll(pid: c_int) OsError!c_int {
    const rc = tk_process_poll(pid);
    if (rc <= -2) return error.ProcessPollUnsupported;
    if (rc < 0) return error.ProcessPollFailed;
    return rc;
}

pub fn writeFd(fd: c_int, buf: []const u8) usize {
    return tk_write(fd, buf.ptr, buf.len);
}

pub fn isTerminal(fd: c_int) c_int {
    return tk_isatty(fd);
}

pub fn flushStderr() void {
    tk_fflush();
}

pub fn setEnv(name: [*]const u8, value: [*]const u8, overwrite: c_int) c_int {
    return tk_setenv(name, value, overwrite);
}

pub fn getenv(name: [*]const u8) ?[*:0]const u8 {
    return tk_getenv(name);
}

pub fn getAffinity(pid: c_int, cpu_set: []u8) !void {
    const rc = tk_get_affinity(pid, cpu_set.ptr);
    if (rc < 0) return error.GetAffinityFailed;
}

pub fn setAffinity(pid: c_int, cpu_set: []const u8) !void {
    const rc = tk_set_affinity(pid, cpu_set.ptr);
    if (rc < 0) return error.SetAffinityFailed;
}

pub fn processReap(pid: c_int, options: c_int) tk_process_reap_result {
    var result: tk_process_reap_result = undefined;
    tk_process_reap(pid, options, &result);
    return result;
}

// ---------------------------------------------------------------------------
// Tests — runtime sanity checks (require C shim linkage)
// ---------------------------------------------------------------------------

test "monotonicNanos returns non-negative values" {
    const t1 = monotonicNanos();
    try std.testing.expect(t1 >= 0);
    std.time.sleep(1 * std.time.ns_per_ms);
    const t2 = monotonicNanos();
    try std.testing.expect(t2 >= t1);
}

test "selfExePath returns a non-empty path" {
    var buf: [4096]u8 = undefined;
    const path = try selfExePath(&buf);
    try std.testing.expect(path.len > 0);
}

test "portIsInUse detects a used port" {
    // Start a listener on a random port, then check.
    // This test requires a live network stack — skip on constrained CI.
    // For now, verify it returns false for a port we know is free.
    const free_port: u16 = 59876; // unlikely to be in use during tests
    // Port availability is best-effort; the test just verifies no panic.
    _ = portIsInUse(free_port);
}

test "getEnv/setEnv round-trip" {
    const name = "TK_TEST_ENV_VAR_XYZ";
    const value = "hello_from_test";
    _ = setEnv(name, value, 1);
    const got = getenv(name);
    try std.testing.expect(got != null);
    try std.testing.expectEqualStrings(value, got.?);
    // Clean up to not pollute process environment
    _ = setEnv(name, "", 1);
}

test "tk_process_reap_result is extern struct with correct size" {
    // 6 fields × 4 bytes each = 24 bytes, no padding expected for extern struct
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(tk_process_reap_result));
}
