/// Thin Zig wrapper over tk_dedu_stem.c — the Firedancer stem tile for tkdedu.
///
/// Exposes the C stem tile's public symbols (run tile descriptor, scratch
/// footprint, field accessors) as extern declarations with Zig-native wrapper
/// functions. This module is the FFI boundary for the tkdedu stem tile.
const std = @import("std");

// ---------------------------------------------------------------------------
// Extern declarations — from c_abi/shim/tk_dedu_stem.c
// Link requires tk_dedu_stem.c (supervisor shim library).
// ---------------------------------------------------------------------------

/// Opaque handle for fd_topo_run_tile_t. Only shim code knows the real layout.
pub const TopoRunTile = opaque {};

extern fn tk_get_dedu_run_name() [*:0]const u8;
extern fn tk_get_dedu_run_tile() ?*TopoRunTile;
extern fn tk_get_dedu_run_run() ?*anyopaque;
extern fn tk_get_dedu_run_scratch_align() ?*anyopaque;
extern fn tk_get_dedu_run_scratch_footprint() ?*anyopaque;
extern fn tk_get_dedu_run_privileged_init() ?*anyopaque;
extern fn tk_get_dedu_run_unprivileged_init() ?*anyopaque;
extern fn tkdedu_tile_scratch_footprint() usize;
extern fn tkdedu_tile_scratch_align() usize;
extern fn tkdedu_set_event_count(event_count: usize) void;
extern fn tk_topob_tickoni_tile_scratch_footprint(tile_name: [*:0]const u8) usize;

// ---------------------------------------------------------------------------
// Public Zig wrappers.
// ---------------------------------------------------------------------------

/// Returns the tile name for tkdedu.
pub fn getDeduRunName() [*:0]const u8 {
    return tk_get_dedu_run_name();
}

/// Returns a pointer to the TK_DEDU_RUN tile descriptor.
pub fn getDeduRunTile() ?*TopoRunTile {
    return tk_get_dedu_run_tile();
}

/// Returns the stem run callback pointer.
pub fn getDeduRun() ?*anyopaque {
    return tk_get_dedu_run_run();
}

/// Returns the scratch align callback pointer.
pub fn getDeduRunScratchAlign() ?*anyopaque {
    return tk_get_dedu_run_scratch_align();
}

/// Returns the scratch footprint callback pointer.
pub fn getDeduRunScratchFootprint() ?*anyopaque {
    return tk_get_dedu_run_scratch_footprint();
}

/// Returns the privileged init callback pointer.
pub fn getDeduRunPrivilegedInit() ?*anyopaque {
    return tk_get_dedu_run_privileged_init();
}

/// Returns the unprivileged init callback pointer.
pub fn getDeduRunUnprivilegedInit() ?*anyopaque {
    return tk_get_dedu_run_unprivileged_init();
}

/// Returns the scratch footprint (in bytes) for the tkdedu tile.
pub fn deduScratchFootprint() usize {
    return tkdedu_tile_scratch_footprint();
}

/// Returns the alignment (in bytes) of the tkdedu tile's scratch object —
/// the block holding the context, the dedupe arrays and the output message.
pub fn deduScratchAlign() usize {
    return tkdedu_tile_scratch_align();
}

/// Sets the dedupe table size for this process.
///
/// This value participates in workspace layout: `tkdedu_scratch_footprint_tile`
/// reserves `event_count` entries for each of `seen_keys`/`seen_hashes`, and
/// `privileged_init` derives its pointers from the same number. The supervisor
/// and every self-exec'd child must therefore pass the identical value, or
/// their object offsets diverge and children read the wrong addresses.
/// `topo_build.build` is the single call site; it takes the value from
/// `TopologySpec.event_count`, which is written once by the supervisor and read
/// by every child. 0 selects the tile's built-in default reservation and
/// disables the event-count shutdown gate.
pub fn setEventCount(event_count: u64) void {
    tkdedu_set_event_count(@intCast(event_count));
}

// ---------------------------------------------------------------------------
// Identity tests — verify the C stem symbols are linked and accessible.
// These are compile-time linkage checks; they do not require a running pipeline.
// ---------------------------------------------------------------------------

test "tkdedu tile identity — name is TILE_ID_TKDEDU" {
    const name = std.mem.sliceTo(tk_get_dedu_run_name(), 0);
    try std.testing.expectEqualStrings("tkdedu", name);
}

test "tkdedu tile identity — run callback is non-null" {
    try std.testing.expect(tk_get_dedu_run_run() != null);
}

test "tkdedu tile identity — scratch callbacks are non-null" {
    try std.testing.expect(tk_get_dedu_run_scratch_align() != null);
    try std.testing.expect(tk_get_dedu_run_scratch_footprint() != null);
}

test "tkdedu scratch align — describes the context block, not fd_stem's stack scratch" {
    // 16: the strictest of tkdedu_ctx_t and the output TkEvent the same
    // footprint carves out of the same block (TkEvent is 16-aligned by its
    // 16-byte trace_id).
    //
    // 128 (FD_STEM_SCRATCH_ALIGN) here means .scratch_align was wired to the
    // STEM-generated tkdedu_scratch_align() from fd_stem.c, which describes
    // fd_stem's own stack scratch: a different block from the one
    // .scratch_footprint reserves.  See "Tile Scratch Layout" in
    // doc/execution/contribution/tickoni.md.
    try std.testing.expectEqual(@as(usize, 16), tkdedu_tile_scratch_align());
}

test "tkdedu scratch align — footprint is a whole number of alignment units" {
    // The topology places the object on scratch_align and reserves
    // scratch_footprint bytes; a footprint that is not a multiple of the
    // alignment leaves the next object's offset depending on the slack.
    setEventCount(0);
    try std.testing.expectEqual(
        @as(usize, 0),
        tkdedu_tile_scratch_footprint() % tkdedu_tile_scratch_align(),
    );
}

test "tkdedu tile identity — init callbacks are non-null" {
    try std.testing.expect(tk_get_dedu_run_privileged_init() != null);
    try std.testing.expect(tk_get_dedu_run_unprivileged_init() != null);
}

test "tkdedu scratch footprint — returns deterministic value > 1" {
    const footprint = tkdedu_tile_scratch_footprint();
    try std.testing.expect(footprint > 1);
    try std.testing.expectEqual(footprint, tkdedu_tile_scratch_footprint());
}

test "tkdedu scratch footprint — topob wrapper matches direct call" {
    const direct = tkdedu_tile_scratch_footprint();
    const via_topob = tk_topob_tickoni_tile_scratch_footprint("tkdedu");
    try std.testing.expectEqual(direct, via_topob);
}

test "tkdedu scratch footprint — tracks the event_count layout parameter" {
    // Same parameter must yield the same reservation: this is what makes the
    // supervisor's layout and a child's re-derived layout agree.
    setEventCount(32);
    const a = tkdedu_tile_scratch_footprint();
    setEventCount(32);
    try std.testing.expectEqual(a, tkdedu_tile_scratch_footprint());

    // A larger table must reserve strictly more: two u64 arrays per entry.
    setEventCount(64);
    const b = tkdedu_tile_scratch_footprint();
    try std.testing.expectEqual(a + 32 * 2 * @sizeOf(u64), b);
}

test "tkdedu scratch footprint — 0 selects the built-in default reservation" {
    setEventCount(0);
    const default_footprint = tkdedu_tile_scratch_footprint();
    setEventCount(10_000);
    try std.testing.expectEqual(default_footprint, tkdedu_tile_scratch_footprint());
    setEventCount(0);
}
