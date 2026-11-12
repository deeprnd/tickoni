/// Standalone topology tests for the tknorm fd_stem tile.
///
/// Tests:
/// 1. Tile identity — name == "tknorm", callbacks non-null
/// 2. Scratch space determinism — footprint > 1, topob matches
const std = @import("std");
const c_abi = @import("c_abi");

// ---------------------------------------------------------------------------
// Helper extern functions to read individual fields from TK_NORM_RUN.
// This avoids struct layout mismatch between Zig and C.
// ---------------------------------------------------------------------------

extern fn tk_get_norm_run_name() [*]const u8;
extern fn tk_get_norm_run_run() ?*anyopaque;
extern fn tk_get_norm_run_scratch_align() ?*anyopaque;
extern fn tk_get_norm_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_norm_run_privileged_init() ?*anyopaque;
extern fn tk_get_norm_run_unprivileged_init() ?*anyopaque;
extern fn tknorm_tile_scratch_footprint() c_ulong;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) c_ulong;

test "tknorm tile identity — name is TILE_ID_TKNORM" {
    const name = std.mem.sliceTo(tk_get_norm_run_name(), 0);
    try std.testing.expectEqualStrings("tknorm", name);
}

test "tknorm tile identity — run callback is non-null" {
    try std.testing.expect(tk_get_norm_run_run() != null);
}

test "tknorm tile identity — scratch callbacks are non-null" {
    try std.testing.expect(tk_get_norm_run_scratch_align() != null);
    try std.testing.expect(tk_get_norm_run_scratch_footprint() != null);
}

test "tknorm tile identity — init callbacks are non-null" {
    try std.testing.expect(tk_get_norm_run_privileged_init() != null);
    try std.testing.expect(tk_get_norm_run_unprivileged_init() != null);
}

test "tknorm scratch footprint — returns deterministic value > 1" {
    const footprint = tknorm_tile_scratch_footprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(footprint, tknorm_tile_scratch_footprint());
}

test "tknorm scratch footprint — topob wrapper matches direct call" {
    const direct = tknorm_tile_scratch_footprint();
    const via_topob = tk_topob_tickoni_tile_scratch_footprint("tknorm");
    try std.testing.expectEqual(direct, via_topob);
}
