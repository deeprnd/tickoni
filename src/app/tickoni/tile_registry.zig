/// v2.14.S8.T1: single source of truth for tile id -> behavior. Before this
/// file, tile identity was independently mapped in four places: supervisor's
/// process-mode spawn (position-indexed), supervisor's snapshotProcessMetrics
/// (string-matched), tile_main's process dispatch (string-matched if/else),
/// and process.zig's counter indices (positionally assumed, unowned).
///
/// This registry follows Firedancer's TILES[] + one-dispatcher pattern: one
/// array of TileEntry, looked up by TileId, that owns a tile's launch mode,
/// process-mode run callback, and counter schema. Every
/// consumer of tile identity reads from here instead of recreating the
/// mapping.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");
const tile_ids = rt.tile_ids;

/// Process-mode run callback: joins this tile's links from the launch spec
/// and runs its pipeline stage. Not every tile has a process-mode role yet
/// (see TileEntry.process_fn).
pub const ProcessFn = *const fn (
    io: std.Io,
    wksp: *c_abi.wksp.Wksp,
    spec: *const rt.launch_spec.LaunchSpec,
    cnc: *c_abi.cnc.Cnc,
    allocator: std.mem.Allocator,
) anyerror!void;

/// Named meaning of a cnc app-region counter index, so supervisor.zig's
/// snapshotProcessMetrics can read counters without knowing per-tile which
/// index means what. See tiles/payment_pipeline/process.zig's
/// rt.cnc_counters.appCounterWrite call sites for where each index is
/// written. Observer tiles (tkrepl, metric, tkdiag) use additional fields
/// for process-mode visibility.
pub const CounterField = enum {
    produced,
    normalized,
    invalid,
    duplicates,
    allowed,
    denied,
    audited,
    // Observer tile counters (process-mode)
    replay_checked,
    replay_match,
    metric_snapshots,
    metric_backpressure_waits,
    diag_crashed_tile,
    diag_sandbox_failures,
    // Index 2 on the metric tile's CNC app-region holds boot_ts
    // written by tk_metric_run after CNC join. Supervisor reads it via
    // metric_boot_timestamp to verify unprivileged_init ran.
    metric_boot_timestamp,
};

pub const CounterSchemaEntry = struct { idx: u8, field: CounterField };

pub const LaunchMode = enum { tile, stem };

pub const TileEntry = struct {
    id: rt.tile.TileId,
    launch_mode: LaunchMode = .tile,
    /// Null for tiles with no process-mode pipeline role yet (tkrepl,
    /// metric, tkdiag) — see tiles/payment_pipeline/process.zig's module
    /// doc comment for that scope boundary.
    process_fn: ?ProcessFn = null,
    counters: []const CounterSchemaEntry = &.{},
    /// Expected link cardinality (v2.14.S8 registry responsibility).
    /// v2.14.S8.T2 wires these into real validation: validate(topo) below
    /// fails closed if a topology's actual per-tile channel count for this
    /// id doesn't match.
    in_cnt: u8 = 0,
    out_cnt: u8 = 0,
};

fn id(comptime s: []const u8) rt.tile.TileId {
    return tile_ids.lookup(s) orelse unreachable;
}

/// Reads the payment-pipeline test config the supervisor wrote once for
/// the whole run (see supervisor.zig's startPaymentPipelineProcess), from
/// the path convention "<shmem_path>/payment_pipeline.config" — sibling to
/// this tile's own LaunchSpec file, derived from spec.shmemPath() rather
/// than carried as a LaunchSpec field (v2.14.S8.T2 keeps that record
/// payment-pipeline-agnostic).
fn loadProcessConfig(io: std.Io, spec: *const rt.launch_spec.LaunchSpec) !tiles.process.ProcessRuntimeConfig {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()});
    const file = try rt.file_io.openFile(io, std.Io.Dir.cwd(), path);
    defer file.close(io);
    var file_struct: tiles.process.ProcessConfigFile = undefined;
    const buf = std.mem.asBytes(&file_struct);
    const n = try file.readPositionalAll(io, buf, 0);
    if (n != @sizeOf(tiles.process.ProcessConfigFile)) return error.ProcessConfigTruncated;
    if (file_struct.magic_field != tiles.process.process_config_magic) return error.ProcessConfigBadMagic;
    if (file_struct.version_field != tiles.process.process_config_version) return error.ProcessConfigUnsupportedVersion;
    const stuck_str = if (file_struct.cfg.stuck_tile) |h| blk: {
        var id_buf: [32]u8 = undefined;
        break :blk std.fmt.bufPrint(&id_buf, "{d}", .{h.tile_idx}) catch "unknown";
    } else "null";
    std.log.warn(
        "tile {d}: loaded process config, stuck_tile={s}, event_count={d}",
        .{
            spec.tile_idx,
            stuck_str,
            file_struct.cfg.pipeline.event_count,
        },
    );
    return file_struct.cfg;
}

// ---------------------------------------------------------------------------
// Process-mode dispatch wrappers.
//
// Each wrapper owns the link-joining shape for its tile (which of
// input/output it expects) and calls into the pure pipeline-stage logic in
// tiles.process. Moved here from tile_main.zig's if/else dispatch so this
// file is the actual single source of truth, not just a lookup table
// pointing back at scattered per-tile logic.
// ---------------------------------------------------------------------------

