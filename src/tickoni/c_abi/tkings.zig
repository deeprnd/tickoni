/// Narrow FFI for the tkings fd_stem ingestion tile. Its only source is its
/// input link (tk_ingest_stem.c); nothing here installs a generator.
const std = @import("std");
const audit_mod = @import("audit_mod");

pub const TkEvent = audit_mod.TkEvent;

extern fn tkings_set_event_count(event_count: u64) void;
extern fn tkings_framing_ok(ev: *const TkEvent) c_int;
extern fn tk_get_ingest_run_name() [*:0]const u8;
extern fn tk_get_ingest_run_tile() ?*anyopaque;
extern fn tkings_tile_scratch_align() usize;
extern fn tkings_tile_scratch_footprint() usize;

pub fn setEventCount(event_count: u64) void {
    tkings_set_event_count(event_count);
}

/// Whether tkings would forward `ev` (its canonical framing).
pub fn framingOk(ev: *const TkEvent) bool {
    return tkings_framing_ok(ev) != 0;
}

fn validEvent() TkEvent {
    var ev = std.mem.zeroes(TkEvent);
    ev.version = audit_mod.TK_EVENT_WIRE_VERSION;
    ev.kind = audit_mod.TK_EVENT_KIND_PAYMENT;
    ev.source = audit_mod.TK_EVENT_SOURCE_TKAPI;
    ev.trace_id = 1;
    return ev;
}

test "tkings stem descriptor and event ABI" {
    try std.testing.expectEqualStrings("tkings", std.mem.sliceTo(tk_get_ingest_run_name(), 0));
    try std.testing.expect(tk_get_ingest_run_tile() != null);
    try std.testing.expect(tkings_tile_scratch_align() > 0);
    try std.testing.expect(tkings_tile_scratch_footprint() > 0);
    try std.testing.expectEqual(@as(usize, 360), @sizeOf(TkEvent));
    try std.testing.expect(@sizeOf(TkEvent) <= audit_mod.TK_EVENT_LINK_MTU);
}

test "tkings framing: a canonical event passes, from tkapi or tkrepl" {
    var ev = validEvent();
    try std.testing.expect(framingOk(&ev));
    ev.kind = audit_mod.TK_EVENT_KIND_AGENT_REQUEST;
    try std.testing.expect(framingOk(&ev));
    ev.source = audit_mod.TK_EVENT_SOURCE_TKREPL;
    ev.flags = audit_mod.TK_EVENT_FLAG_REPLAY;
    try std.testing.expect(framingOk(&ev));
}

test "tkings framing: each malformed envelope field fails closed" {
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
        struct {
            fn f(e: *TkEvent) void {
                e.source = audit_mod.TK_EVENT_SOURCE_CNT;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.trace_id = 0;
            }
        }.f,
        struct {
            fn f(e: *TkEvent) void {
                e.flags = 0x80;
            }
        }.f,
        // Only tkrepl may mark an event as a replay.
        struct {
            fn f(e: *TkEvent) void {
                e.flags = audit_mod.TK_EVENT_FLAG_REPLAY;
            }
        }.f,
    };
    for (cases) |mutate| {
        var ev = validEvent();
        mutate(&ev);
        try std.testing.expect(!framingOk(&ev));
    }
}
