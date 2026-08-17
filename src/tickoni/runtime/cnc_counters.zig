const std = @import("std");
const c_abi = @import("c_abi");

/// Tickoni process-mode tile metric-counter schema, layered on top of the
/// cnc app-defined region (c_abi.cnc.appLaddr). Each process-mode tile
/// publishes its own local produced/normalized/etc. counters here so a
/// diagnostics reader can see them across the process boundary without a
/// separate shared object per counter. Callers must ensure the cnc was
/// created with app_sz >= (idx+1)*8.
pub const app_counter_cap: usize = 8;

/// Reads one u64 counter slot from the cnc's app-defined region.
pub fn appCounterRead(cnc: *c_abi.cnc.Cnc, idx: usize) u64 { std.debug.assert(idx < app_counter_cap);
    const base = c_abi.cnc.appLaddr(cnc);
    const ptr: *const volatile u64 = @ptrCast(@alignCast(base + idx * 8));
    return ptr.*; }

/// Writes one u64 counter slot in the cnc's app-defined region.
pub fn appCounterWrite(cnc: *c_abi.cnc.Cnc, idx: usize, value: u64) void { std.debug.assert(idx < app_counter_cap);
    const base = c_abi.cnc.appLaddr(cnc);
    const ptr: *volatile u64 = @ptrCast(@alignCast(base + idx * 8));
    ptr.* = value; }

test "appCounterRead/Write round-trip within a fake cnc-shaped buffer" { var buf: [256]u8 align(128) = std.mem.zeroes([256]u8);
    const cnc: *c_abi.cnc.Cnc = @ptrCast(&buf);
    appCounterWrite(cnc, 0, 42);
    appCounterWrite(cnc, 7, 100);
    try std.testing.expectEqual(@as(u64, 42), appCounterRead(cnc, 0));
    try std.testing.expectEqual(@as(u64, 100), appCounterRead(cnc, 7));
    try std.testing.expectEqual(@as(u64, 0), appCounterRead(cnc, 1));
}
