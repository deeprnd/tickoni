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
const tile_ids = @import("tile_ids.zig");
const util = @import("util");

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
    /// Instance ordinal among tiles sharing `tile_id`; with it, the Firedancer
    /// `(name, kind_id)` identity of this tile.
    kind_id: u8,
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
    /// The committed-audit watermark fseq (tkaudt writes, tkagnt reads), or
    /// `not_found` when the topology has no tkaudt+tkagnt pair.
    audit_watermark_obj_id: usize,
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
        // Guard: free() on &.{} (empty inline array) is a stack address —
        // allocator reads garbage metadata and GPEs under kcov. Only free
        // slices that came from heap allocations (len > 0).
        // Zero slices after free so a second deinit() call is a safe no-op.
        if (self.cnc_obj_id.len > 0) {
            allocator.free(self.cnc_obj_id);
            self.cnc_obj_id = &.{};
        }
        if (self.link_obj_id.len > 0) {
            allocator.free(self.link_obj_id);
            self.link_obj_id = &.{};
        }
        if (self.tile_infos.len > 0) {
            allocator.free(self.tile_infos);
            self.tile_infos = &.{};
        }
        if (self.buf.len > 0) {
            allocator.free(self.buf);
            self.buf = &.{};
        }
    }

    /// Returns the Firedancer index of the first instance (kind_id 0) of a tile
    /// ID, or not_found. Use tileIdxByIdentity for a tile type that can have
    /// several processes, such as tkmodl.
    pub fn tileIdxById(self: *const BuiltTopo, tile_id: tile.TileId) usize {
        return self.tileIdxByIdentity(.{ .name = tile_id, .kind_id = 0 });
    }

    /// Returns the Firedancer index for an exact `(name, kind_id)` identity, or
    /// not_found.
    pub fn tileIdxByIdentity(self: *const BuiltTopo, identity: tile.TileIdentity) usize {
        for (self.tile_infos, 0..) |info, i| {
            if (info.tile_id.eql(identity.name) and info.kind_id == identity.kind_id) return i;
        }
        return c_abi.topob.not_found;
    }
};