fn tkingsProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    _ = allocator;
    std.debug.print("[tkings] joining output link...\n", .{});
    if (spec.out_cnt != 1) return error.MissingOutputLink;
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    if (cfg.pipeline.model_requests != null) {
        // Test-build model-request stream for the tkmodl topologies.
        std.debug.print("[tkings] producing model requests (event_count={d})...\n", .{cfg.pipeline.event_count});
        try tiles.process.runModelRequestSourceProcess(cfg, spec.tile_idx, &output, cnc);
        std.debug.print("[tkings] done producing\n", .{});
        return;
    }
    std.debug.print("[tkings] producing events (event_count={d})...\n", .{cfg.pipeline.event_count});
    tiles.process.runIngestProcess(cfg, spec.tile_idx, &output, cnc);
    std.debug.print("[tkings] done producing\n", .{});
}

// ---------------------------------------------------------------------------
// Registry.
// ---------------------------------------------------------------------------

/// Supported Phase 0 tiles. A configured topology may contain a subset in
/// any order; launch and validation look up entries by tile identity.
pub const entries = [_]TileEntry{
    .{
        .id = tile_ids.tkings,
        .process_fn = tkingsProcess,
        .counters = &.{.{ .idx = 0, .field = .produced }},
        .out_cnt = 1,
    },
    // tknorm migrated to fd_stem tile — lifecycle owned by
    // TK_NORM_RUN's privileged_init / stem_run, not the process-mode
    // callback path below.
    .{
        .id = tile_ids.tknorm,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{ .{ .idx = 0, .field = .normalized }, .{ .idx = 1, .field = .invalid } },
        .in_cnt = 1,
        .out_cnt = 1,
    },
    // tkdedu migrated to fd_stem tile — lifecycle owned by
    // TK_DEDU_RUN's privileged_init / stem_run, not the process-mode
    // callback path below.
    .{
        .id = tile_ids.tkdedu,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{.{ .idx = 0, .field = .duplicates }},
        .in_cnt = 1,
        .out_cnt = 1,
    },
    .{
        .id = tile_ids.tkpoly,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{ .{ .idx = 0, .field = .allowed }, .{ .idx = 1, .field = .denied } },
        .in_cnt = 1,
        .out_cnt = 1,
    },
    // tkaudt migrated to fd_stem tile (Phase 4.1) — lifecycle owned by
    // TK_AUDIT_RUN's privileged_init / stem_run, not the process-mode
    // callback path below.
    .{
        .id = tile_ids.tkaudt,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{.{ .idx = 0, .field = .audited }},
        .in_cnt = 1,
    },
    .{
        .id = tile_ids.tkrepl,
        .counters = &.{ .{ .idx = 0, .field = .replay_checked }, .{ .idx = 1, .field = .replay_match } },
    },
    .{
        .id = tile_ids.metric,
        .counters = &.{
            .{ .idx = 0, .field = .metric_snapshots },
            .{ .idx = 1, .field = .metric_backpressure_waits },
            .{ .idx = 2, .field = .metric_boot_timestamp },
        },
        .in_cnt = 0,
        .out_cnt = 0,
    },
    .{
        .id = tile_ids.tkdiag,
        .counters = &.{ .{ .idx = 0, .field = .diag_crashed_tile }, .{ .idx = 1, .field = .diag_sandbox_failures } },
    },
    // tkmodl: fd_stem tile, fixture/replay only (no provider I/O). One request
    // link in; an audit link (tkaudt) and a result link (tkagnt) out.
    // Slots 0/1 are allowed (served from a captured result) and denied.
    .{
        .id = tile_ids.tkmodl,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{ .{ .idx = 0, .field = .allowed }, .{ .idx = 1, .field = .denied } },
        .in_cnt = 1,
        .out_cnt = 2,
    },
    // tkagnt: bounded result-sink fd_stem observer for the tkmodl result link.
    // Not an agent; its committed results are read from scratch, so it
    // publishes no CNC counter slot.
    .{
        .id = tile_ids.tkagnt,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{},
        .in_cnt = 1,
    },
};

pub fn findById(tile_id: rt.tile.TileId) ?*const TileEntry {
    for (&entries) |*e| {
        if (e.id.eql(tile_id)) return e;
    }
    return null;
}

/// Validates each configured tile against its registry entry and link shape.
/// The registry can contain tiles absent from a particular topology.
pub fn validate(topo: rt.topology.Topology) !void {
    for (topo.tiles, 0..) |t, i| {
        _ = findById(t.name) orelse return error.UnregisteredTopologyTile;
        for (topo.tiles[0..i]) |previous| {
            if (previous.name.eql(t.name)) return error.DuplicateTopologyTile;
        }
    }
    for (topo.tiles, 0..) |t, i| {
        const entry = findById(t.name).?;
        var in_cnt: u8 = 0;
        var out_cnt: u8 = 0;
        for (topo.channels) |ch| {
            if (ch.dst_idx == i) in_cnt += 1;
            if (ch.src_idx == i) out_cnt += 1;
        }
        if (in_cnt != entry.in_cnt or out_cnt != entry.out_cnt) return error.LinkCardinalityMismatch;
    }
}

test {
    _ = @import("tile_registry_test.zig");
}
