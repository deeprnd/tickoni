/// v2.14.S8.T12: builds a real Firedancer fd_topo_t from Tickoni's own
/// Topology (tiles + channels), driving it through c_abi.topob's fd_topob
/// wrappers. Called identically by the supervisor (parent, to pre-format
/// the shared workspace) and by each self-exec'd tile process (child, to
/// re-derive an identical topology and find its own tile) — see the
/// v2.14.S8.T12 "topology handoff" finding: Tickoni rebuilds the topology
/// in every process rather than serializing fd_topo_t through a handoff
/// file, matching Firedancer's own self-exec convention.
///
/// Does not create the workspace or instantiate any object content —
/// that's the caller's job via c_abi.topob.topoCreateWorkspace/
/// topoWkspNew (parent-only, once). This function only builds the
/// in-memory topology description and calls topobFinish, which computes
/// every object's offset deterministically from the construction order
/// below — the parent and every child must call this with identical
/// inputs to get byte-identical offsets.
const std = @import("std");
const c_abi = @import("c_abi");
const topology = @import("topology.zig");
const cpu_placement = @import("cpu_placement.zig");
const logger = @import("logger");

const Topo = c_abi.topob.Topo;

/// Shared app_name for every build() call across the parent and every
/// child (must be identical for fd_topo_join_workspace's "%s_%s.wksp"
/// naming — see supervisor.zig's workspace_name_z construction — to find
/// the same region both sides look up).
pub const app_name: []const u8 = "tickoni";
pub const concrete_workspace_name_cap: usize = 64;

/// Firedancer joins workspace files by the concrete `"<app>_<wksp>.wksp"`
/// region name, not by Tickoni's short workspace label alone. The
/// supervisor must create exactly this filename so child-side
/// `fd_topo_join_workspace()` resolves the same region after rebuilding the
/// topology.
pub fn concreteWorkspaceName(buf: []u8, workspace_name: []const u8) ![:0]const u8 {
    const printed = try std.fmt.bufPrint(buf[0 .. buf.len - 1], "{s}_{s}.wksp", .{ app_name, workspace_name });
    buf[printed.len] = 0;
    return @ptrCast(buf[0..printed.len :0]);
}

/// fd_topo_t's real alignment isn't knowable from Zig (opaque type) but is
/// small in practice (char-array/ulong/union-of-ulongs fields only) — 128
/// is a safe, generous bound matching this codebase's existing Tango
/// alignment convention (e.g. cnc_align). Checked against the real
/// runtime value in build() below; fails closed if Firedancer's actual
/// alignment ever exceeds this.
const topo_alloc_align: std.mem.Alignment = .fromByteUnits(128);

/// ULONG_MAX sentinel Firedancer uses for "no CPU pinned" (see
/// src/disco/topo/fd_topo_run.c's `tile->cpu_idx<65535UL` floating check).
const cpu_idx_floating: usize = std.math.maxInt(usize);

/// mcache/dcache/fseq object ids for one channel — fseq is a per-(tile,
/// in-link) object in fd_topob's model, not per-link, but Phase 0's
/// linear chain has exactly one consumer per channel, so this is still a
/// clean 1:1 mapping from Topology.channels' index.
pub const LinkObjIds = struct {
    mcache_obj_id: usize,
    dcache_obj_id: usize,
    fseq_obj_id: usize,
};

/// The stable bridge from a Tickoni descriptor position to Firedancer's
/// topology and object indices.  `tiles` is indexed exclusively by the
/// descriptor index in `Topology.tiles`; callers must use `topo_tile_idx` for
/// every Firedancer topology operation.
pub const BuiltTile = struct {
    topo_tile_idx: usize,
    tile_obj_id: usize,
    cnc_obj_id: usize,
};

