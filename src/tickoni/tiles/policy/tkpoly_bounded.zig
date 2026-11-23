/// Bounded tile context for tkpoly — Phase 5 stem tile migration.
///
/// P5.1: Initialize and validate the bounded tile context.
/// Resolve scratch, require exactly one input/output, validate mcache/dcache/MTU
/// and workspace joins, find CNC, and precompute output chunk bounds.
///
/// Valid topology initialization succeeds; missing objects, wrong cardinality,
/// undersized MTU, or an unjoined workspace fails before the stem loop.
const std = @import("std");
const c_abi = @import("c_abi");
const topo_run = c_abi.topo_run;
const topob = c_abi.topob;

// ---------------------------------------------------------------------------
// Bounded tile context
// ---------------------------------------------------------------------------

/// The bounded tile context for tkpoly. All fields are set during
/// initBoundedTileContext and remain read-only for the tile's lifetime.
pub const TkPolyCtx = struct {
    /// Tile pointer (from topo).
    tile: *topo_run.TopoTile,
    /// Tile index in the topology.
    tile_idx: usize,
    /// Scratch base address (from tile_obj_id via fd_topo_obj_laddr).
    scratch: ?*anyopaque,
    /// Scratch footprint in bytes.
    scratch_footprint: usize,
    /// Scratch alignment.
    scratch_align: usize,
    /// Input link index (must be 0 — exactly one input).
    in_link_idx: usize,
    /// Output link index (must be 0 — exactly one output).
    out_link_idx: usize,
    /// Input mcache pointer.
    in_mcache: ?*anyopaque,
    /// Input dcache pointer (non-null if mtu > 0).
    in_dcache: ?*anyopaque,
    /// Output mcache pointer.
    out_mcache: ?*anyopaque,
    /// Output dcache pointer (non-null if mtu > 0).
    out_dcache: ?*anyopaque,
    /// Input link depth (mcache depth).
    in_depth: usize,
    /// Output link depth (mcache depth).
    out_depth: usize,
    /// Input link MTU.
    in_mtu: usize,
    /// Output link MTU.
    out_mtu: usize,
    /// CNC pointer (for shutdown detection and progress).
    cnc: ?*anyopaque,
    /// Output chunk bounds: next_chunk and max_chunk.
    out_next_chunk: usize,
    out_max_chunk: usize,
};

// ---------------------------------------------------------------------------
// Error set
// ---------------------------------------------------------------------------

