/// Thin Zig wrapper over tk_diag_stem.c — the minimal observer stem registered
/// as tkdiag (0 input links, 0 output links, BEFORE_CREDIT only). It holds no
/// fragment I/O and exposes no tile state: the only observable outputs are its
/// CNC app slots 0 and 1, read by the supervisor through tile_registry.zig.
/// This module is therefore the identity and scratch contract, nothing more.
const std = @import("std");
const stem_run = @import("stem_run.zig");

pub const TopoRunTile = opaque {};

const run_desc = stem_run.RunDescriptor("diag", TopoRunTile);

extern fn tkdiag_tile_scratch_footprint() usize;
extern fn tkdiag_tile_scratch_align() usize;
extern fn tk_topob_tickoni_tile_scratch_requirements(tile_name: [*:0]const u8, alignment_out: *usize, footprint_out: *usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

pub fn scratchFootprint() usize {
    return tkdiag_tile_scratch_footprint();
}

pub fn scratchAlign() usize {
    return tkdiag_tile_scratch_align();
}

test "tkdiag identity — name is TILE_ID_TKDIAG" {
    try std.testing.expectEqualStrings("tkdiag", std.mem.sliceTo(run_desc.name(), 0));
    try std.testing.expect(run_desc.tile() != null);
}

test "tkdiag identity — run callback is non-null" {
    try std.testing.expect(run_desc.run() != null);
}

test "tkdiag identity — scratch callbacks are non-null" {
    try std.testing.expect(run_desc.scratchAlign() != null);
    try std.testing.expect(run_desc.scratchFootprint() != null);
}

test "tkdiag identity — init callbacks are non-null" {
    try std.testing.expect(run_desc.privilegedInit() != null);
    try std.testing.expect(run_desc.unprivilegedInit() != null);
}

test "tkdiag scratch — deterministic, aligned, and larger than one byte" {
    const footprint = scratchFootprint();
    const alignment = scratchAlign();
    try std.testing.expect(footprint > 1);
    try std.testing.expect(std.math.isPowerOfTwo(alignment));
    try std.testing.expectEqual(@as(usize, 0), footprint % alignment);
    try std.testing.expectEqual(footprint, scratchFootprint());
    try std.testing.expectEqual(alignment, scratchAlign());
}

test "tkdiag scratch — topob wrapper matches the direct call" {
    var alignment: usize = 0;
    var footprint: usize = 0;
    tk_topob_tickoni_tile_scratch_requirements("tkdiag", &alignment, &footprint);
    try std.testing.expectEqual(scratchAlign(), alignment);
    try std.testing.expectEqual(scratchFootprint(), footprint);
    try std.testing.expectEqual(scratchFootprint(), tk_topob_tickoni_tile_scratch_footprint("tkdiag"));
}
