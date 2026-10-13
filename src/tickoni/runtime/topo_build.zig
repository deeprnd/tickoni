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
const tile = @import("tile.zig");

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
    const log = logger.get();
    log.enter("topo_build", "concreteWorkspaceName");
    defer log.exit("topo_build", "concreteWorkspaceName");
    const printed = try std.fmt.bufPrint(buf[0 .. buf.len - 1], "{s}_{s}.wksp", .{ app_name, workspace_name });
    buf[printed.len] = 0;
    // Verify the concrete name matches the Firedancer join format.
    std.debug.assert(std.mem.startsWith(u8, buf[0..printed.len], "tickoni_"));
    std.debug.assert(std.mem.endsWith(u8, buf[0..printed.len], ".wksp"));
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

/// Per-tile metadata indexed by Firedancer tile idx.
pub const BuiltTopoTileInfo = struct {
    tile_id: tile.TileId,
    cpu_placement: cpu_placement.CpuPlacement,
};

pub const BuiltTopo = struct {
    buf: []align(128) u8,
    topo: *Topo,
    wksp_idx: usize,
    /// Index of the metric workspace in the topology's workspace list.
    metric_wksp_idx: usize,
    /// Index of the metric_in workspace in the topology's workspace list.
    metric_in_wksp_idx: usize,
    /// Tile index of metric (if present), otherwise not_found.
    metric_tile_idx: usize,
    /// Object id for the metric tile's scratch space (fd_metric_ctx_t +
    /// fd_http_server).  Only populated when metric_tile_idx != not_found.
    metric_tile_obj_id: usize,
    /// Per-tile cnc object id, indexed by Firedancer tile idx.
    cnc_obj_id: []usize,
    /// Per-channel object ids, indexed the same as Topology.channels.
    link_obj_id: []LinkObjIds,
    /// Per-tile metadata indexed by Firedancer tile idx, allocated and owned
    /// by BuiltTopo.
    ///
    /// The source of truth for tile metadata is Topology.tiles (the descriptor
    /// array). BuiltTopo.tile_infos re-indexes tile_id and cpu_placement so
    /// that code iterating by Firedancer tile idx gets the correct values
    /// without guessing from descriptor position (which breaks when
    /// metric/tkdiag swap reorders indices 6/7).
    tile_infos: []BuiltTopoTileInfo,

    pub fn deinit(self: *BuiltTopo, allocator: std.mem.Allocator) void {
        allocator.free(self.cnc_obj_id);
        allocator.free(self.link_obj_id);
        allocator.free(self.tile_infos);
        allocator.free(self.buf);
    }

    /// Returns the Firedancer index for a tile ID, or not_found.
    pub fn tileIdxById(self: *const BuiltTopo, tile_id: tile.TileId) usize {
        for (self.tile_infos, 0..) |info, i| {
            if (info.tile_id.eql(tile_id)) return i;
        }
        return c_abi.topob.not_found;
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
    const log = logger.get();
    log.enter("topo_build", "build");
    defer log.exit("topo_build", "build");
    std.debug.assert(c_abi.topob.topoAlignof() <= topo_alloc_align.toByteUnits());

    const size = c_abi.topob.topoSizeof();
    log.kvFmt("topo_build", "build", "size={d} align={d}", .{ size, topo_alloc_align.toByteUnits() });

    const buf = try allocator.alignedAlloc(u8, topo_alloc_align, size);
    errdefer allocator.free(buf);

    log.kvFmt("topo_build", "build", "allocated buf ptr={x} len={d}", .{ @intFromPtr(buf.ptr), buf.len });

    var app_name_buf: [64]u8 = undefined;
    log.kvFmt("topo_build", "build", "passing to topobNew ptr={x}", .{@intFromPtr(buf.ptr)});
    const topo = c_abi.topob.topobNew(buf.ptr, toZ(&app_name_buf, app_name)) orelse return error.TopobNewFailed;

    var wksp_name_buf: [64]u8 = undefined;
    log.kvFmt("topo_build", "build", "calling topobWksp(name={s})", .{workspace_name});
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
    // metric is present, so links and tiles route correctly for all topologies.
    if (has_metric_tile) log.kvFmt("topo_build", "build", "calling topobWksp(metric)", .{});
    const metric_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, "metric") else c_abi.topob.not_found;
    if (has_metric_tile) log.kvFmt("topo_build", "build", "calling topobWksp(metric_in)", .{});
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
        log.kvFmt("topo_build", "build", "calling topobLink(name=ch{d}, wksp={s}, depth={d}, mtu={d})", .{ i, wksp_name_z, ch.depth, ch.mtu });
        link_ids[i] = c_abi.topob.topobLink(topo, linkNameZ(&link_name_buf, i), wksp_name_z, ch.depth, ch.mtu, 1);
        // Verify link was registered with expected name (catches link name typos).
        log.kvFmt("topo_build", "build", "topoValidateLinkExists(name=ch{d})", .{i});
        std.debug.assert(c_abi.topob.topoValidateLinkExists(topo, linkNameZ(&link_name_buf, i)));
    }

    // Register tiles: all non-metric tiles go into the app workspace.
    // The metric tile (if present) goes into the "metric" workspace.
    // Capture cpu placements and Firedancer index mapping during register
    // so tile_infos can be built without looking up topo_desc after the build
    // (topo_desc is a one-time input, not reused).
    const tile_placements = try allocator.alloc(cpu_placement.CpuPlacement, topo_desc.tiles.len);
    defer allocator.free(tile_placements);
    const cpu_idx_arr = try allocator.alloc(usize, topo_desc.tiles.len);
    defer allocator.free(cpu_idx_arr);
    const fd_tile_idx_by_desc = try allocator.alloc(usize, topo_desc.tiles.len);
    defer allocator.free(fd_tile_idx_by_desc);
    var non_metric_count: usize = 0;
    for (topo_desc.tiles, 0..) |t, i| {
        cpu_idx_arr[i] = tileCpuIdx(i, t.cpu_placement);
        tile_placements[i] = t.cpu_placement;
        if (std.mem.eql(u8, t.id.slice(), "metric")) {
            fd_tile_idx_by_desc[i] = c_abi.topob.not_found;
            continue;
        }
        fd_tile_idx_by_desc[i] = non_metric_count;
        non_metric_count += 1;
        var tile_name_buf: [16]u8 = undefined;
        log.kvFmt("topo_build", "build", "calling topobTile(id={s}, wksp={s})", .{ t.id.slice(), wksp_name_z });
        _ = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, t.id.slice()), wksp_name_z, wksp_name_z, 0);
        // Verify tile was registered with expected name (catches tile name typos).
        log.kvFmt("topo_build", "build", "topoValidateTileExists(id={s})", .{t.id.slice()});
        std.debug.assert(c_abi.topob.topoValidateTileExists(topo, toZ(&tile_name_buf, t.id.slice())));
    }
    if (has_metric_tile) {
        var tile_name_buf: [16]u8 = undefined;
        log.kvFmt("topo_build", "build", "calling topobTile(metric, metric, metric)", .{});
        _ = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, "metric"), "metric", "metric", 0);
        // Verify metric tile was registered.
        log.kvFmt("topo_build", "build", "topoValidateTileExists(metric)", .{});
        std.debug.assert(c_abi.topob.topoValidateTileExists(topo, toZ(&tile_name_buf, "metric")));
        // Metric tile is always last in Firedancer order.
        for (topo_desc.tiles, 0..) |t, d_idx| {
            if (std.mem.eql(u8, t.id.slice(), "metric")) {
                fd_tile_idx_by_desc[d_idx] = non_metric_count;
                break;
            }
        }
    }

    if (has_metric_tile) {
        var metric_name_buf: [16]u8 = undefined;
        log.kvFmt("topo_build", "build", "calling topoFindTile(metric)", .{});
        const metric_idx = c_abi.topob.topoFindTile(topo, toZ(&metric_name_buf, "metric"), 0);
        if (metric_idx != c_abi.topob.not_found) {
            metric_tile_idx = metric_idx;
            log.kvFmt("topo_build", "build", "detected metric tile at idx={d}, metric_wksp={d}, metric_in_wksp={d}", .{ metric_tile_idx, metric_wksp_idx, metric_in_wksp_idx });
        } else {
            log.kvFmt("topo_build", "build", "metric tile NOT found in topology", .{});
        }
    } else {
        log.kvFmt("topo_build", "build", "no metric tile in topology", .{});
    }

    // v2.22.S4 Task 0: Wire each tile's output links into the metric tile
    // via the metric_in workspace BEFORE topobAutoLayout so that the
    // metric tile's in_cnt is set correctly by the layout engine.
    if (metric_tile_idx != c_abi.topob.not_found) {
        log.kvFmt("topo_build", "build", "calling topobTileIn(metric, metric_in, ch0..ch{d})", .{topo_desc.channels.len - 1});
        for (topo_desc.channels, 0..) |_, i| {
            var tile_name_buf: [16]u8 = undefined;
            var in_name_buf: [16]u8 = undefined;
            var link_name_buf: [8]u8 = undefined;
            const link_name_z = linkNameZ(&link_name_buf, i);
            // Connect this link into the metric tile's inputs from metric_in workspace
            _ = c_abi.topob.topobTileIn(topo, toZ(&tile_name_buf, "metric"), 0, toZ(&in_name_buf, "metric_in"), link_name_z, 0, true, true);
        }
        log.kvFmt("topo_build", "build", "done topobTileIn for metric tile", .{});
    }

    log.kvFmt("topo_build", "build", "calling topobAutoLayout(tile_cnt={d})", .{topo_desc.tiles.len});
    c_abi.topob.topobAutoLayout(topo, @as([*]const usize, cpu_idx_arr.ptr));
    log.kvFmt("topo_build", "build", "topobAutoLayout completed", .{});

    // Set per-tile scratch footprint and alignment properties so
    // tile_footprint() / tile_align() in topob.c can query them.
    // Only the metric tile has a non-default footprint; every other
    // tile gets 1UL (which the property setter silently skips since
    // 1UL == the default).
    const scratch_footprint_key: [*:0]const u8 = "tickoni.scratch_footprint";
    const scratch_align_key: [*:0]const u8 = "tickoni.scratch_align";
    for (topo_desc.tiles) |t| {
        var tile_name_buf: [8]u8 = undefined;
        const reqs = c_abi.topob.tickoniTileScratchRequirements(toZ(&tile_name_buf, t.id.slice()));
        if (reqs.footprint > 1) {
            log.kvFmt("topo_build", "build", "calling topobSetTileObjPropertyUlong({s}, footprint={d}, align={d})", .{ t.id.slice(), reqs.footprint, reqs.alignment });
            c_abi.topob.topobSetTileObjPropertyUlong(topo, toZ(&tile_name_buf, t.id.slice()), 0, scratch_footprint_key, reqs.footprint);
            c_abi.topob.topobSetTileObjPropertyUlong(topo, toZ(&tile_name_buf, t.id.slice()), 0, scratch_align_key, reqs.alignment);
        }
    }

    const cnc_obj_id = try allocator.alloc(usize, topo_desc.tiles.len);
    errdefer allocator.free(cnc_obj_id);
    // v2.14.S8.T6: create one CNC per tile so the supervisor can detect
    // per-tile heartbeat staleness independently.  Each tile writes to
    // its own CNC; the supervisor sends BOOT/HALT to each tile's CNC.
    // Call topobObj separately per tile — fd_topob_obj creates a distinct
    // object each time — so each tile gets its own CNC sharing the "cnc"
    // type string (needed by tk_topo_find_tile_obj in topob.c, which
    // matches the metric tile's shutdown CNC lookup).
    //
    // CRITICAL: `topobTileUses` expects Firedancer tile index, not descriptor
    // array index.  Use `fd_tile_idx_by_desc` to map descriptor idx →
    // Firedancer idx before calling topobTileUses.  Without this mapping,
    // tiles registered out-of-order (metric at desc 6 → Firedancer 7) get
    // their CNC registered under the wrong Firedancer tile, so
    // tk_topo_find_tile_obj(topo, "metric", "cnc") returns ULONG_MAX and
    // boot_ts never gets written.
    for (topo_desc.tiles, 0..) |_, desc_idx| {
        const fd_idx = fd_tile_idx_by_desc[desc_idx];
        log.kvFmt("topo_build", "build", "calling topobObj(tile_desc={d}, fd_idx={d}, type=cnc)", .{ desc_idx, fd_idx });
        const cnc_obj = c_abi.topob.topobObj(topo, "cnc", wksp_name_z);
        log.kvFmt("topo_build", "build", "calling topobTileUses(fd_idx={d}, cnc_obj={d})", .{ fd_idx, cnc_obj });
        c_abi.topob.topobTileUses(topo, fd_idx, cnc_obj, true);
        cnc_obj_id[fd_idx] = cnc_obj;
    }
    log.kvFmt("topo_build", "build", "done CNC loop (tile_cnt={d})", .{topo_desc.tiles.len});

    const link_obj_id = try allocator.alloc(LinkObjIds, topo_desc.channels.len);
    errdefer allocator.free(link_obj_id);
    for (topo_desc.channels, 0..) |ch, i| {
        var src_name_buf: [8]u8 = undefined;
        var dst_name_buf: [8]u8 = undefined;
        var link_name_buf: [8]u8 = undefined;
        const src_name_z = toZ(&src_name_buf, topo_desc.tiles[ch.src_idx].id.slice());
        const dst_name_z = toZ(&dst_name_buf, topo_desc.tiles[ch.dst_idx].id.slice());
        const link_name_z = linkNameZ(&link_name_buf, i);
        log.kvFmt("topo_build", "build", "calling topobTileIn(dst={s}, wksp={s}, link=ch{d})", .{ dst_name_z, wksp_name_z, i });
        const fseq_obj_id = c_abi.topob.topobTileIn(topo, dst_name_z, 0, wksp_name_z, link_name_z, 0, true, true);
        log.kvFmt("topo_build", "build", "calling topobTileOut(src={s}, link=ch{d})", .{ src_name_z, i });
        c_abi.topob.topobTileOut(topo, src_name_z, 0, link_name_z, 0);
        // Verify channel wiring: src tile has out_cnt >= 1, dst tile has in_cnt >= 1.
        // Catches stale src_idx/dst_idx that reference deleted tiles.
        log.kvFmt("topo_build", "build", "calling topoFindTile(src={s})", .{src_name_z});
        const src_tile_id = c_abi.topob.topoFindTile(topo, src_name_z, 0);
        log.kvFmt("topo_build", "build", "calling topoFindTile(dst={s})", .{dst_name_z});
        const dst_tile_id = c_abi.topob.topoFindTile(topo, dst_name_z, 0);
        std.debug.assert(src_tile_id != c_abi.topob.not_found);
        std.debug.assert(dst_tile_id != c_abi.topob.not_found);
        log.kvFmt("topo_build", "build", "calling topoTileOutputCount(tile={d})", .{src_tile_id});
        const src_out_cnt = c_abi.topob.topoTileOutputCount(topo, src_tile_id);
        log.kvFmt("topo_build", "build", "calling topoTileInputCount(tile={d})", .{dst_tile_id});
        const dst_in_cnt = c_abi.topob.topoTileInputCount(topo, dst_tile_id);
        std.debug.assert(src_out_cnt > 0);
        std.debug.assert(dst_in_cnt > 0);
        log.kvFmt("topo_build", "build", "calling topoLinkMcacheObjId(link={d})", .{link_ids[i]});
        const mcache_obj = c_abi.topob.topoLinkMcacheObjId(topo, link_ids[i]);
        log.kvFmt("topo_build", "build", "calling topoLinkDcacheObjId(link={d})", .{link_ids[i]});
        const dcache_obj = c_abi.topob.topoLinkDcacheObjId(topo, link_ids[i]);
        log.kvFmt("topo_build", "build", "calling topoLinkFseqObjId(link={d})", .{link_ids[i]});
        link_obj_id[i] = .{
            .mcache_obj_id = mcache_obj,
            .dcache_obj_id = dcache_obj,
            .fseq_obj_id = fseq_obj_id,
        };
        log.kvFmt("topo_build", "build", "done channel ch{d} (src={s}->dst={s})", .{ i, src_name_z, dst_name_z });
    }
    log.kvFmt("topo_build", "build", "done channel wiring (channel_cnt={d})", .{topo_desc.channels.len});

    // Print workspace -> object mapping before finish
    log.kvFmt("topo_build", "build", "calling topobDebugWkspObjIds", .{});
    c_abi.topob.topobDebugWkspObjIds(topo);
    log.kvFmt("topo_build", "build", "topobDebugWkspObjIds returned", .{});

    const metric_tile_obj_id = if (metric_tile_idx != c_abi.topob.not_found)
        c_abi.topob.topoTileObjId(topo, metric_tile_idx)
    else
        0;

    if (metric_tile_idx != c_abi.topob.not_found)
        log.kvFmt("topo_build", "build", "calling topoTileObjId(metric_tile_idx={d})", .{metric_tile_idx});
    log.kvFmt("topo_build", "build", "calling topobFinish()", .{});
    c_abi.topob.topobFinish(topo);
    log.kvFmt("topo_build", "build", "topobFinish returned OK", .{});

    // Verify all object offsets are valid after topobFinish (catches
    // layout/offset computation bugs before any tile crashes).
    std.debug.assert(c_abi.topob.topoValidateTileObjectOffsets(topo));

    if (metric_tile_idx != c_abi.topob.not_found) {
        c_abi.topob.topoTileSetMetricPort(topo, metric_tile_idx, metric_port);
    }

    // Build tile_infos indexed by Firedancer tile idx, using the pre-captured
    // fd_tile_idx_by_desc mapping. No lookup into topo_desc after the build
    // — topo_desc was a one-time input.
    const tile_infos_cnt = topo_desc.tiles.len;
    const tile_infos = try allocator.alloc(BuiltTopoTileInfo, tile_infos_cnt);
    for (tile_infos, 0..) |*info, firedancer_idx| {
        const name_z = c_abi.topob.topoTileName(topo, @as(c_uint, @intCast(firedancer_idx)));
        // Cast to opaque pointer slice to index into the NUL-terminated string.
        const name_raw: [*]const u8 = @ptrCast(name_z);
        var len: usize = 0;
        while (len < 16) : (len += 1) {
            if (name_raw[len] == 0) break;
        }
        var name_buf: [16]u8 = undefined;
        @memcpy(name_buf[0..len], name_raw);
        const tile_id = tile.TileId.parse(name_buf[0..len]) catch unreachable;
        // Find the descriptor whose Firedancer index matches this one.
        for (fd_tile_idx_by_desc, 0..) |fd_idx, d_idx| {
            if (fd_idx == firedancer_idx) {
                info.* = .{
                    .tile_id = tile_id,
                    .cpu_placement = tile_placements[d_idx],
                };
                break;
            }
        }
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
        .tile_infos = tile_infos,
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

    var built = try build(std.testing.allocator, topo_desc, "tkpay0");
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