/// linkNameZ formats a channel link name ("chN") into a caller-allocated buffer
/// and returns a null-terminated pointer.
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
    event_count: u64,
) !BuiltTopo {
    std.debug.print("[topo-build] ENTER build workspace={s}\n", .{workspace_name});
    const log = logger.get();
    log.enter("topo_build", "build");
    defer log.exit("topo_build", "build");

    // Firedancer assigns kind_id by registration order, which below is
    // descriptor order. A descriptor whose declared kind_id disagrees would be
    // wired to, and launched as, a different instance than the one it names.
    try topo_desc.validateIdentities();

    // tkdedu's scratch footprint is a function of event_count, so it has to be
    // pushed into the tile before any footprint query below. Both the
    // supervisor and every self-exec'd child reach this with the same value
    // (the supervisor from its run config, children from TopologySpec), which
    // is what keeps the two layouts byte-identical. Previously the tile read
    // this from the TKDEDU_EVENT_COUNT environment variable, so a child with a
    // different environment reserved a different footprint and every object
    // offset after tkdedu's shifted.
    c_abi.tkdedu.setEventCount(event_count);
    log.kvFmt("topo_build", "build", "tkdedu event_count={d}", .{event_count});
    // tkcase's capsule holds every event of the run, so its footprint is a
    // function of event_count too: same rule as tkdedu.
    c_abi.tkcase.setEventCount(event_count);

    // tkaudt, tknorm and tkpoly event_count for shutdown gating.
    // Unlike tkdedu (where event_count affects scratch footprint), these tiles
    // have fixed footprints. But we set event_count via the same C-param pattern
    // to avoid the env var anti-pattern: getenv() in privileged_init reads each
    // child's own environment, which can differ from the supervisor's.
    c_abi.tkgate.setEventCount(event_count);
    c_abi.tkings.setEventCount(event_count);
    c_abi.tkaudit.setEventCount(event_count);
    c_abi.tknorm.setEventCount(event_count);
    c_abi.tkpoly.setEventCount(event_count);
    c_abi.tkmodl.setEventCount(event_count);
    c_abi.tkagnt.setEventCount(event_count);
    c_abi.tkdisp.setEventCount(event_count);

    const align_check = c_abi.topob.topoAlignof();
    std.debug.print("[topo-build] alignof={d} <= {d} check={}\n", .{ align_check, topo_alloc_align.toByteUnits(), align_check <= topo_alloc_align.toByteUnits() });
    const size = c_abi.topob.topoSizeof();
    std.debug.print("[topo-build] size={d} ws={s}\n", .{ size, workspace_name });
    std.debug.print("[topo-build] before alignedAlloc\n", .{});
    std.debug.print("[topo-build] alloc ptr={x} page_align={d} size={d} bytes={d}MB\n", .{ @intFromPtr(&allocator), topo_alloc_align.toByteUnits(), size, size / 1024 / 1024 });
    const buf = allocator.alignedAlloc(u8, topo_alloc_align, size) catch |err| {
        std.debug.print("[topo-build] alignedAlloc FAILED: {any}\n", .{err});
        return error.AllocFailed;
    };
    std.debug.print("[topo-build] alignedAlloc ok\n", .{});
    errdefer allocator.free(buf);

    log.kvFmt("topo_build", "build", "allocated buf ptr={x} len={d}", .{ @intFromPtr(buf.ptr), buf.len });

    var app_name_buf: [64]u8 = undefined;
    std.debug.print("[topo-build] before topobNew\n", .{});
    log.kvFmt("topo_build", "build", "passing to topobNew ptr={x}", .{@intFromPtr(buf.ptr)});
    const topo = c_abi.topob.topobNew(buf.ptr, util.toZ(&app_name_buf, app_name)) orelse return error.TopobNewFailed;
    std.debug.print("[topo-build] topobNew ok\n", .{});

    var wksp_name_buf: [64]u8 = undefined;
    std.debug.print("[topo-build] before topobWksp(name={s})\n", .{workspace_name});
    const wksp_idx = c_abi.topob.topobWksp(topo, util.toZ(&wksp_name_buf, workspace_name));
    std.debug.print("[topo-build] topobWksp ok idx={d}\n", .{wksp_idx});
    var wksp_name_z_buf: [64]u8 = undefined;
    const wksp_name_z = util.toZ(&wksp_name_z_buf, workspace_name);

    // v2.22.S4 Task 0: Scan tiles to detect if metric tile is present BEFORE
    // creating workspaces, so we only create metric/metric_in when needed.
    var has_metric_tile = false;
    for (topo_desc.tiles) |t| {
        if (tile_ids.metric.eql(t.name)) {
            has_metric_tile = true;
            break;
        }
    }

    // v2.22.S4 Task 0: Create metric and metric_in workspaces only when
    // metric is present, so links and tiles route correctly for all topologies.
    if (has_metric_tile) log.kvFmt("topo_build", "build", "calling topobWksp(metric)", .{});
    const metric_wksp_idx: usize = if (has_metric_tile) c_abi.topob.topobWksp(topo, c_abi.wksp.wksp_name_metric) else c_abi.topob.not_found;
    if (has_metric_tile and topo_desc.channels.len > 0) log.kvFmt("topo_build", "build", "calling topobWksp(metric_in)", .{});
    const metric_in_wksp_idx: usize = if (has_metric_tile and topo_desc.channels.len > 0) c_abi.topob.topobWksp(topo, c_abi.wksp.wksp_name_metric_in) else c_abi.topob.not_found;
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
        if (!ch.hasProducerTile()) c_abi.topob.topobLinkPermitNoProducers(topo, link_ids[i]);
        // Verify link was registered with expected name (catches link name typos).
        log.kvFmt("topo_build", "build", "topoValidateLinkExists(name=ch{d})", .{i});
        std.debug.assert(c_abi.topob.topoValidateLinkExists(topo, linkNameZ(&link_name_buf, i)));
    }

    // Register tiles. All non-metric tiles go into the app workspace; the
    // metric tile goes into the dedicated "metric" workspace. Resolve the
    // descriptor-to-Firedancer index map after registration so later wiring
    // does not depend on the order in which tiles were registered.
    const tile_placements = try allocator.alloc(cpu_placement.CpuPlacement, topo_desc.tiles.len);
    defer allocator.free(tile_placements);
    const cpu_idx_arr = try allocator.alloc(usize, topo_desc.tiles.len);
    defer allocator.free(cpu_idx_arr);
    const fd_tile_idx_by_desc = try allocator.alloc(usize, topo_desc.tiles.len);
    defer allocator.free(fd_tile_idx_by_desc);
    for (topo_desc.tiles, 0..) |t, i| {
        tile_placements[i] = t.cpu_placement;
        if (tile_ids.metric.eql(t.name)) continue;

        var tile_name_buf: [16]u8 = undefined;
        log.kvFmt("topo_build", "build", "calling topobTile(id={s}, wksp={s})", .{ t.name.slice(), wksp_name_z });
        _ = c_abi.topob.topobTile(topo, util.toZ(&tile_name_buf, t.name.slice()), wksp_name_z, wksp_name_z, 0);
        // Verify tile was registered with expected name (catches tile name typos).
        log.kvFmt("topo_build", "build", "topoValidateTileExists(id={s})", .{t.name.slice()});
        std.debug.assert(c_abi.topob.topoValidateTileExists(topo, util.toZ(&tile_name_buf, t.name.slice())));
    }
    if (has_metric_tile) {
        var tile_name_buf: [16]u8 = undefined;
        log.kvFmt("topo_build", "build", "calling topobTile(metric, metric, metric)", .{});
        _ = c_abi.topob.topobTile(topo, util.toZ(&tile_name_buf, tile_ids.metric.slice()), c_abi.wksp.wksp_name_metric, c_abi.wksp.wksp_name_metric, 0);
        // Verify metric tile was registered.
        log.kvFmt("topo_build", "build", "topoValidateTileExists(metric)", .{});
        std.debug.assert(c_abi.topob.topoValidateTileExists(topo, util.toZ(&tile_name_buf, tile_ids.metric.slice())));
    }

    for (topo_desc.tiles, 0..) |t, desc_idx| {
        var tile_name_buf: [16]u8 = undefined;
        const fd_idx = c_abi.topob.topoFindTile(topo, util.toZ(&tile_name_buf, t.name.slice()), t.kind_id);
        if (fd_idx == c_abi.topob.not_found) return error.TileKindIdMismatch;
        if (c_abi.topob.topoTileKindId(topo, fd_idx) != t.kind_id) return error.TileKindIdMismatch;
        fd_tile_idx_by_desc[desc_idx] = fd_idx;
        cpu_idx_arr[fd_idx] = tileCpuIdx(desc_idx, t.cpu_placement);
        if (tile_ids.metric.eql(t.name)) metric_tile_idx = fd_idx;
    }

    if (metric_tile_idx != c_abi.topob.not_found) {
        log.kvFmt("topo_build", "build", "detected metric tile at idx={d}, metric_wksp={d}, metric_in_wksp={d}", .{ metric_tile_idx, metric_wksp_idx, metric_in_wksp_idx });
    } else {
        log.kvFmt("topo_build", "build", "no metric tile in topology", .{});
    }

    // v2.22.S4 Task 0: Wire each tile's output links into the metric tile
    // via the metric_in workspace BEFORE topobAutoLayout so that the
    // metric tile's in_cnt is set correctly by the layout engine.
    // Only wire observer inputs for channels where metric is NOT already
    // the explicit destination (line 354-390 handles the explicit dst).
    if (metric_tile_idx != c_abi.topob.not_found) {
        log.kvFmt("topo_build", "build", "wiring {d} candidate metric inputs", .{topo_desc.channels.len});
        for (topo_desc.channels, 0..) |ch, i| {
            // Channel endpoints use descriptor indices, while metric_tile_idx
            // is the Firedancer index after metric is moved to the end.
            // Map the destination before comparing indices from the same space.
            if (fd_tile_idx_by_desc[ch.dst_idx] == metric_tile_idx) continue;
            var tile_name_buf: [16]u8 = undefined;
            var link_name_buf: [8]u8 = undefined;
            const link_name_z = linkNameZ(&link_name_buf, i);
            // The metric tile observes pipeline links but must not apply
            // flow control to their producers.
            _ = c_abi.topob.topobTileIn(topo, util.toZ(&tile_name_buf, tile_ids.metric.slice()), 0, c_abi.wksp.wksp_name_metric_in, link_name_z, 0, false, true);
        }
        log.kvFmt("topo_build", "build", "done topobTileIn for metric tile", .{});
    }

    log.kvFmt("topo_build", "build", "calling topobAutoLayout(tile_cnt={d})", .{topo_desc.tiles.len});
    c_abi.topob.topobAutoLayout(topo, @as([*]const usize, cpu_idx_arr.ptr));
    log.kvFmt("topo_build", "build", "topobAutoLayout completed", .{});

    // Set per-tile scratch footprint and alignment properties so
    // tile_footprint() / tile_align() in topob.c can query them. Both come
    // from the tile's own fd_topo_run_tile_t, so the object fd_topob_finish
    // reserves is the one the tile's init actually carves up.
    // tknorm, tkdedu, tkaudt and metric report a real footprint; a tile with
    // no tile-local scratch reports 1UL and is skipped here, leaving it at
    // the 1UL default both callbacks fall back to.
    const scratch_footprint_key: [*:0]const u8 = "tickoni.scratch_footprint";
    const scratch_align_key: [*:0]const u8 = "tickoni.scratch_align";
    for (topo_desc.tiles) |t| {
        var tile_name_buf: [8]u8 = undefined;
        const reqs = c_abi.topob.tickoniTileScratchRequirements(util.toZ(&tile_name_buf, t.name.slice()));
        if (reqs.footprint > 1) {
            log.kvFmt("topo_build", "build", "calling topobSetTileObjPropertyUlong({s}, footprint={d}, align={d})", .{ t.name.slice(), reqs.footprint, reqs.alignment });
            c_abi.topob.topobSetTileObjPropertyUlong(topo, util.toZ(&tile_name_buf, t.name.slice()), t.kind_id, scratch_footprint_key, reqs.footprint);
            c_abi.topob.topobSetTileObjPropertyUlong(topo, util.toZ(&tile_name_buf, t.name.slice()), t.kind_id, scratch_align_key, reqs.alignment);
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
        std.debug.print("[topo-build] cnc_obj[{d}]={x} wksp_name={s}\\n", .{ fd_idx, cnc_obj, wksp_name_z });
        log.kvFmt("topo_build", "build", "calling topobTileUses(fd_idx={d}, cnc_obj={d})", .{ fd_idx, cnc_obj });
        c_abi.topob.topobTileUses(topo, fd_idx, cnc_obj, true);
        cnc_obj_id[fd_idx] = cnc_obj;
    }
    log.kvFmt("topo_build", "build", "done CNC loop (tile_cnt={d})", .{topo_desc.tiles.len});

    // The diagnostics tile observes the whole topology, as Firedancer's diag tile
    // does: it reads every other tile's metrics region (the tile's status and pid,
    // and where it writes the tile's OS-level metrics) and, to learn the replay
    // result, tkrepl's CNC. Declaring the use is what makes its process join the
    // workspaces holding them. These add no objects, so parent and child still
    // lay the topology out identically.
    {
        var diag_name_buf: [8]u8 = undefined;
        const diag_fd = c_abi.topob.topoFindTile(topo, util.toZ(&diag_name_buf, tile_ids.tkdiag.slice()), 0);
        if (diag_fd != c_abi.topob.not_found) {
            for (topo_desc.tiles, 0..) |t, desc_idx| {
                const fd_idx = fd_tile_idx_by_desc[desc_idx];
                if (fd_idx == diag_fd) continue;
                c_abi.topob.topobTileUses(topo, diag_fd, c_abi.topob.topoTileMetricsObjId(topo, fd_idx), true);
                if (tile_ids.tkrepl.eql(t.name)) c_abi.topob.topobTileUses(topo, diag_fd, cnc_obj_id[fd_idx], false);
            }
        }
    }

    // Committed-audit watermark: tkaudt stays a pure sink, so the barrier that
    // tells tkagnt an audit record is committed is one single-writer fseq,
    // not a return link. Created at a fixed position (after the CNCs, before
    // the channel wiring) so parent and child lay it out identically.
    var audit_watermark_obj_id: usize = c_abi.topob.not_found;
    {
        var audit_name_buf: [8]u8 = undefined;
        var agent_name_buf: [8]u8 = undefined;
        const audit_fd = c_abi.topob.topoFindTile(topo, util.toZ(&audit_name_buf, tile_ids.tkaudt.slice()), 0);
        const agent_fd = c_abi.topob.topoFindTile(topo, util.toZ(&agent_name_buf, tile_ids.tkagnt.slice()), 0);
        if (audit_fd != c_abi.topob.not_found and agent_fd != c_abi.topob.not_found) {
            audit_watermark_obj_id = c_abi.topob.topobObj(topo, "fseq", wksp_name_z);
            c_abi.topob.topobTileUses(topo, audit_fd, audit_watermark_obj_id, true);
            c_abi.topob.topobTileUses(topo, agent_fd, audit_watermark_obj_id, false);
            c_abi.topob.topobSetAuditWatermark(topo, audit_watermark_obj_id);
        }
    }

    const link_obj_id = try allocator.alloc(LinkObjIds, topo_desc.channels.len);
    errdefer allocator.free(link_obj_id);
    for (topo_desc.channels, 0..) |ch, i| {
        var src_name_buf: [8]u8 = undefined;
        var dst_name_buf: [8]u8 = undefined;
        var link_name_buf: [8]u8 = undefined;
        const dst_desc = topo_desc.tiles[ch.dst_idx];
        const dst_name_z = util.toZ(&dst_name_buf, dst_desc.name.slice());
        const link_name_z = linkNameZ(&link_name_buf, i);
        log.kvFmt("topo_build", "build", "calling topobTileIn(dst={s}#{d}, wksp={s}, link=ch{d})", .{ dst_name_z, dst_desc.kind_id, wksp_name_z, i });
        // A lossy channel is an unreliable consumer: its producer never waits on
        // it. Only telemetry links are lossy (link/types.zig, LinkReliability).
        const reliable = ch.reliability == .reliable;
        const fseq_obj_id = c_abi.topob.topobTileIn(topo, dst_name_z, dst_desc.kind_id, wksp_name_z, link_name_z, 0, reliable, true);
        // Verify channel wiring: src tile has out_cnt >= 1, dst tile has in_cnt >= 1.
        // Catches stale src_idx/dst_idx that reference deleted tiles. A link fed
        // from outside the tile graph has no src tile (permit_no_producers).
        log.kvFmt("topo_build", "build", "calling topoFindTile(dst={s})", .{dst_name_z});
        const dst_tile_id = c_abi.topob.topoFindTile(topo, dst_name_z, dst_desc.kind_id);
        std.debug.assert(dst_tile_id != c_abi.topob.not_found);
        log.kvFmt("topo_build", "build", "calling topoTileInputCount(tile={d})", .{dst_tile_id});
        const dst_in_cnt = c_abi.topob.topoTileInputCount(topo, dst_tile_id);
        std.debug.assert(dst_in_cnt > 0);
        var src_name_z: [*:0]const u8 = "external";
        if (ch.hasProducerTile()) {
            const src_desc = topo_desc.tiles[ch.src_idx];
            src_name_z = util.toZ(&src_name_buf, src_desc.name.slice());
            log.kvFmt("topo_build", "build", "calling topobTileOut(src={s}, link=ch{d})", .{ src_name_z, i });
            c_abi.topob.topobTileOut(topo, src_name_z, src_desc.kind_id, link_name_z, 0);
            log.kvFmt("topo_build", "build", "calling topoFindTile(src={s})", .{src_name_z});
            const src_tile_id = c_abi.topob.topoFindTile(topo, src_name_z, src_desc.kind_id);
            std.debug.assert(src_tile_id != c_abi.topob.not_found);
            log.kvFmt("topo_build", "build", "calling topoTileOutputCount(tile={d})", .{src_tile_id});
            const src_out_cnt = c_abi.topob.topoTileOutputCount(topo, src_tile_id);
            std.debug.assert(src_out_cnt > 0);
        }
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
                    .kind_id = @intCast(c_abi.topob.topoTileKindId(topo, firedancer_idx)),
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
        .audit_watermark_obj_id = audit_watermark_obj_id,
        .link_obj_id = link_obj_id,
        .tile_infos = tile_infos,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const tile_mod = @import("tile.zig");
const link_mod = @import("link.zig");

fn testTile(idx: usize, id: []const u8) tile_mod.TileDescriptor {
    return .{ .id = idx, .name = tile_ids.lookup(id) orelse unreachable };
}

test "build produces a topology for the linear Phase 0 chain" {
    const tiles = [_]tile_mod.TileDescriptor{
        testTile(0, tile_ids.tkings.slice()),
        testTile(1, tile_ids.tknorm.slice()),
        testTile(2, tile_ids.tkdedu.slice()),
        testTile(3, tile_ids.tkpoly.slice()),
        testTile(4, tile_ids.tkaudt.slice()),
    };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 0, 0);
    defer built.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), built.cnc_obj_id.len);

    var tkaudt_buf: [8]u8 = undefined;
    const tkaudt_id = c_abi.topob.topoFindTile(built.topo, util.toZ(&tkaudt_buf, tile_ids.tkaudt.slice()), 0);
    try std.testing.expect(tkaudt_id != c_abi.topob.not_found);
}

