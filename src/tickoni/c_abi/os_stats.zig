/// Tests of the per-process OS statistics probe (shim/tk_os_stats.h) that the
/// tkdiag tile uses to publish per-tile CPU, fault, context-switch and memory
/// metrics, the way Firedancer's diag tile reads /proc/<pid>/task/<tid>/stat
/// (plans/v2.NN-sXX-tkdiag-fd-stem-migration.md, Future Work 3).
///
/// Linux is exercised here against this very process. The macOS and Windows
/// implementations (tk_os_stats_macos.c, tk_os_stats_windows.c) share the same
/// header; they are compile-checked for those targets but cannot be run on a
/// Linux host.
const std = @import("std");
const builtin = @import("builtin");

const Stats = extern struct {
    user_nanos: u64,
    system_nanos: u64,
    wait_nanos: u64,
    minor_faults: u64,
    major_faults: u64,
    voluntary_switches: u64,
    involuntary_switches: u64,
    resident_bytes: u64,
    last_cpu: u64,
    lifetime_nanos: u64,
};

const Probe = extern struct {
    stat_fd: c_int,
    sched_fd: c_int,
    pid: u64,
    tid: u64,
    os_handle: u64,
};

const probe_ok: c_int = 0;
const probe_gone: c_int = 1;

extern fn tk_os_probe_open(probe: *Probe, pid: u64, tid: u64) c_int;
extern fn tk_os_probe_read(probe: *Probe, out: *Stats) c_int;
extern fn tk_os_probe_close(probe: *Probe) void;
extern fn tk_os_probe_fds(probe: *const Probe, out: [*]c_int, cap: u64) u64;
extern fn tk_os_self_ids(pid: *u64, tid: *u64) void;
extern fn tk_os_stats_size() u64;

// The extern structs above restate the C layout only so the Linux test can read
// fields; a size check against the C definition keeps them from drifting.
test "os stats — the C struct layout matches the one used here" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    try std.testing.expectEqual(@as(u64, @sizeOf(Stats)), tk_os_stats_size());
}

fn selfPid() u64 {
    return @intCast(std.os.linux.getpid());
}

fn selfTid() u64 {
    return @intCast(std.os.linux.gettid());
}

test "os stats — probing this process yields live, monotonic numbers" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var probe: Probe = undefined;
    try std.testing.expectEqual(probe_ok, tk_os_probe_open(&probe, selfPid(), selfTid()));
    defer tk_os_probe_close(&probe);

    var first: Stats = undefined;
    try std.testing.expectEqual(probe_ok, tk_os_probe_read(&probe, &first));
    try std.testing.expect(first.resident_bytes > 0);
    try std.testing.expect(first.lifetime_nanos > 0);

    // Burn a little CPU and fault in some memory, then read again.
    var sink: u64 = 0;
    var i: u64 = 0;
    while (i < 50_000_000) : (i += 1) sink +%= i *% 2654435761;
    std.mem.doNotOptimizeAway(sink);
    const page = try std.testing.allocator.alloc(u8, 8 * 1024 * 1024);
    defer std.testing.allocator.free(page);
    @memset(page, 1);

    var second: Stats = undefined;
    try std.testing.expectEqual(probe_ok, tk_os_probe_read(&probe, &second));
    try std.testing.expect(second.user_nanos + second.system_nanos >= first.user_nanos + first.system_nanos);
    try std.testing.expect(second.minor_faults >= first.minor_faults);
    try std.testing.expect(second.lifetime_nanos >= first.lifetime_nanos);
}

test "os stats — a process that does not exist is reported gone, not an error" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var probe: Probe = undefined;
    // pid_max is at most 2^22, so this pid cannot exist.
    try std.testing.expectEqual(probe_gone, tk_os_probe_open(&probe, 0x7fff_fff0, 0x7fff_fff0));
}

test "os stats — the probe lists the descriptors that must survive sandbox entry" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var probe: Probe = undefined;
    try std.testing.expectEqual(probe_ok, tk_os_probe_open(&probe, selfPid(), selfTid()));
    var fds: [4]c_int = undefined;
    const cnt = tk_os_probe_fds(&probe, &fds, fds.len);
    // The stat file always; the sched file only on kernels built with
    // CONFIG_SCHED_DEBUG.
    try std.testing.expect(cnt == 1 or cnt == 2);
    for (fds[0..cnt]) |fd| try std.testing.expect(fd >= 0);
    if (cnt == 2) try std.testing.expect(fds[0] != fds[1]);
    // A too-small buffer is not overrun.
    var one: [1]c_int = undefined;
    try std.testing.expectEqual(@as(u64, 1), tk_os_probe_fds(&probe, &one, one.len));
    tk_os_probe_close(&probe);
    // After close nothing is left to keep.
    try std.testing.expectEqual(@as(u64, 0), tk_os_probe_fds(&probe, &fds, fds.len));
}

test "os stats — closing twice is harmless" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var probe: Probe = undefined;
    try std.testing.expectEqual(probe_ok, tk_os_probe_open(&probe, selfPid(), selfTid()));
    tk_os_probe_close(&probe);
    tk_os_probe_close(&probe);
}

test "os stats — a process finds its own ids" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var pid: u64 = 0;
    var tid: u64 = 0;
    tk_os_self_ids(&pid, &tid);
    try std.testing.expectEqual(selfPid(), pid);
    try std.testing.expectEqual(selfTid(), tid);
}