pub const BuiltTopo = struct {
    buf: []align(128) u8,
    topo: *Topo,
    wksp_idx: usize,
    /// Index of the metric workspace in the topology's workspace list.
    metric_wksp_idx: usize,
    /// Index of the metric_in workspace in the topology's workspace list.
    metric_in_wksp_idx: usize,
    /// Descriptor index of tkmetr (if present), otherwise not_found.
    metric_desc_idx: usize,
    /// Stable descriptor-indexed records for all topology tiles.
    tiles: []BuiltTile,
    /// Per-channel object ids, indexed the same as Topology.channels.
    link_obj_id: []LinkObjIds,

    pub fn deinit(self: *BuiltTopo, allocator: std.mem.Allocator) void {
        allocator.free(self.tiles);
        allocator.free(self.link_obj_id);
        allocator.free(self.buf);
    }
};

fn toZ(buf: []u8, s: []const u8) [*:0]const u8 {
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return @ptrCast(buf.ptr);
}

fn linkNameZ(buf: []u8, idx: usize) [*:0]const u8 {
    const s = std.fmt.bufPrint(buf[0 .. buf.len - 1], "ch{d}", .{idx}) catch unreachable;
    buf[s.len] = 0;
    return @ptrCast(buf.ptr);
}

fn tileCpuIdx(tile_idx: usize, placement: cpu_placement.CpuPlacement) usize {
    return switch (placement) {
        .exclusive => |cpu| cpu,
        .shared => |cpu| cpu + @as(usize, @intCast(tile_idx)),
        .floating => cpu_idx_floating,
    };
}

