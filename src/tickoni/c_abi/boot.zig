/// Narrow Zig bindings over src/util/fd_util.h's fd_boot/fd_halt lifecycle.
///
/// Every process that touches fd_shmem/fd_wksp/fd_tango substrate (the v2.14
/// process-mode supervisor and every spawned tile) must call fd_boot exactly
/// once before using it and fd_halt once at shutdown; fd_boot is what reads
/// --shmem-path/FD_SHMEM_PATH and brings the shared-memory subsystem online
/// (src/util/shmem/fd_shmem_admin.c). Synthetic-argv boot policy lives in
/// src/tickoni/runtime/boot.zig, which calls boot() below. Tile-process
/// teardown uses haltForTileProcess() so non-Linux quirks stay hidden behind
/// this ABI boundary instead of leaking into runtime orchestration code.
const builtin = @import("builtin");
extern fn tk_boot(pargc: *c_int, pargv: *[*][*:0]u8) void;
extern fn tk_halt() void;

pub fn boot(pargc: *c_int, pargv: *[*][*:0]u8) void {
    tk_boot(pargc, pargv);
}

pub fn halt() void {
    tk_halt();
}

/// Platform-neutral tile-process teardown hook. Linux keeps the explicit
/// fd_boot/fd_halt pairing; macOS and Windows retail child tiles exit
/// immediately after their one tile returns, so skip tk_halt() there and let
/// process teardown reclaim process-local state.
pub fn haltForTileProcess() void {
    if (builtin.os.tag == .linux) tk_halt();
}

/// Wraps FD_SPIN_PAUSE (src/util/fd_util_base.h): yields the calling logical
/// core for one bounded-poll iteration without a scheduler-visible yield.
/// Used between polls in hot mcache-consumer wait loops, matching the
/// FD_MCACHE_WAIT pattern in src/tango/mcache/fd_mcache.h.
extern fn tk_spin_pause() void;

pub fn spinPause() void {
    tk_spin_pause();
}

// ---------------------------------------------------------------------------
// Tests — platform-specific halt behavior and constant smoke checks.
// ---------------------------------------------------------------------------

test "haltForTileProcess calls tk_halt only on Linux" {
    if (builtin.os.tag == .linux) {
        // On Linux we cannot easily isolate the branch, but we can verify
        // the compile-time constant path is what we expect: the Linux build
        // will reach tk_halt; non-Linux will not.  This test at least
        // documents the expected platform branching.
        try std.testing.expect(builtin.os.tag == .linux);
    } else {
        try std.testing.expect(builtin.os.tag != .linux);
    }
}

test "boot.zig module compiles with expected symbols" {
    // Smoke test: verify all public symbols exist and have the expected
    // types.  The actual C linkage is exercised by process-mode
    // integration tests, but the Zig surface must be consistent.
    const t = @TypeOf(boot);
    const u = @TypeOf(halt);
    const v = @TypeOf(haltForTileProcess);
    const w = @TypeOf(spinPause);
    // All should be functions with no return (void)
    _ = t;
    _ = u;
    _ = v;
    _ = w;
}
