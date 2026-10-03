/// Narrow Zig bindings over src/tango/cnc/fd_cnc.h.
///
/// `fd_cnc_t` owns tile boot/heartbeat/halt/fail state for v2.14 process
/// mode. Zig callers bind only through Tickoni-owned `tk_*` shim symbols; the
/// shim calls the real Firedancer functions/static inline helpers.
const std = @import("std");

// ---------------------------------------------------------------------------
// Constants (from fd_cnc.h)
// ---------------------------------------------------------------------------

pub const cnc_align: usize = 128;
pub const cnc_app_align: usize = 64;
/// fd_cnc_app_laddr returns `((ulong)cnc) + 64UL` literally, not a
/// sizeof-derived offset — mirrored here as the same literal.
pub const cnc_app_offset: usize = 64;

pub const signal_run: u64 = 0;
pub const signal_boot: u64 = 1;
pub const signal_fail: u64 = 2;
pub const signal_halt: u64 = 3;

pub const err_success: i32 = 0;
pub const err_unsup: i32 = -1;
pub const err_inval: i32 = -2;
pub const err_again: i32 = -3;
pub const err_fail: i32 = -4;

/// Layout-only mirror of `struct fd_cnc_private` (fd_cnc.h) for offset
/// tests. Not used to allocate memory in Zig; `fd_cnc_new`/`fd_cnc_join`
/// own the real region.
pub const CncPrivate = extern struct {
    magic: u64,
    app_sz: u64,
    type: u64,
    heartbeat0: i64,
    heartbeat: i64,
    lock: u64,
    signal: u64,
};

pub const cnc_magic: u64 = 0xf17eda2c37c2c000;

/// Opaque handle returned by fd_cnc_join.
pub const Cnc = opaque {};

// ---------------------------------------------------------------------------
// Extern declarations — require -lfd_tango at link time
// ---------------------------------------------------------------------------

extern fn tk_cnc_align() usize;
extern fn tk_cnc_footprint(app_sz: usize) usize;
extern fn tk_cnc_new(shmem: *anyopaque, app_sz: usize, cnc_type: u64, now: i64) ?*anyopaque;
extern fn tk_cnc_join(shcnc: *anyopaque) ?*Cnc;
extern fn tk_cnc_leave(cnc: *const Cnc) ?*anyopaque;
extern fn tk_cnc_delete(shcnc: *anyopaque) ?*anyopaque;
extern fn tk_cnc_open(cnc: *Cnc) c_int;
extern fn tk_cnc_wait(cnc: *const Cnc, test_signal: u64, dt: i64, opt_now: ?*i64) u64;
extern fn tk_cnc_strerror(err: c_int) [*:0]const u8;
extern fn tk_cstr_to_cnc_signal(cstr: [*:0]const u8) u64;
extern fn tk_cnc_signal_cstr(signal: u64, buf: [*]u8) [*:0]u8;
extern fn tk_cnc_app_laddr(cnc: *Cnc) [*]u8;
extern fn tk_cnc_heartbeat_query(cnc: *const Cnc) u32;
extern fn tk_cnc_heartbeat(cnc: *Cnc, now_ns: i64) void;
extern fn tk_cnc_signal_query(cnc: *const Cnc) u64;
extern fn tk_cnc_signal(cnc: *Cnc, s: u64) void;
extern fn tk_cnc_close(cnc: *Cnc) void;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

pub fn cncAlign() usize {
    return tk_cnc_align();
}

pub fn cncFootprint(app_sz: usize) usize {
    return tk_cnc_footprint(app_sz);
}

pub fn cncNew(shmem: *anyopaque, app_sz: usize, cnc_type: u64, now: i64) ?*anyopaque {
    return tk_cnc_new(shmem, app_sz, cnc_type, now);
}

pub fn cncJoin(shcnc: *anyopaque) ?*Cnc {
    return tk_cnc_join(shcnc);
}

pub fn cncLeave(cnc: *const Cnc) ?*anyopaque {
    return tk_cnc_leave(cnc);
}

pub fn cncDelete(shcnc: *anyopaque) ?*anyopaque {
    return tk_cnc_delete(shcnc);
}

pub fn cncOpen(cnc: *Cnc) c_int {
    return tk_cnc_open(cnc);
}

pub fn cncWait(cnc: *const Cnc, test_signal: u64, dt: i64, opt_now: ?*i64) u64 {
    return tk_cnc_wait(cnc, test_signal, dt, opt_now);
}

pub fn cncStrerror(err: c_int) [*:0]const u8 {
    return tk_cnc_strerror(err);
}

pub fn cstrToCncSignal(cstr: [*:0]const u8) u64 {
    return tk_cstr_to_cnc_signal(cstr);
}

pub fn cncSignalCstr(s: u64, buf: [*]u8) [*:0]u8 {
    return tk_cnc_signal_cstr(s, buf);
}

/// Mirrors the upstream cnc app-laddr helper.
pub fn appLaddr(cnc: *Cnc) [*]u8 {
    return tk_cnc_app_laddr(cnc);
}

/// Mirrors the upstream cnc heartbeat-query helper.
pub fn heartbeatQuery(cnc: *const Cnc) u32 {
    return tk_cnc_heartbeat_query(cnc);
}

/// Mirrors the upstream cnc heartbeat helper.
pub fn heartbeat(cnc: *Cnc, now_ns: i64) void {
    tk_cnc_heartbeat(cnc, now_ns);
}

/// Mirrors the upstream cnc signal-query helper.
pub fn signalQuery(cnc: *const Cnc) u64 {
    return tk_cnc_signal_query(cnc);
}

/// Mirrors the upstream cnc signal helper.
pub fn signal(cnc: *Cnc, s: u64) void {
    tk_cnc_signal(cnc, s);
}

/// Mirrors the upstream cnc close helper.
pub fn close(cnc: *Cnc) void {
    tk_cnc_close(cnc);
}

// ---------------------------------------------------------------------------
// Tests — layout only; no C linkage required
// ---------------------------------------------------------------------------

test "CncPrivate field offsets match fd_cnc_private layout" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(CncPrivate, "magic"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(CncPrivate, "app_sz"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(CncPrivate, "type"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(CncPrivate, "heartbeat0"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(CncPrivate, "heartbeat"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(CncPrivate, "lock"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(CncPrivate, "signal"));
}

test "cnc alignment and app-region offset constants match header" {
    try std.testing.expectEqual(@as(usize, 128), cnc_align);
    try std.testing.expectEqual(@as(usize, 64), cnc_app_align);
    try std.testing.expectEqual(@as(usize, 64), cnc_app_offset);
}

test "cnc signal constants match header" {
    try std.testing.expectEqual(@as(u64, 0), signal_run);
    try std.testing.expectEqual(@as(u64, 1), signal_boot);
    try std.testing.expectEqual(@as(u64, 2), signal_fail);
    try std.testing.expectEqual(@as(u64, 3), signal_halt);
}
