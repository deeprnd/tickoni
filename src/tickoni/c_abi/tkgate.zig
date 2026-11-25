/// Narrow FFI for the tkgate fd_stem CaseOps gate tile (tk_gate_stem.c): the
/// boundary between the terminal tile and tkings. Its only source is its input
/// link.
const std = @import("std");
const audit_mod = @import("audit_mod");
const trace_id = @import("trace_id.zig");

pub const TkEvent = audit_mod.TkEvent;

extern fn tkgate_set_event_count(event_count: u64) void;
extern fn tkgate_wire_ok(ev: *const TkEvent) c_int;
extern fn tk_get_gate_run_name() [*:0]const u8;
extern fn tk_get_gate_run_tile() ?*anyopaque;
extern fn tk_get_gate_run_privileged_init() ?*anyopaque;
extern fn tk_get_gate_run_unprivileged_init() ?*anyopaque;
extern fn tkgate_tile_scratch_align() usize;
extern fn tkgate_tile_scratch_footprint() usize;

pub fn setEventCount(event_count: u64) void {
    tkgate_set_event_count(event_count);
}

/// Whether tkgate would forward `ev` to tkings (its wire shape).
pub fn wireOk(ev: *const TkEvent) bool {
    return tkgate_wire_ok(ev) != 0;
}

fn validEvent() TkEvent {
    var ev = std.mem.zeroes(TkEvent);
    ev.version = audit_mod.TK_EVENT_WIRE_VERSION;
    ev.kind = audit_mod.TK_EVENT_KIND_PAYMENT;
    ev.source = audit_mod.TK_EVENT_SOURCE_TKGATE;
    ev.idempotency_key = 1;
    ev.trace_id = trace_id.fromInt(1);
    return ev;
}

test "tkgate stem descriptor and scratch" {
    try std.testing.expectEqualStrings("tkgate", std.mem.sliceTo(tk_get_gate_run_name(), 0));
    try std.testing.expect(tk_get_gate_run_tile() != null);
    try std.testing.expect(tk_get_gate_run_privileged_init() != null);
    try std.testing.expect(tk_get_gate_run_unprivileged_init() != null);
    // The context holds a TkEvent and an fd_rng_t, both 16-byte aligned.
    try std.testing.expectEqual(@as(usize, 16), tkgate_tile_scratch_align());
    try std.testing.expect(tkgate_tile_scratch_footprint() >= @sizeOf(TkEvent));
}

test "tkgate wire: a user request passes, of either kind" {
    var ev = validEvent();
    try std.testing.expect(wireOk(&ev));
    ev.kind = audit_mod.TK_EVENT_KIND_AGENT_REQUEST;
    try std.testing.expect(wireOk(&ev));
}

test "tkgate wire: an absent trace id passes, to be filled in" {
    var ev = validEvent();
    ev.trace_id = trace_id.fromInt(0);
    try std.testing.expect(wireOk(&ev));
}

test "tkgate wire: each malformed field fails closed" {
    const Mutate = *const fn (*TkEvent) void;
    const cases = [_]Mutate{
        struct {
            fn f(e: *TkEvent) void {
                e.version = audit_mod.TK_EVENT_WIRE_VERSION + 1;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.kind = 0;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.kind = 3;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.source = 0;
            }
        }.f,
        // Replay enters through tkrepl, never through the gate.
        struct {
            fn f(e: *TkEvent) void {
                e.source = audit_mod.TK_EVENT_SOURCE_TKREPL;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.source = audit_mod.TK_EVENT_SOURCE_TKREPL;
                e.flags = audit_mod.TK_EVENT_FLAG_REPLAY;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.flags = audit_mod.TK_EVENT_FLAG_REPLAY;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.flags = 0x80;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.idempotency_key = 0;
            }
        }.f,
    };
    for (cases) |mutate| {
        var ev = validEvent();
        mutate(&ev);
        try std.testing.expect(!wireOk(&ev));
    }
}