test "concreteWorkspaceName matches Firedancer join naming" {
    var buf: [concrete_workspace_name_cap]u8 = undefined;
    const name = try concreteWorkspaceName(&buf, "tkpay0");
    try std.testing.expectEqualStrings("tickoni_tkpay0.wksp", name);
}

test "build with metric tile populates metric_wksp_idx and metric_tile_idx" {
    const tiles = [_]tile_mod.TileDescriptor{
        testTile(0, tile_ids.tkings.slice()),
        testTile(1, tile_ids.tknorm.slice()),
        testTile(2, tile_ids.tkdedu.slice()),
        testTile(3, tile_ids.tkpoly.slice()),
        testTile(4, tile_ids.tkaudt.slice()),
        testTile(5, tile_ids.metric.slice()),
    };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
        .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    // Metric workspace indices must be valid (not not_found).
    try std.testing.expect(built.metric_wksp_idx != c_abi.topob.not_found);
    try std.testing.expect(built.metric_in_wksp_idx != c_abi.topob.not_found);

    // Metric tile must be found and indexed in tile_infos.
    try std.testing.expect(built.metric_tile_idx != c_abi.topob.not_found);
    try std.testing.expect(built.metric_tile_obj_id != 0);

    // The metric tile must be resolvable by TileId.
    const metric_id = tile_ids.metric;
    const found_idx = built.tileIdxById(metric_id);
    try std.testing.expectEqual(built.metric_tile_idx, found_idx);
}