pub fn build(
    allocator: std.mem.Allocator,
    topo_desc: topology.Topology,
    workspace_name: []const u8,
    metric_port: u16,
) !BuiltTopo {
    std.debug.assert(c_abi.topob.topoAlignof() <= topo_alloc_align.toByteUnits());

    const log = logger.get();

    const size = c_abi.topob.topoSizeof();
    log.kvFmt("topo_build", "build", "size={d} align={d}", .{ size, topo_alloc_align.toByteUnits() });

    const buf = try allocator.alignedAlloc(u8, topo_alloc_align, size);
    errdefer allocator.free(buf);

    log.kvFmt("topo_build", "build", "allocated buf ptr={x} len={d}", .{ @intFromPtr(buf.ptr), buf.len });

    var app_name_buf: [64]u8 = undefined;
    log.kvFmt("topo_build", "build", "passing to topobNew ptr={x}", .{@intFromPtr(buf.ptr)});
    const topo = c_abi.topob.topobNew(buf.ptr, toZ(&app_name_buf, app_name)) orelse return error.TopobNewFailed;

    var wksp_name_buf: [64]u8 = undefined;
    const wksp_idx = c_abi.topob.topobWksp(topo, toZ(&wksp_name_buf, workspace_name));
    var wksp_name_z_buf: [64]u8 = undefined;
    const wksp_name_z = toZ(&wksp_name_z_buf, workspace_name);

    // v2.22.S4 Task 0: Scan tiles to detect if metric tile is present BEFORE
    // creating workspaces, so we only create metric/metric_in when needed.
    var has_metric_tile = false;
    for (topo_desc.tiles) |t| {
        if (std.mem.eql(u8, t.id.slice(), "metric")) {
            has_metric_tile = true;
            break;
        }
    }

    // v2.22.S4 Task 0: Create metric and metric_in workspaces only when
    // tkmetr is present, so links and tiles route correctly for all topologies.
    const metric_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, "metric") else c_abi.topob.not_found;
    const metric_in_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, "metric_in") else c_abi.topob.not_found;
    var metric_desc_idx: usize = c_abi.topob.not_found;

    // Links first, then tiles, then autoLayout, then CNC objects, then
    // channel wiring — a
    // fixed construction order so object ids stay deterministic across
    // parent/child rebuilds.
    const link_ids = try allocator.alloc(usize, topo_desc.channels.len);
    defer allocator.free(link_ids);
    for (topo_desc.channels, 0..) |ch, i| {
        var link_name_buf: [8]u8 = undefined;
        // Main pipeline links always stay in the app workspace.
        link_ids[i] = c_abi.topob.topobLink(topo, linkNameZ(&link_name_buf, i), wksp_name_z, ch.depth, ch.mtu, 1);
    }

    const cpu_idx_arr = try allocator.alloc(usize, topo_desc.tiles.len);
    errdefer allocator.free(cpu_idx_arr);
    const built_tiles = try allocator.alloc(BuiltTile, topo_desc.tiles.len);
    errdefer allocator.free(built_tiles);

    // Register strictly in descriptor order.  The tile workspace remains the
    // app workspace except for metric; all per-tile metric objects live in
    // metric_in for direct fd_prometheus_render_all observation.
    for (topo_desc.tiles, 0..) |t, i| {
        var tile_name_buf: [16]u8 = undefined;
        const is_metric = std.mem.eql(u8, t.id.slice(), "metric");
        const tile_wksp = if (is_metric) "metric" else wksp_name_z;
        const metrics_wksp = if (has_metric_tile) "metric_in" else wksp_name_z;
        const topo_tile_idx = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, t.id.slice()), tile_wksp, metrics_wksp, 0);
        built_tiles[i] = .{
            .topo_tile_idx = topo_tile_idx,
            .tile_obj_id = c_abi.topob.topoTileObjId(topo, topo_tile_idx),
            .cnc_obj_id = c_abi.topob.not_found,
        };
        cpu_idx_arr[topo_tile_idx] = tileCpuIdx(topo_tile_idx, t.cpu_placement);
        if (is_metric) metric_desc_idx = i;
    }

    c_abi.topob.topobAutoLayout(topo, @as([*]const usize, cpu_idx_arr.ptr));
    allocator.free(cpu_idx_arr);

    // Set both metric scratch properties before topobFinish. This build path
    // is shared by the parent and every child rebuild, so all processes derive
    // the same C-owned metric layout without reproducing it in Zig.
    if (metric_desc_idx != c_abi.topob.not_found) {
        const requirements = c_abi.topob.tickoniTileScratchRequirements("metric");
        const metric_tile = built_tiles[metric_desc_idx];
        c_abi.topob.topobSetObjPropertyUlong(topo, metric_tile.tile_obj_id, "tickoni.scratch_align", requirements.alignment);
        c_abi.topob.topobSetObjPropertyUlong(topo, metric_tile.tile_obj_id, "tickoni.scratch_footprint", requirements.footprint);
    }

    for (built_tiles) |*tile| {
        // CNC objects stay in app workspace for all tiles.
        const obj_id = c_abi.topob.topobObj(topo, "cnc", wksp_name_z);
        c_abi.topob.topobTileUses(topo, tile.topo_tile_idx, obj_id, true);
        tile.cnc_obj_id = obj_id;
    }

    const link_obj_id = try allocator.alloc(LinkObjIds, topo_desc.channels.len);
    errdefer allocator.free(link_obj_id);
    for (topo_desc.channels, 0..) |ch, i| {
        var src_name_buf: [8]u8 = undefined;
        var dst_name_buf: [8]u8 = undefined;
        var link_name_buf: [8]u8 = undefined;
        const src_name_z = toZ(&src_name_buf, topo_desc.tiles[ch.src_idx].id.slice());
        const dst_name_z = toZ(&dst_name_buf, topo_desc.tiles[ch.dst_idx].id.slice());
        const link_name_z = linkNameZ(&link_name_buf, i);
        const fseq_obj_id = c_abi.topob.topobTileIn(topo, dst_name_z, 0, wksp_name_z, link_name_z, 0, true, true);
        c_abi.topob.topobTileOut(topo, src_name_z, 0, link_name_z, 0);
        link_obj_id[i] = .{
            .mcache_obj_id = c_abi.topob.topoLinkMcacheObjId(topo, link_ids[i]),
            .dcache_obj_id = c_abi.topob.topoLinkDcacheObjId(topo, link_ids[i]),
            .fseq_obj_id = fseq_obj_id,
        };
    }

    // Print workspace -> object mapping before finish
    log.kvFmt("topo_build", "build", "calling topobDebugWkspObjIds", .{});
    c_abi.topob.topobDebugWkspObjIds(topo);

    c_abi.topob.topobFinish(topo);

    // Fail topology construction before the supervisor can spawn children if
    // the metric tile does not own an adequately sized and aligned object.
    if (metric_desc_idx != c_abi.topob.not_found and
        !c_abi.topob.topoValidateMetricScratch(topo))
    {
        return error.InvalidMetricScratchLayout;
    }

    if (metric_desc_idx != c_abi.topob.not_found) {
        c_abi.topob.topoTileSetMetricPort(topo, built_tiles[metric_desc_idx].topo_tile_idx, metric_port);
    }

    return .{
        .buf = buf,
        .topo = topo,
        .wksp_idx = wksp_idx,
        .metric_wksp_idx = metric_wksp_idx,
        .metric_in_wksp_idx = metric_in_wksp_idx,
        .metric_desc_idx = metric_desc_idx,
        .tiles = built_tiles,
        .link_obj_id = link_obj_id,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const tile_mod = @import("tile.zig");
const link_mod = @import("link.zig");

fn testTile(id: []const u8) tile_mod.TileDescriptor {
    return .{ .id = tile_mod.TileId.parse(id) catch unreachable, .name = id };
}

test "build produces a topology for the linear Phase 0 chain" {
    const tiles = [_]tile_mod.TileDescriptor{
        testTile("tkings"),
        testTile("tknorm"),
        testTile("tkdedu"),
        testTile("tkpoly"),
        testTile("tkaudt"),
    };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 7999);
    defer built.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), built.tiles.len);

    var name_buf: [8]u8 = undefined;
    const tkaudt_id = c_abi.topob.topoFindTile(built.topo, toZ(&name_buf, "tkaudt"), 0);
    try std.testing.expect(tkaudt_id != c_abi.topob.not_found);
}

