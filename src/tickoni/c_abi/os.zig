/// Zig extern declarations for os.c cross-platform OS operations shim.
/// All platform-specific code is in os.c behind #if FD_HAS_LINUX guards.
const std = @import("std");
const builtin = @import("builtin");

// ---------------------------------------------------------------------------
// Extern declarations (bare, module-scoped — canonical pattern)
// ---------------------------------------------------------------------------

extern fn fd_log_wallclock() i64;
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
extern fn tk_getenv_len(name: [*]const u8) c_long;
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

pub fn fdLogWallclock() i64 {
    return fd_log_wallclock();
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

/// Returns the actual length of the environment variable value, or -1 if
/// the variable does not exist. Callers should check this before calling
/// `getenv()` to detect values that would be silently truncated by the
/// 4096-byte thread-local buffer (enforces "reject, don't truncate
/// silently" from security.md lines 57-59).
pub fn getenvLen(name: [*]const u8) c_long {
    return tk_getenv_len(name);
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
// Tests — cross-platform (run on Linux, macOS, and Windows)
// ---------------------------------------------------------------------------

test "monotonicNanos returns non-negative and monotonically increasing" {
    const t1 = monotonicNanos();
    try std.testing.expect(t1 >= 0);
    // Use the C shim's own sleepNanos — it's platform-independent
    sleepNanos(std.time.ns_per_ms);
    const t2 = monotonicNanos();
    try std.testing.expect(t2 >= t1);
}

test "selfExePath returns a non-empty path" {
    var buf: [4096]u8 = undefined;
    const path = try selfExePath(&buf);
    try std.testing.expect(path.len > 0);
}

test "selfExePath fits within exact buffer (no overflow, no truncation)" {
    // Verify the path fits exactly — ensures the C function doesn't
    // write past buf_len and that we don't silently truncate.
    var buf: [4096]u8 = undefined;
    const path = try selfExePath(&buf);
    try std.testing.expect(path.len > 0);
    try std.testing.expect(path.len < buf.len);
}

test "selfExePath truncates on undersized buffer (returns success with partial path)" {
    // Pass a 4-byte buffer — Linux readlink truncates rather than failing.
    // The C shim returns the truncated length (3 bytes), not -1.
    // This is acceptable: callers who need the full path get SelfExePathFailed
    // only when the buffer is 1 byte (buf_len - 1 = 0, readlink writes nothing).
    var buf: [4]u8 = undefined;
    const result = selfExePath(&buf);
    if (result) |path| {
        // readlink truncated; path is 0..3 bytes long.
        try std.testing.expect(path.len <= 3);
    } else |_| {
        // SelfExePathFailed — buffer too small even for truncated read.
    }
}

test "selfExePath is non-empty on every call" {
    // Call multiple times to ensure the C function is idempotent
    // and doesn't have subtle thread-local or state issues.
    for (0..5) |_| {
        var buf: [4096]u8 = undefined;
        const path = try selfExePath(&buf);
        try std.testing.expect(path.len > 0);
    }
}

test "getEnv/setEnv round-trip" {
    const name = "TK_TEST_ENV_VAR_XYZ";
    const value = "hello_from_test";
    _ = setEnv(name, value, 1);
    const got = getenv(name);
    try std.testing.expect(got != null);
    const got_str = std.mem.sliceTo(got.?, 0);
    try std.testing.expectEqualStrings(value, got_str);
    // Clean up to not pollute process environment
    _ = setEnv(name, "", 1);
}

test "getenvLen returns -1 for missing var" {
    const name = "TK_NONEXISTENT_VAR_XYZ";
    const len = getenvLen(name.ptr);
    try std.testing.expect(len == -1);
    const val = getenv(name.ptr);
    try std.testing.expect(val == null);
}

test "process ABI layouts match C declarations" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(ProcessReapResult));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(ProcessTerminateResult));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(ProcessTerminateResult));
}

// ---------------------------------------------------------------------------
// Tests — POSIX-specific (Linux and macOS only)
// ---------------------------------------------------------------------------