test "build accepts a metric-only topology without channel arithmetic" {
    const tiles = [_]tile_mod.TileDescriptor{testTile(0, tile_ids.metric.slice())};
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &.{} };
    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);
    try std.testing.expect(built.metric_tile_idx != c_abi.topob.not_found);
    try std.testing.expectEqual(@as(usize, 1), built.tile_infos.len);
    try std.testing.expectEqual(c_abi.topob.not_found, built.metric_in_wksp_idx);
}

// ---------------------------------------------------------------------------
// Multi-instance (name, kind_id) identity — tkagnt fan-out graph
// ---------------------------------------------------------------------------

const topology_spec = @import("topology_spec.zig");

const max_model_cnt = 11;

/// tkings, tkagnt, tkaudt, then `n` tkmodl instances (kind 0..n-1). The
/// metric tile goes last, or at descriptor index 3 when `metric_before_models`
/// so Firedancer's index order (metric moved to the end) differs from the
/// descriptor order that channel endpoints use.
///
/// Channels: tkings->tkagnt, then per model k: tkagnt->k (request), k->tkaudt
/// (audit), k->tkagnt (result), i.e. 1+3n channels.
fn modelGraph(
    n: usize,
    metric_before_models: bool,
    tiles: *[max_model_cnt + 4]tile_mod.TileDescriptor,
    channels: *[1 + 3 * max_model_cnt]link_mod.Channel,
) !topology.Topology {
    std.debug.assert(n >= 1 and n <= max_model_cnt);
    const wksp = try link_mod.WorkspaceName.parse("tkpay0");
    var t: usize = 0;
    tiles[t] = .{ .id = t, .name = tile_ids.tkings };
    t += 1;
    tiles[t] = .{ .id = t, .name = tile_ids.tkagnt };
    t += 1;
    tiles[t] = .{ .id = t, .name = tile_ids.tkaudt };
    t += 1;
    if (metric_before_models) {
        tiles[t] = .{ .id = t, .name = tile_ids.metric };
        t += 1;
    }
    const model_base = t;
    for (0..n) |k| {
        tiles[t] = .{ .id = t, .name = tile_ids.tkmodl, .kind_id = @intCast(k) };
        t += 1;
    }
    if (!metric_before_models) {
        tiles[t] = .{ .id = t, .name = tile_ids.metric };
        t += 1;
    }
    channels[0] = .{ .src_idx = 0, .dst_idx = 1, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
    for (0..n) |k| {
        const m: u32 = @intCast(model_base + k);
        channels[1 + 3 * k + 0] = .{ .src_idx = 1, .dst_idx = m, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
        channels[1 + 3 * k + 1] = .{ .src_idx = m, .dst_idx = 2, .depth = 32, .mtu = 256, .backing = .tango_shm, .workspace_name = wksp };
        channels[1 + 3 * k + 2] = .{ .src_idx = m, .dst_idx = 1, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
    }
    return .{ .tiles = tiles[0..t], .channels = channels[0 .. 1 + 3 * n] };
}

fn findInstance(built: *const BuiltTopo, k: usize) usize {
    var name_buf: [8]u8 = undefined;
    return c_abi.topob.topoFindTile(built.topo, util.toZ(&name_buf, tile_ids.tkmodl.slice()), k);
}

fn expectEveryModelWiredOnce(built: *const BuiltTopo, n: usize) !void {
    var seen: [max_model_cnt]usize = undefined;
    for (0..n) |k| {
        const fd_idx = findInstance(built, k);
        try std.testing.expect(fd_idx != c_abi.topob.not_found);
        try std.testing.expectEqual(k, c_abi.topob.topoTileKindId(built.topo, fd_idx));
        // One request in; one audit link and one result link out. Wiring every
        // endpoint to kind 0 would pile all links on instance 0 instead.
        try std.testing.expectEqual(@as(usize, 1), c_abi.topob.topoTileInputCount(built.topo, fd_idx));
        try std.testing.expectEqual(@as(usize, 2), c_abi.topob.topoTileOutputCount(built.topo, fd_idx));
        for (seen[0..k]) |previous| try std.testing.expect(previous != fd_idx);
        seen[k] = fd_idx;

        const info = built.tile_infos[fd_idx];
        try std.testing.expect(info.tile_id.eql(tile_ids.tkmodl));
        try std.testing.expectEqual(@as(u8, @intCast(k)), info.kind_id);
        try std.testing.expectEqual(fd_idx, built.tileIdxByIdentity(.{ .name = tile_ids.tkmodl, .kind_id = @intCast(k) }));
    }
    var agent_buf: [8]u8 = undefined;
    const agent = c_abi.topob.topoFindTile(built.topo, util.toZ(&agent_buf, tile_ids.tkagnt.slice()), 0);
    try std.testing.expectEqual(1 + n, c_abi.topob.topoTileInputCount(built.topo, agent));
    try std.testing.expectEqual(n, c_abi.topob.topoTileOutputCount(built.topo, agent));
    var audit_buf: [8]u8 = undefined;
    const audit = c_abi.topob.topoFindTile(built.topo, util.toZ(&audit_buf, tile_ids.tkaudt.slice()), 0);
    try std.testing.expectEqual(n, c_abi.topob.topoTileInputCount(built.topo, audit));
}

test "build wires each tkmodl instance by its own (name, kind_id)" {
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const topo_desc = try modelGraph(3, false, &tiles, &channels);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    try expectEveryModelWiredOnce(&built, 3);
}

test "build keeps nonzero tkmodl identities when metric precedes the models" {
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const topo_desc = try modelGraph(3, true, &tiles, &channels);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    try expectEveryModelWiredOnce(&built, 3);
    // Metric moved to the end of Firedancer's order: descriptor 3 is not
    // Firedancer tile 3 any more, which is the case that breaks positional
    // lookups.
    try std.testing.expectEqual(built.tile_infos.len - 1, built.metric_tile_idx);
}

test "build accepts the 11-model maximum graph within the metric input ceiling" {
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const topo_desc = try modelGraph(max_model_cnt, false, &tiles, &channels);
    try std.testing.expectEqual(@as(usize, 15), topo_desc.tiles.len);
    try std.testing.expectEqual(@as(usize, 34), topo_desc.channels.len);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    try expectEveryModelWiredOnce(&built, max_model_cnt);
    // The metric observer takes one input per channel it is not already the
    // destination of: all 34, well under Firedancer's 128-input ceiling.
    const metric_in = c_abi.topob.topoTileInputCount(built.topo, built.metric_tile_idx);
    try std.testing.expectEqual(@as(usize, 34), metric_in);
    try std.testing.expect(metric_in <= 128);
}

test "build gives a sparse tkmodl selection the same layout in parent and child" {
    // Parent builds from the supervisor's Topology; each child rebuilds from
    // the TopologySpec round-trip. Every object offset must agree or the
    // child maps a different tile's scratch.
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const parent_desc = try modelGraph(2, true, &tiles, &channels);
    var parent = try build(std.testing.allocator, parent_desc, "tkpay0", 9091, 4);
    defer parent.deinit(std.testing.allocator);

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    const spec = try topology_spec.TopologySpec.fromTopology(parent_desc, 9091, 4);
    try spec.writeToFile(std.testing.io, tmp.dir, "topology.spec");
    const read_back = try topology_spec.TopologySpec.readFromFile(std.testing.io, tmp.dir, "topology.spec");
    var child_tiles: [topology_spec.max_tiles]tile_mod.TileDescriptor = undefined;
    var child_channels: [topology_spec.max_channels]link_mod.Channel = undefined;
    const child_desc = read_back.toTopology(&child_tiles, &child_channels);
    var child = try build(std.testing.allocator, child_desc, "tkpay0", read_back.metric_port, read_back.event_count);
    defer child.deinit(std.testing.allocator);

    try std.testing.expectEqual(parent.tile_infos.len, child.tile_infos.len);
    for (parent.tile_infos, child.tile_infos, 0..) |p, c, i| {
        try std.testing.expect(p.tile_id.eql(c.tile_id));
        try std.testing.expectEqual(p.kind_id, c.kind_id);
        try std.testing.expectEqual(
            c_abi.topob.topoObjOffset(parent.topo, parent.cnc_obj_id[i]),
            c_abi.topob.topoObjOffset(child.topo, child.cnc_obj_id[i]),
        );
    }
    for (parent.link_obj_id, child.link_obj_id) |p, c| {
        try std.testing.expectEqual(
            c_abi.topob.topoObjOffset(parent.topo, p.mcache_obj_id),
            c_abi.topob.topoObjOffset(child.topo, c.mcache_obj_id),
        );
        try std.testing.expectEqual(
            c_abi.topob.topoObjOffset(parent.topo, p.dcache_obj_id),
            c_abi.topob.topoObjOffset(child.topo, c.dcache_obj_id),
        );
    }
}

test "build rejects kind ids that disagree with Firedancer registration order" {
    const tiles = [_]tile_mod.TileDescriptor{
        .{ .id = 0, .name = tile_ids.tkmodl, .kind_id = 1 },
        .{ .id = 1, .name = tile_ids.tkmodl, .kind_id = 0 },
    };
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &.{} };
    try std.testing.expectError(error.TileKindIdMismatch, build(std.testing.allocator, topo_desc, "tkpay0", 0, 0));
}

test "build creates one audit watermark shared by tkaudt (writer) and tkagnt (reader)" {
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const topo_desc = try modelGraph(2, false, &tiles, &channels);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    const obj = c_abi.topob.topoAuditWatermarkObj(built.topo);
    try std.testing.expect(obj != c_abi.topob.not_found);
    try std.testing.expectEqual(obj, built.audit_watermark_obj_id);
    // The object lives in the app workspace beside the links and CNCs.
    try std.testing.expectEqual(built.wksp_idx, c_abi.topob.topoObjWkspId(built.topo, obj));
}

test "build creates no audit watermark without a tkagnt" {
    const tiles = [_]tile_mod.TileDescriptor{
        testTile(0, tile_ids.tkings.slice()),
        testTile(1, tile_ids.tkaudt.slice()),
    };
    const channels = [_]link_mod.Channel{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 }};
    const topo_desc = topology.Topology{ .tiles = &tiles, .channels = &channels };

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 0, 0);
    defer built.deinit(std.testing.allocator);

    try std.testing.expectEqual(c_abi.topob.not_found, c_abi.topob.topoAuditWatermarkObj(built.topo));
    try std.testing.expectEqual(c_abi.topob.not_found, built.audit_watermark_obj_id);
}

