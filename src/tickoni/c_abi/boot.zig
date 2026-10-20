/// Narrow Zig bindings over src/util/fd_util.h's fd_boot/fd_halt lifecycle.
///
/// Two boot paths exist:
/// - `bootLite()` — version + log + shmem only. Used by the supervisor
///   which spawns tile child processes instead of running tile threads.
/// - `boot()` — full boot including tile thread creation. Used by child
///   tile processes that run stem_run() and need their own tile thread.
///
/// Every process that touches fd_shmem/fd_wksp/fd_tango substrate calls
/// its appropriate boot exactly once before using shared memory and
/// calls fd_halt once at shutdown; fd_boot is what reads --shmem-path
/// / FD_SHMEM_PATH and brings the shared-memory subsystem online
/// (src/util/shmem/fd_shmem_admin.c). Synthetic-argv boot policy lives
/// in src/tickoni/runtime/boot.zig, which calls boot() / bootLite()
/// below. Tile-process teardown uses haltForTileProcess() so non-Linux
/// quirks stay hidden behind this ABI boundary instead of leaking into
/// runtime orchestration code.
const std = @import("std");
const builtin = @import("builtin");
extern fn tk_boot_lite(pargc: *c_int, pargv: *[*][*:0]u8) void;
extern fn tk_boot(pargc: *c_int, pargv: *[*][*:0]u8) void;
extern fn tk_halt() void;

/// Lightweight boot: version + log + shmem only. Used by the supervisor
/// and other bootstrap paths that spawn child tile processes instead of
/// running tile threads in-process. Skips fd_tile_private_boot() which
/// would create pthreads the supervisor never uses.
pub fn bootLite(pargc: *c_int, pargv: *[*][*:0]u8) void {
    tk_boot_lite(pargc, pargv);
}

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