test "getenvLen returns correct length for PATH" {
    // PATH is available on all POSIX systems. It may not exist on Windows.
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const name = "PATH";
    const len = getenvLen(name.ptr);
    try std.testing.expect(len >= 0);
    const val = getenv(name.ptr);
    try std.testing.expect(val != null);
    try std.testing.expectEqual(len, @as(c_long, @intCast(std.mem.sliceTo(val.?, 0).len)));
}

test "parentPid for PID 1 returns a valid parent" {
    // tk_parent_pid(1) should return the parent of init.
    // In containers, PID 1's parent is often 0 (container init).
    // This may fail in restricted environments (e.g. containers, Windows).
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const ppid = parentPid(1) catch {
        // If parent lookup fails (e.g. restricted environment), skip.
        return error.SkipZigTest;
    };
    // Parent PID must be non-negative (PID 0 is used by container runtimes).
    try std.testing.expect(ppid >= 0);
}

test "parentPid returns -1 for a nonexistent PID" {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const r = parentPid(-1);
    try std.testing.expect(r == error.PPidNotFound);
    const r2 = parentPid(99999999);
    try std.testing.expect(r2 == error.PPidNotFound);
}

test "portIsInUse returns false for a random high port" {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    // High ports are very unlikely to be in use. This verifies the
    // happy path (socket -> bind succeeds -> not busy) on every run.
    const port: u16 = 59999;
    try std.testing.expect(!portIsInUse(port));
}

test "portIsInUse does not crash on any u16 value" {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    // Test several port values to verify the C shim handles them without crashes.
    // We only assert that the function returns a bool (not a crash).
    // Port availability is system-dependent and not asserted.
    _ = portIsInUse(0);
    _ = portIsInUse(80); // well-known port
    _ = portIsInUse(49152); // dynamic/ephemeral range
    _ = portIsInUse(65535); // max port
}

test "writeFd writes data and returns count" {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const n = writeFd(2, "hello"); // write to stderr fd (avoid stdout pipe backpressure)
    try std.testing.expect(n == 5);
}

test "isatty returns non-negative for stdout" {
    // Test that isTerminal works on stdout. When run in a terminal,
    // stdout is a TTY and returns non-zero. In piped/redirected contexts
    // it returns 0. Either way, the shim should not crash.
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const result = isTerminal(1);
    try std.testing.expect(result >= 0);
}

test "getenv truncation: long value returns truncated copy" {
    // Set a 5000-byte value — the C shim truncates to 4095 bytes.
    // getenvLen() returns the real length (5000), while getenv()
    // returns the truncated 4095-byte copy.
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) return error.SkipZigTest;

    const name = "TK_SHIM_LONG_VALUE_TEST";
    var long_buf: [5001]u8 = undefined;
    for (0..5000) |i| long_buf[i] = 'A';
    long_buf[5000] = '\x00'; // null-terminate so setenv reads exactly 5000 bytes
    const long_val = &long_buf;
    _ = setEnv(name, long_val, 1);
    defer _ = setEnv(name, "", 1);

    const real_len = getenvLen(name.ptr);
    try std.testing.expect(real_len > 0);
    // The real length should be 5000.
    try std.testing.expectEqual(@as(c_long, 5000), real_len);

    const got = getenv(name.ptr);
    try std.testing.expect(got != null);
    const truncated = std.mem.sliceTo(got.?, 0);
    // The C shim truncates to 4095 bytes.
    try std.testing.expect(truncated.len <= 4095);
    // All characters should still be 'A' (no corruption at boundary).
    for (truncated) |c| {
        try std.testing.expectEqual('A', c);
    }
}

// ---------------------------------------------------------------------------
// Tests — Windows-specific
// ---------------------------------------------------------------------------

// No Windows-specific tests yet — the C shim functions (selfExePath, getenv,
// parentPid, etc.) have equivalent Windows implementations but with different
// underlying APIs (GetModuleFileNameA, _dupenv_s, CreateToolhelp32Snapshot, etc.).
// Add Windows-specific tests when needed for coverage parity.