test "build gives parent and child the same audit watermark layout" {
    var tiles: [max_model_cnt + 4]tile_mod.TileDescriptor = undefined;
    var channels: [1 + 3 * max_model_cnt]link_mod.Channel = undefined;
    const topo_desc = try modelGraph(3, true, &tiles, &channels);
    var parent = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 4);
    defer parent.deinit(std.testing.allocator);
    var child = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 4);
    defer child.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        c_abi.topob.topoObjOffset(parent.topo, parent.audit_watermark_obj_id),
        c_abi.topob.topoObjOffset(child.topo, child.audit_watermark_obj_id),
    );
}

// ---------------------------------------------------------------------------
// Link reliability — the diagnostic fan-in links are unreliable consumers
// (plans/v2.10-s14-tkdiag-fan-in.md, "Resolved Design" 1)
// ---------------------------------------------------------------------------

/// tkings(0) tknorm(1) tkdedu(2) tkpoly(3) tkaudt(4) metric(5) tkdiag(6): the
/// four reliable pipeline links, then one lossy diagnostic link from each
/// pipeline tile into tkdiag. Diagnostic links are appended after the pipeline
/// links, so each producer's diagnostic output is its last output.
fn fanInTopology(tiles: *[7]tile_mod.TileDescriptor, channels: *[9]link_mod.Channel) !topology.Topology {
    const wksp = try link_mod.WorkspaceName.parse("tkpay0");
    const names = [_]tile.TileId{ tile_ids.tkings, tile_ids.tknorm, tile_ids.tkdedu, tile_ids.tkpoly, tile_ids.tkaudt, tile_ids.metric, tile_ids.tkdiag };
    for (names, 0..) |name, i| tiles[i] = .{ .id = i, .name = name };
    for (0..4) |i| {
        channels[i] = .{ .src_idx = @intCast(i), .dst_idx = @intCast(i + 1), .depth = 64, .mtu = 128, .backing = .tango_shm, .reliability = .reliable, .workspace_name = wksp };
    }
    for (0..5) |i| {
        channels[4 + i] = .{ .src_idx = @intCast(i), .dst_idx = 6, .depth = 64, .mtu = 128, .backing = .tango_shm, .reliability = .lossy, .workspace_name = wksp };
    }
    return .{ .tiles = tiles, .channels = channels };
}

