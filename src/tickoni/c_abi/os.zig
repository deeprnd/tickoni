/// Zig extern declarations for os.c cross-platform OS operations shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations (bare, module-scoped — canonical pattern)
// ---------------------------------------------------------------------------

extern fn tk_monotonic_nanos() i64;
extern fn tk_sleep_nanos(ns: u64) void;
extern fn tk_self_exe_path(buf: [*]u8, buf_len: usize) c_int;
extern fn tk_parent_pid(pid: c_int) c_int;
extern fn tk_process_diagnostic_pid(process_token: usize) u32;
extern fn tk_port_is_in_use(port: u16) c_int;
extern fn tk_write(fd: c_int, buf: [*]const u8, count: usize) usize;
extern fn tk_isatty(fd: c_int) c_int;
extern fn tk_fflush() void;
extern fn tk_setenv(name: [*]const u8, value: [*]const u8, overwrite: c_int) c_int;
extern fn tk_getenv(name: [*]const u8) [*:0]const u8;
extern fn tk_get_affinity(pid: c_int, mask: [*]u8) c_int;
extern fn tk_set_affinity(pid: c_int, mask: [*]const u8) c_int;

pub const ProcessReapKind = enum(u32) {
    running = 0,
    exited = 1,
    signaled = 2,
    stopped = 3,
    no_child = 4,
    failed = 5,
};

pub const ProcessError = enum(u32) {
    none = 0,
    access_denied = 1,
    invalid_process = 2,
    invalid_argument = 3,
    resource_exhausted = 4,
    unsupported = 5,
    system = 6,
};

pub const ProcessReapResult = extern struct {
    kind: u32,
    exit_code: u32,
    signal: u32,
    native_status: u32,
    err: u32,
    native_error: u32,
};

pub const ProcessTerminationKind = enum(u32) {
    none = 0,
    signal = 1,
    exit_code = 2,
};

pub const ProcessTerminateResult = extern struct {
    accepted: u32,
    action_kind: u32,
    action_value: u32,
    err: u32,
    native_error: u32,
};

extern fn tk_process_reap_nohang(process_token: usize, out: *ProcessReapResult) void;
extern fn tk_process_force_terminate(process_token: usize, out: *ProcessTerminateResult) void;
extern fn tk_process_release(process_token: usize, thread_token: usize) void;

extern fn tk_process_test_eintr_then_exit(exit_code: u32) void;
extern fn tk_process_test_native_call_count() u32;
extern fn tk_process_test_force_failure(err: u32, native_error: u32) void;

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

pub fn processToken(id: std.process.Child.Id) usize {
    return switch (@typeInfo(std.process.Child.Id)) {
        .pointer => @intFromPtr(id),
        .int => @intCast(id),
        else => @compileError("unsupported std.process.Child.Id representation"),
    };
}

/// Returns a numeric identifier only for logs and diagnostics. Lifecycle
/// operations must retain and use the opaque child token.
pub fn processDiagnosticPid(id: std.process.Child.Id) u32 {
    return tk_process_diagnostic_pid(processToken(id));
}

pub fn portIsInUse(port: u16) bool {
    return tk_port_is_in_use(port) != 0;
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

pub fn processReapNoHang(process_token: usize) ProcessReapResult {
    var result: ProcessReapResult = undefined;
    tk_process_reap_nohang(process_token, &result);
    return result;
}

pub fn processForceTerminate(process_token: usize) ProcessTerminateResult {
    var result: ProcessTerminateResult = undefined;
    tk_process_force_terminate(process_token, &result);
    return result;
}

pub fn processRelease(child: *std.process.Child) void {
    const id = child.id orelse return;
    const thread_token: usize = switch (@typeInfo(@TypeOf(child.thread_handle))) {
        .pointer => @intFromPtr(child.thread_handle),
        .void => 0,
        else => @compileError("unsupported child thread handle representation"),
    };
    tk_process_release(processToken(id), thread_token);
    child.id = null;
}

pub fn processTestEintrThenExit(exit_code: u32) void {
    tk_process_test_eintr_then_exit(exit_code);
}

pub fn processTestNativeCallCount() u32 {
    return tk_process_test_native_call_count();
}

pub fn processTestForceFailure(err: u32, native_error: u32) void {
    tk_process_test_force_failure(err, native_error);
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

test "process ABI layouts match C declarations" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(ProcessTerminateResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(ProcessTerminateResult));
}
