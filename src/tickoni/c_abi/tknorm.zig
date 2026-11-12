/// Thin Zig wrapper over tk_normalize_stem.c — the Firedancer stem tile for tknorm.
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint, field accessors) as extern declarations with Zig-native wrapper
/// functions. This module is the FFI boundary for the tknorm stem tile.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations — from c_abi/shim/tk_normalize_stem.c
// Link requires tk_normalize_stem.c (supervisor shim library).
// ---------------------------------------------------------------------------

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_norm_run_name() [*:0]const u8;
extern fn tk_get_norm_run_tile() ?*TopoRunTile;
extern fn tk_get_norm_run_run() ?*anyopaque;
extern fn tk_get_norm_run_scratch_align() ?*anyopaque;
extern fn tk_get_norm_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_norm_run_privileged_init() ?*anyopaque;
extern fn tk_get_norm_run_unprivileged_init() ?*anyopaque;
extern fn tknorm_tile_scratch_footprint() usize;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns the tile name for tknorm.
pub fn getNormRunName() [*:0]const u8 {
    return tk_get_norm_run_name();
}

/// Returns a pointer to the TK_NORM_RUN tile descriptor.
pub fn getNormRunTile() ?*TopoRunTile {
    return tk_get_norm_run_tile();
}

/// Returns the stem run callback pointer.
pub fn getNormRun() ?*anyopaque {
    return tk_get_norm_run_run();
}

/// Returns the scratch align callback pointer.
pub fn getNormRunScratchAlign() ?*anyopaque {
    return tk_get_norm_run_scratch_align();
}

/// Returns the scratch footprint callback pointer.
pub fn getNormRunScratchFootprint() ?*anyopaque {
    return tk_get_norm_run_scratch_footprint();
}

/// Returns the privileged init callback pointer.
pub fn getNormRunPrivilegedInit() ?*anyopaque {
    return tk_get_norm_run_privileged_init();
}

/// Returns the unprivileged init callback pointer.
pub fn getNormRunUnprivilegedInit() ?*anyopaque {
    return tk_get_norm_run_unprivileged_init();
}

/// Returns the scratch footprint (in bytes) for the tknorm tile.
pub fn normScratchFootprint() usize {
    return tknorm_tile_scratch_footprint();
}

// ---------------------------------------------------------------------------
// Identity tests — verify the C stem symbols are linked and accessible.
// These are compile-time linkage checks; they do not require a running pipeline.
// ---------------------------------------------------------------------------

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