fn tileByName(built: *const BuiltTopo, id: tile.TileId) usize {
    var buf: [8]u8 = undefined;
    return c_abi.topob.topoFindTile(built.topo, util.toZ(&buf, id.slice()), 0);
}

test "build wires a lossy channel as an unreliable consumer and a reliable channel as a reliable one" {
    var tiles: [7]tile_mod.TileDescriptor = undefined;
    var channels: [9]link_mod.Channel = undefined;
    const topo_desc = try fanInTopology(&tiles, &channels);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    // tkdiag: five inputs, every one unreliable, none of them an output of its own.
    const diag = tileByName(&built, tile_ids.tkdiag);
    try std.testing.expect(diag != c_abi.topob.not_found);
    try std.testing.expectEqual(@as(usize, 5), c_abi.topob.topoTileInputCount(built.topo, diag));
    try std.testing.expectEqual(@as(usize, 0), c_abi.topob.topoTileOutputCount(built.topo, diag));
    for (0..5) |i| try std.testing.expect(!c_abi.topob.topoTileInReliable(built.topo, diag, i));

    // The pipeline stays reliable: tknorm's one input comes from tkings.
    const norm = tileByName(&built, tile_ids.tknorm);
    try std.testing.expectEqual(@as(usize, 1), c_abi.topob.topoTileInputCount(built.topo, norm));
    try std.testing.expect(c_abi.topob.topoTileInReliable(built.topo, norm, 0));
    const audit = tileByName(&built, tile_ids.tkaudt);
    try std.testing.expect(c_abi.topob.topoTileInReliable(built.topo, audit, 0));
}

