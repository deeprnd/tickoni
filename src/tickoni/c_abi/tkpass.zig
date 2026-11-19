/// Thin Zig wrapper over tk_pass_stem.c — the placeholder stem tiles of the
/// investment workflow: tkcase (forwards its input to every output), and tktool
/// and tkadpt (idle bounded consumers). One implementation, three identities.
/// They carry no case, tool or adapter semantics; see the tkagnt migration plan.
const std = @import("std");

extern fn tkpass_tile_scratch_footprint() usize;
extern fn tkpass_tile_scratch_align() usize;
extern fn tkpass_set_event_count(event_count: u64) void;
extern fn tkpass_consumed(scratch: ?*anyopaque) usize;
extern fn tkpass_forwarded(scratch: ?*anyopaque) usize;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn scratchFootprint() usize {
    return tkpass_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkpass_tile_scratch_align();
}

/// Sets the forwarding tile's event gate (tkcase). tktool and tkadpt have none.
pub fn setEventCount(event_count: u64) void {
    tkpass_set_event_count(event_count);
}

/// Fragments this tile has committed from its input.
pub fn consumed(scratch: ?*anyopaque) u64 {
    return tkpass_consumed(scratch);
}

/// Fragments tkcase has forwarded (each to every output). Zero for the others.
pub fn forwarded(scratch: ?*anyopaque) u64 {
    return tkpass_forwarded(scratch);
}

test "the placeholder tiles share one aligned scratch layout, registered under each identity" {
    const footprint = scratchFootprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(@as(usize, 0), footprint % scratchAlign());
    inline for (.{ "tkcase", "tktool", "tkadpt" }) |name| {
        try std.testing.expectEqual(footprint, tk_topob_tickoni_tile_scratch_footprint(name));
    }
}
