/// Generic CPU affinity bindings and cpu-set bit manipulation. Zero Tickoni
/// domain knowledge (no tiles, no topology) — a plain Linux syscall wrapper
/// usable outside this codebase unchanged. CPU placement policy (validating
/// a Topology's declared placements against a live CpuSet) lives in
/// src/tickoni/runtime/cpu_placement.zig, layered on top of this file.
///
/// Firedancer has an internal fd_cpuset_t affinity wrapper
/// (src/util/tile/fd_tile_private.h), but that header documents itself as
/// "intended for internal use within fd_tile" and layers a macro-templated
/// bitset (`fd_set.c` with `SET_MAX FD_TILE_MAX`) that has no stable,
/// independently-linkable layout outside fd_tile's own translation unit.
/// Per the "drop to a more explicit lower-level path" guidance in
/// doc/execution/contribution/tickoni.md, this wraps the POSIX
/// sched_getaffinity/sched_setaffinity syscalls via the C shim.
/// On macOS these are stubs (no-op) because macOS does not provide
/// sched_*affinity — the stub lets the same topo/run pipeline compile
/// without platform-specific code paths.
///
/// Link requirements: none beyond libc (glibc exposes sched_*affinity
/// directly). On macOS no extra linking needed.
const std = @import("std");
const os_api = @import("os_api.zig");

/// Matches glibc's default cpu_set_t size (CPU_SETSIZE=1024 bits).
pub const cpu_set_bytes: usize = 128;
pub const CpuSet = [cpu_set_bytes]u8;

/// Clears every bit in `cpu_set`.
pub fn zero(cpu_set: *CpuSet) void {
    @memset(cpu_set, 0);
}

/// Sets the bit for `cpu` in `cpu_set`. Asserts `cpu` is in range
/// (`< cpu_set_bytes * 8`); callers with externally-sourced cpu ids must
/// range-check first (see cpu_placement.zig's requireAvailable for the
/// fail-closed version of that check).
pub fn set(cpu_set: *CpuSet, cpu: usize) void {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    cpu_set[cpu / 8] |= @as(u8, 1) << @intCast(cpu % 8);
}

/// Returns whether the bit for `cpu` is set in `cpu_set`. Asserts `cpu`
/// is in range, matching set().
pub fn isSet(cpu_set: *const CpuSet, cpu: usize) bool {
    std.debug.assert(cpu < cpu_set_bytes * 8);
    return (cpu_set[cpu / 8] & (@as(u8, 1) << @intCast(cpu % 8))) != 0;
}

/// Returns the number of set bits in `cpu_set`.
pub fn count(cpu_set: *const CpuSet) usize {
    var n: usize = 0;
    for (cpu_set) |byte| n += @popCount(byte);
    return n;
}

// ---------------------------------------------------------------------------
// Platform-specific affinity syscalls — moved to C shim (os.c).
// See os_api.getAffinity/os_api.setAffinity for the uniform interface.
// ---------------------------------------------------------------------------

/// Reads the current CPU affinity mask for `pid` into `cpu_set`. pid==0
/// means the calling thread. On non-Linux this returns an all-bits-set mask
/// so placement validation treats every logical CPU id as available.
pub fn getAffinity(pid: c_int, cpu_set: *CpuSet) !void {
    try os_api.getAffinity(pid, cpu_set);
}

/// Pins `pid` (0 == calling thread) to the CPUs set in `cpu_set`.
/// On non-Linux this is a no-op that returns successfully.
pub fn setAffinity(pid: c_int, cpu_set: *const CpuSet) !void {
    try os_api.setAffinity(pid, cpu_set);
}

// ---------------------------------------------------------------------------
// Tests — bit manipulation only; no real syscalls invoked
// ---------------------------------------------------------------------------

test "zero clears all bits" {
    var cs: CpuSet = undefined;
    @memset(&cs, 0xff);
    zero(&cs);
    try std.testing.expectEqual(@as(usize, 0), count(&cs));
}

test "set and isSet round-trip for low and high cpu ids" {
    var cs: CpuSet = undefined;
    zero(&cs);
    set(&cs, 0);
    set(&cs, 63);
    set(&cs, 1023);
    try std.testing.expect(isSet(&cs, 0));
    try std.testing.expect(isSet(&cs, 63));
    try std.testing.expect(isSet(&cs, 1023));
    try std.testing.expect(!isSet(&cs, 1));
    try std.testing.expectEqual(@as(usize, 3), count(&cs));
}
