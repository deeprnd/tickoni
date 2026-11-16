/// Narrow Zig bindings over src/tango/tempo/fd_tempo.h.
///
/// Tickoni uses only the housekeeping-scheduler helpers needed by v2.14.S8.T13.
/// The shim hides Firedancer's fd_rng_t requirement for async_reload behind a
/// thread-local RNG, so Zig callers stay on the Tickoni-owned `tk_*` surface.
const std = @import("std");

extern fn tk_tempo_tick_per_ns(opt_sigma: ?*f64) f64;
extern fn tk_tempo_async_reload(async_min: usize) usize;
extern fn tk_tickcount_wide() i64;
extern fn tk_tickcount_is_wallclock() c_int;
extern fn tk_log_wallclock_nanos() i64;

/// Full-width tick counter driving fd_stem housekeeping (fd_tickcount_wide).
pub fn tickcountWide() i64 {
    return tk_tickcount_wide();
}

/// True when this build's tick counter is the portable wallclock fallback
/// (FD_TICKCOUNT_STYLE 0: no FD_HAS_X86/FD_HAS_ARM, e.g. every aarch64 target).
pub fn tickcountIsWallclock() bool {
    return tk_tickcount_is_wallclock() != 0;
}

/// Full-width wallclock, ns since the UNIX epoch (fd_log_wallclock_nanos).
pub fn wallclockNanos() i64 {
    return tk_log_wallclock_nanos();
}

pub fn tickPerNs(opt_sigma: ?*f64) f64 {
    return tk_tempo_tick_per_ns(opt_sigma);
}

pub fn lazyDefault(cr_max: usize) i64 {
    return if (cr_max > 954_437_176) std.math.maxInt(i32) else @intCast(1 + ((9 * cr_max) >> 2));
}

pub fn asyncMin(lazy: i64, event_cnt: usize, tick_per_ns: f32) usize {
    if (!(1 <= lazy and lazy < (1 << 31))) return 0;
    if (!(1 <= event_cnt and event_cnt < (1 << 31))) return 0;

    const tick_per_ns_max = std.math.floatMax(f32) / @as(f32, @floatFromInt(1 << 31));
    if (!(0.0 < tick_per_ns and tick_per_ns <= tick_per_ns_max)) return 0;

    const lazy_f: f32 = @floatFromInt(lazy);
    const event_cnt_f: f32 = @floatFromInt(event_cnt);
    const async_target = (tick_per_ns * lazy_f) / event_cnt_f;

    if (!(async_target >= 1.0)) return 0;
    if (!(async_target < @as(f32, @floatFromInt(@as(u64, 1) << 32)))) return 0;

    const async_target_int: usize = @intFromFloat(async_target);
    return @as(usize, 1) << @intCast(std.math.log2_int(usize, async_target_int));
}

pub fn asyncReload(async_min: usize) usize {
    return tk_tempo_async_reload(async_min);
}

test "lazyDefault matches the documented formula for small cr_max" {
    try std.testing.expectEqual(@as(i64, 1), lazyDefault(0));
    try std.testing.expectEqual(@as(i64, 3), lazyDefault(1));
    try std.testing.expectEqual(@as(i64, 10), lazyDefault(4));
}

test "asyncMin returns a power of two for a valid scheduler configuration" {
    const value = asyncMin(225, 1, 1.0);
    try std.testing.expect(value > 0);
    try std.testing.expect(std.math.isPowerOfTwo(value));
}

test "tickPerNs returns a positive calibration" {
    try std.testing.expect(tickPerNs(null) > 0.0);
}

// Regression: on LLP64 Windows, fd_log_wallclock() returns a 32-bit long,
// so a wallclock-fallback fd_tickcount_wide() built on it wrapped every
// ~4.29 s. A housekeeping deadline set just before the wrap was then never
// reached again and stem tiles stopped returning flow-control credits.
test "wallclock-fallback tickcountWide is full-width wallclock ns" {
    if (!tickcountIsWallclock()) return error.SkipZigTest;
    const before = wallclockNanos();
    const tick = tickcountWide();
    const after = wallclockNanos();
    // Must lie between two surrounding wallclock reads; a truncated value
    // is within +/-2^31 and so is ~1.8e18 below this window.
    try std.testing.expect(before <= tick);
    try std.testing.expect(tick <= after);
}

test "asyncReload stays within the expected range" {
    const async_min: usize = 64;
    const value = asyncReload(async_min);
    try std.testing.expect(value >= async_min);
    try std.testing.expect(value < (2 * async_min));
}