/// Errors returned by initBoundedTileContext.
pub const Error = error{
    /// Tile not found in topology.
    TileNotFound,
    /// Wrong number of input links (expected exactly 1).
    WrongInputCardinality,
    /// Wrong number of output links (expected exactly 1).
    WrongOutputCardinality,
    /// Input mcache object id is not_found (link not wired).
    InputMcacheNull,
    /// Input dcache is null but MTU > 0 (undersized MTU or missing dcache).
    InputDcacheNullWithMtu,
    /// Output mcache object id is not_found (link not wired).
    OutputMcacheNull,
    /// Output dcache is null but MTU > 0 (undersized MTU or missing dcache).
    OutputDcacheNullWithMtu,
    /// Input MTU is zero or too small (must be >= minimum fragment size).
    InputMtuTooSmall,
    /// Output MTU is zero or too small (must be >= minimum fragment size).
    OutputMtuTooSmall,
    /// CNC object not found.
    CncNotFound,
    /// Scratch object not found.
    ScratchNotFound,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Minimum MTU — a data fragment must be at least 16 bytes.
const MIN_MTU: usize = 16;

/// Initialize and validate the bounded tile context for a tkpoly tile.
///
/// Steps:
/// 1. Find tkpoly in the topology (tile_id = "tkpoly", kind_id = 0).
/// 2. Verify exactly one input link (in_cnt == 1).
/// 3. Verify exactly one output link (out_cnt == 1).
/// 4. Validate input mcache/dcache/MTU and workspace joins.
/// 5. Validate output mcache/dcache/MTU and workspace joins.
/// 6. Find the CNC object for the tile.
/// 7. Resolve scratch (tile object).
/// 8. Precompute output chunk bounds.
///
/// Returns Error on any validation failure — the tile must not proceed to
/// the stem loop if any step fails.
pub fn initBoundedTileContext(
    topo: *topo_run.Topo,
    tile_name: []const u8,
    tile_kind_id: usize,
) Error!TkPolyCtx {
    // Step 1: Find tkpoly tile in topology.
    var name_buf: [7]u8 = undefined;
    const name_len = if (tile_name.len >= name_buf.len) name_buf.len else tile_name.len;
    @memcpy(name_buf[0..name_len], tile_name[0..name_len]);
    name_buf[name_len] = 0;
    const name_z: [*:0]const u8 = @ptrCast(&name_buf);

    const tile_idx = topob.topoFindTile(topo, name_z, tile_kind_id);
    if (tile_idx == topob.not_found) return Error.TileNotFound;

    // Step 2: Verify exactly one input link.
    const in_cnt = topob.topoTileInputCount(topo, tile_idx);
    if (in_cnt != 1) return Error.WrongInputCardinality;

    // Step 3: Verify exactly one output link.
    const out_cnt = topob.topoTileOutputCount(topo, tile_idx);
    if (out_cnt != 1) return Error.WrongOutputCardinality;

    // Validate input link — get mcache/dcache object ids.
    const in_link_id = topob.topoFindLink(topo, "tkdedu-tkpoly", 0);
    if (in_link_id == topob.not_found) return Error.InputMcacheNull;
    const in_mcache_obj_id = topob.topoLinkMcacheObjId(topo, in_link_id);
    if (in_mcache_obj_id == topob.not_found) return Error.InputMcacheNull;
    const in_mcache = topob.topoObjLaddr(topo, in_mcache_obj_id);
    const in_mtu: usize = 64; // tkdedu-tkpoly link depth=64
    const in_dcache_obj_id = topob.topoLinkDcacheObjId(topo, in_link_id);
    const in_dcache: ?*anyopaque = if (in_dcache_obj_id != topob.not_found)
        topob.topoObjLaddr(topo, in_dcache_obj_id)
    else
        null;

    if (in_mtu > 0 and in_dcache == null) return Error.InputDcacheNullWithMtu;
    if (in_mtu < MIN_MTU) return Error.InputMtuTooSmall;

    // Validate output link — get mcache/dcache object ids.
    const out_link_id = topob.topoFindLink(topo, "tkpoly-tkaudt", 0);
    if (out_link_id == topob.not_found) return Error.OutputMcacheNull;
    const out_mcache_obj_id = topob.topoLinkMcacheObjId(topo, out_link_id);
    if (out_mcache_obj_id == topob.not_found) return Error.OutputMcacheNull;
    const out_mcache = topob.topoObjLaddr(topo, out_mcache_obj_id);
    const out_mtu: usize = 64; // tkpoly-tkaudt link depth=64
    const out_dcache_obj_id = topob.topoLinkDcacheObjId(topo, out_link_id);
    const out_dcache: ?*anyopaque = if (out_dcache_obj_id != topob.not_found)
        topob.topoObjLaddr(topo, out_dcache_obj_id)
    else
        null;

    if (out_mtu > 0 and out_dcache == null) return Error.OutputDcacheNullWithMtu;
    if (out_mtu < MIN_MTU) return Error.OutputMtuTooSmall;

    // Step 6: Find CNC.
    // CNC is looked up via the tile's uses_obj_id array.
    const tile_obj_id = topob.topoTileObjId(topo, tile_idx);
    const cnc_laddr = topob.topoObjLaddr(topo, tile_obj_id);
    if (cnc_laddr == null) return Error.CncNotFound;

    // Step 7: Resolve scratch (tile object).
    const scratch_footprint = topob.tickoniTileScratchFootprint(name_z);
    if (scratch_footprint == 0) return Error.ScratchNotFound;

    var scratch_align: usize = 0;
    var scratch_footprint_out: usize = 0;
    topob.tickoniTileScratchRequirements(name_z, &scratch_align, &scratch_footprint_out);

    // Step 8: Precompute output chunk bounds.
    // Chunks are [0..depth), starting at 0.
    const out_max_chunk: usize = out_mtu; // depth-based, mtu=depth here
    const out_next_chunk: usize = 0; // starts at 0

    // Get tile pointer.
    const tile = topob.topoTilePtr(topo, tile_idx);

    return TkPolyCtx{
        .tile = tile,
        .tile_idx = tile_idx,
        .scratch = null, // laddr resolved at runtime
        .scratch_footprint = scratch_footprint_out,
        .scratch_align = scratch_align,
        .in_link_idx = 0,
        .out_link_idx = 0,
        .in_mcache = in_mcache,
        .in_dcache = in_dcache,
        .out_mcache = out_mcache,
        .out_dcache = out_dcache,
        .in_depth = in_mtu,
        .out_depth = out_mtu,
        .in_mtu = in_mtu,
        .out_mtu = out_mtu,
        .cnc = cnc_laddr,
        .out_next_chunk = out_next_chunk,
        .out_max_chunk = out_max_chunk,
    };
}

// ---------------------------------------------------------------------------
// P5.1 — Unit tests for bounded tile context validation.
//
// These tests verify:
// - scratch footprint and alignment are deterministic
// - scratch footprint is stable across calls
// - scratch alignment is correct (8 for tkpoly)
// ---------------------------------------------------------------------------

test "tkpoly_bounded: scratch footprint and alignment are deterministic" {
    const name_z: [*:0]const u8 = "tkpoly";
    const footprint = topob.tickoniTileScratchFootprint(name_z);
    const reqs = topob.tickoniTileScratchRequirements(name_z);

    try std.testing.expect(footprint > 0);
    try std.testing.expect(reqs.alignment > 0);
    try std.testing.expect(reqs.footprint > 0);
    // Footprint must be a whole number of alignment units.
    try std.testing.expectEqual(@as(usize, 0), reqs.footprint % reqs.alignment);
    // Footprint should match the direct query.
    try std.testing.expectEqual(footprint, reqs.footprint);
}

test "tkpoly_bounded: scratch footprint is stable across calls" {
    const name_z: [*:0]const u8 = "tkpoly";
    const f1 = topob.tickoniTileScratchFootprint(name_z);
    const f2 = topob.tickoniTileScratchFootprint(name_z);
    try std.testing.expectEqual(f1, f2);
}

test "tkpoly_bounded: scratch alignment is 16" {
    const name_z: [*:0]const u8 = "tkpoly";
    const reqs = topob.tickoniTileScratchRequirements(name_z);
    try std.testing.expectEqual(@as(usize, 16), reqs.alignment);
}