test "build gives each diagnostic producer its diagnostic link as its last output" {
    var tiles: [7]tile_mod.TileDescriptor = undefined;
    var channels: [9]link_mod.Channel = undefined;
    const topo_desc = try fanInTopology(&tiles, &channels);

    var built = try build(std.testing.allocator, topo_desc, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    // Pipeline output plus the diagnostic output, except the sink.
    const expected_out = [_]struct { id: tile.TileId, out: usize }{
        .{ .id = tile_ids.tkings, .out = 2 },
        .{ .id = tile_ids.tknorm, .out = 2 },
        .{ .id = tile_ids.tkdedu, .out = 2 },
        .{ .id = tile_ids.tkpoly, .out = 2 },
        .{ .id = tile_ids.tkaudt, .out = 1 },
    };
    for (expected_out) |e| {
        const idx = tileByName(&built, e.id);
        try std.testing.expectEqual(e.out, c_abi.topob.topoTileOutputCount(built.topo, idx));
    }
    // The metric tile still observes every link, the diagnostic ones included.
    try std.testing.expectEqual(@as(usize, 9), c_abi.topob.topoTileInputCount(built.topo, built.metric_tile_idx));
}

// ---------------------------------------------------------------------------
// tkdiag observes every tile, as Firedancer's diag tile does
// ---------------------------------------------------------------------------

test "build lets tkdiag reach every other tile's metrics region and tkrepl's CNC" {
    const wksp = try link_mod.WorkspaceName.parse("tkpay0");
    const names = [_]tile.TileId{ tile_ids.tkings, tile_ids.tknorm, tile_ids.tkaudt, tile_ids.tkrepl, tile_ids.metric, tile_ids.tkdiag };
    var tiles: [names.len]tile_mod.TileDescriptor = undefined;
    for (names, 0..) |name, i| tiles[i] = .{ .id = i, .name = name };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = wksp },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = wksp },
    };
    var built = try build(std.testing.allocator, .{ .tiles = &tiles, .channels = &channels }, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);

    const diag = tileByName(&built, tile_ids.tkdiag);
    try std.testing.expect(diag != c_abi.topob.not_found);
    for ([_]tile.TileId{ tile_ids.tkings, tile_ids.tknorm, tile_ids.tkaudt, tile_ids.tkrepl, tile_ids.metric }) |other| {
        const idx = tileByName(&built, other);
        try std.testing.expect(idx != c_abi.topob.not_found);
        const metrics_obj = c_abi.topob.topoTileMetricsObjId(built.topo, idx);
        try std.testing.expect(c_abi.topob.topoTileUsesObj(built.topo, diag, metrics_obj));
    }
    // tkdiag also reads tkrepl's CNC for the replay result.
    const repl = tileByName(&built, tile_ids.tkrepl);
    try std.testing.expect(c_abi.topob.topoTileUsesObj(built.topo, diag, built.cnc_obj_id[repl]));
    // And only tkrepl's: a CNC is a tile's own control surface.
    const norm = tileByName(&built, tile_ids.tknorm);
    try std.testing.expect(!c_abi.topob.topoTileUsesObj(built.topo, diag, built.cnc_obj_id[norm]));
}

test "build without tkdiag adds no cross-tile access" {
    const wksp = try link_mod.WorkspaceName.parse("tkpay0");
    const names = [_]tile.TileId{ tile_ids.tkings, tile_ids.tkaudt, tile_ids.metric };
    var tiles: [names.len]tile_mod.TileDescriptor = undefined;
    for (names, 0..) |name, i| tiles[i] = .{ .id = i, .name = name };
    const channels = [_]link_mod.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = wksp },
    };
    var built = try build(std.testing.allocator, .{ .tiles = &tiles, .channels = &channels }, "tkpay0", 9091, 0);
    defer built.deinit(std.testing.allocator);
    const ings = tileByName(&built, tile_ids.tkings);
    const audt = tileByName(&built, tile_ids.tkaudt);
    try std.testing.expect(!c_abi.topob.topoTileUsesObj(built.topo, ings, c_abi.topob.topoTileMetricsObjId(built.topo, audt)));
}