test "descriptor-indexed records preserve metric identity and zero links" {
    const tiles = [_]tile_mod.TileDescriptor{
        .{ .id = tile_mod.TileId.parse("tkings") catch unreachable, .name = "ingest", .cpu_placement = .{ .exclusive = 2 } },
        .{ .id = tile_mod.TileId.parse("metric") catch unreachable, .name = "metric", .cpu_placement = .{ .exclusive = 3 } },
        .{ .id = tile_mod.TileId.parse("tkdiag") catch unreachable, .name = "diagnostic", .cpu_placement = .{ .exclusive = 4 } },
    };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 2, .depth = 64, .mtu = 128 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };
    var built = try build(std.testing.allocator, topo_desc, "identity", 7999);
    defer built.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), built.metric_desc_idx);
    try std.testing.expectEqual(@as(usize, 3), built.tiles.len);
    for (built.tiles, 0..) |tile, descriptor_idx| {
        try std.testing.expectEqual(descriptor_idx, tile.topo_tile_idx);
        try std.testing.expect(tile.cnc_obj_id != c_abi.topob.not_found);
        try std.testing.expectEqual(@as(usize, 2 + descriptor_idx), c_abi.topob.topoTileCpuIdx(built.topo, tile.topo_tile_idx));
    }

    const metric = built.tiles[built.metric_desc_idx];
    try std.testing.expectEqual(@as(usize, 0), c_abi.topob.topoTileInputCount(built.topo, metric.topo_tile_idx));
    try std.testing.expectEqual(@as(usize, 0), c_abi.topob.topoTileOutputCount(built.topo, metric.topo_tile_idx));
    try std.testing.expectEqual(@as(usize, 1), c_abi.topob.topoLinkConsumerCount(built.topo, 0));
}

test "concreteWorkspaceName matches Firedancer join naming" {
    var buf: [concrete_workspace_name_cap]u8 = undefined;
    const name = try concreteWorkspaceName(&buf, "tkpay0");
    try std.testing.expectEqualStrings("tickoni_tkpay0.wksp", name);
}
