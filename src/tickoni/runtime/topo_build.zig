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

/// Keep topology construction diagnostics disabled in normal builds.
pub const topo_build_debug: bool = false;

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

pub const BuiltTopo = struct {
    buf: []align(128) u8,
    topo: *Topo,
    wksp_idx: usize,
    /// Index of the metric workspace in the topology's workspace list.
    metric_wksp_idx: usize,
    /// Index of the metric_in workspace in the topology's workspace list.
    metric_in_wksp_idx: usize,
    /// Tile index of tkmetr (if present), otherwise not_found.
    metric_tile_idx: usize,
    /// Object id for the metric tile's scratch space (fd_metric_ctx_t +
    /// fd_http_server).  Only populated when metric_tile_idx != not_found.
    metric_tile_obj_id: usize,
    /// Per-tile cnc object id, indexed the same as Topology.tiles.
    cnc_obj_id: []usize,
    /// Per-channel object ids, indexed the same as Topology.channels.
    link_obj_id: []LinkObjIds,

    pub fn deinit(self: *BuiltTopo, allocator: std.mem.Allocator) void {
        allocator.free(self.cnc_obj_id);
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

    const size = c_abi.topob.topoSizeof();
    if (topo_build_debug) std.debug.print("topo_build.build: size={d} align={d}\n", .{ size, topo_alloc_align.toByteUnits() });

    const buf = try allocator.alignedAlloc(u8, topo_alloc_align, size);
    errdefer allocator.free(buf);

    if (topo_build_debug) std.debug.print("topo_build.build: allocated buf ptr={x} len={d}\n", .{ @intFromPtr(buf.ptr), buf.len });

    var app_name_buf: [64]u8 = undefined;
    if (topo_build_debug) std.debug.print("topo_build.build: passing to topobNew ptr={x}\n", .{@intFromPtr(buf.ptr)});
    const topo = c_abi.topob.topobNew(buf.ptr, toZ(&app_name_buf, app_name)) orelse return error.TopobNewFailed;

    var wksp_name_buf: [64]u8 = undefined;
    const wksp_idx = c_abi.topob.topobWksp(topo, toZ(&wksp_name_buf, workspace_name));
    var wksp_name_z_buf: [64]u8 = undefined;
    const wksp_name_z = toZ(&wksp_name_z_buf, workspace_name);

    // v2.22.S4 Task 0: Scan tiles to detect if tkmetr is present BEFORE
    // creating workspaces, so we only create metric/metric_in when needed.
    var has_metric_tile = false;
    for (topo_desc.tiles) |t| {
        if (std.mem.eql(u8, t.id.slice(), "tkmetr")) {
            has_metric_tile = true;
            break;
        }
    }

    // v2.22.S4 Task 0: Create metric and metric_in workspaces only when
    // tkmetr is present, so links and tiles route correctly for all topologies.
    const metric_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, "metric") else c_abi.topob.not_found;
    const metric_in_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, "metric_in") else c_abi.topob.not_found;
    var metric_tile_idx: usize = c_abi.topob.not_found;

    // Links first, then tiles, then metric tile wiring (so in_cnt is
    // known), then autoLayout, then CNC objects, then channel wiring — a
    // fixed construction order so object ids stay deterministic across
    // parent/child rebuilds.
    const link_ids = try allocator.alloc(usize, topo_desc.channels.len);
    defer allocator.free(link_ids);
    for (topo_desc.channels, 0..) |ch, i| {
        var link_name_buf: [8]u8 = undefined;
        // Main pipeline links always stay in the app workspace so tiles can
        // communicate.  The metric tile's observer links (created later via
        // topobTileIn) read from metric_in workspace without moving the main
        // pipeline links.
        link_ids[i] = c_abi.topob.topobLink(topo, linkNameZ(&link_name_buf, i), wksp_name_z, ch.depth, ch.mtu, 1);
    }

    const cpu_idx_arr = try allocator.alloc(usize, topo_desc.tiles.len);
    errdefer allocator.free(cpu_idx_arr);
    for (topo_desc.tiles, 0..) |t, i| {
        var tile_name_buf: [16]u8 = undefined;
        // v2.22.S4 Task 0: tkmetr goes into metric workspace when present
        const tile_wksp_z = if (has_metric_tile and std.mem.eql(u8, t.id.slice(), "tkmetr")) "metric" else wksp_name_z;
        _ = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, t.id.slice()), tile_wksp_z, tile_wksp_z, 0);
        cpu_idx_arr[i] = tileCpuIdx(i, t.cpu_placement);
    }

    // Detect metric tile after all tiles are registered.
    if (has_metric_tile) {
        var tkmetr_name_buf: [16]u8 = undefined;
        const tkmetr_idx = c_abi.topob.topoFindTile(topo, toZ(&tkmetr_name_buf, "tkmetr"), 0);
        if (tkmetr_idx != c_abi.topob.not_found) {
            metric_tile_idx = tkmetr_idx;
            if (topo_build_debug) std.debug.print("topo_build: detected tkmetr tile at idx={d}, metric_wksp={d}, metric_in_wksp={d}\n", .{
                metric_tile_idx, metric_wksp_idx, metric_in_wksp_idx });
        } else {
            if (topo_build_debug) std.debug.print("topo_build: tkmetr NOT found in topology\n", .{});
        }
    } else {
        if (topo_build_debug) std.debug.print("topo_build: no tkmetr tile in topology\n", .{});
    }

    // v2.22.S4 Task 0: Wire each tile's output links into the metric tile
    // via the metric_in workspace BEFORE topobAutoLayout so that the
    // metric tile's in_cnt is set correctly by the layout engine.
    if (metric_tile_idx != c_abi.topob.not_found) {
        for (topo_desc.channels, 0..) |_, i| {
            var tile_name_buf: [16]u8 = undefined;
            var in_name_buf: [16]u8 = undefined;
            var link_name_buf: [8]u8 = undefined;
            const link_name_z = linkNameZ(&link_name_buf, i);
            // Connect this link into the metric tile's inputs from metric_in workspace
            _ = c_abi.topob.topobTileIn(topo, toZ(&tile_name_buf, "tkmetr"), 0, toZ(&in_name_buf, "metric_in"), link_name_z, 0, true, true);
        }
    }

    c_abi.topob.topobAutoLayout(topo, @as([*]const usize, cpu_idx_arr.ptr));
    allocator.free(cpu_idx_arr);

    // Set per-tile scratch footprint properties so tile_footprint() in
    // topob.c can query them.  Only tkmetr has a non-default footprint;
    // every other tile gets 1UL (which the property setter silently skips
    // since 1UL == the default).
    const scratch_key: [*:0]const u8 = "tickoni.scratch_footprint";
    for (topo_desc.tiles) |t| {
        var tile_name_buf: [8]u8 = undefined;
        const fp = c_abi.topob.tickoniTileScratchFootprint(
            toZ(&tile_name_buf, t.id.slice()),
        );
        if (fp > 1) {
            c_abi.topob.topobSetTileObjPropertyUlong(
                topo,
                toZ(&tile_name_buf, t.id.slice()),
                0,
                scratch_key,
                fp,
            );
        }
    }

    const cnc_obj_id = try allocator.alloc(usize, topo_desc.tiles.len);
    errdefer allocator.free(cnc_obj_id);
    for (0..topo_desc.tiles.len) |i| {
        // v2.22.S4 Task 0: CNC objects stay in app workspace for all tiles
        const obj_id = c_abi.topob.topobObj(topo, "cnc", wksp_name_z);
        c_abi.topob.topobTileUses(topo, i, obj_id, true);
        cnc_obj_id[i] = obj_id;
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

    // DEBUG: print workspace -> object mapping before finish
    if (topo_build_debug) {
        std.debug.print("topo_build: calling topobDebugWkspObjIds\n", .{});
        c_abi.topob.topobDebugWkspObjIds(topo);
    }

    const metric_tile_obj_id = if (metric_tile_idx != c_abi.topob.not_found)
        c_abi.topob.topoTileObjId(topo, metric_tile_idx)
    else
        0;

    c_abi.topob.topobFinish(topo);

    if (metric_tile_idx != c_abi.topob.not_found) {
        c_abi.topob.topoTileSetMetricPort(topo, metric_tile_idx, metric_port);
    }

    return .{
        .buf = buf,
        .topo = topo,
        .wksp_idx = wksp_idx,
        .metric_wksp_idx = metric_wksp_idx,
        .metric_in_wksp_idx = metric_in_wksp_idx,
        .metric_tile_idx = metric_tile_idx,
        .metric_tile_obj_id = metric_tile_obj_id,
        .cnc_obj_id = cnc_obj_id,
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

    try std.testing.expectEqual(@as(usize, 5), built.cnc_obj_id.len);

    var name_buf: [8]u8 = undefined;
    const tkaudt_id = c_abi.topob.topoFindTile(built.topo, toZ(&name_buf, "tkaudt"), 0);
    try std.testing.expect(tkaudt_id != c_abi.topob.not_found);
}

test "concreteWorkspaceName matches Firedancer join naming" {
    var buf: [concrete_workspace_name_cap]u8 = undefined;
    const name = try concreteWorkspaceName(&buf, "tkpay0");
    try std.testing.expectEqualStrings("tickoni_tkpay0.wksp", name);
}
