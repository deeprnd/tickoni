/// Narrow FFI for the tkings fd_stem producer.
const std = @import("std");
const audit_mod = @import("audit_mod");

pub const PaymentMessage = audit_mod.PaymentMessage;

pub const Generator = *const fn (u64, *PaymentMessage) callconv(.c) void;

extern fn tkings_set_event_count(event_count: u64) void;
extern fn tkings_set_payment_generator(generator: Generator) void;
extern fn tkings_set_stuck_hook(after_messages: u64, sleep_ns: u64) void;
extern fn tkings_set_crash_after_heartbeats(heartbeat_count: u32) void;
extern fn tk_get_ingest_run_name() [*:0]const u8;
extern fn tk_get_ingest_run_tile() ?*anyopaque;
extern fn tkings_tile_scratch_align() usize;
extern fn tkings_tile_scratch_footprint() usize;

pub fn setEventCount(event_count: u64) void {
    tkings_set_event_count(event_count);
}

pub fn setPaymentGenerator(generator: Generator) void {
    tkings_set_payment_generator(generator);
}

pub fn setStuckHook(after_messages: u64, sleep_ns: u64) void {
    tkings_set_stuck_hook(after_messages, sleep_ns);
}

pub fn setCrashAfterHeartbeats(heartbeat_count: u32) void {
    tkings_set_crash_after_heartbeats(heartbeat_count);
}

test "tkings stem descriptor and payment ABI" {
    try std.testing.expectEqualStrings("tkings", std.mem.sliceTo(tk_get_ingest_run_name(), 0));
    try std.testing.expect(tk_get_ingest_run_tile() != null);
    try std.testing.expect(tkings_tile_scratch_align() > 0);
    try std.testing.expect(tkings_tile_scratch_footprint() > 0);
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(audit_mod.RawPayment));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(PaymentMessage));
}
