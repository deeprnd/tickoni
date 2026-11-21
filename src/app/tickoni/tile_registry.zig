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
    // tkdiag fan-in counters (tk_diag_stem.c)
    diag_tiles_reporting,
    diag_fragments_accepted,
    diag_fragments_rejected,
    // tkagnt agent-worker counters
    agent_dispatched,
    agent_results,
    agent_denied,
    agent_tokens,
    agent_embeddings,
    // Index 2 on the metric tile's CNC app-region holds boot_ts
    // written by tk_metric_run after CNC join. Supervisor reads it via
    // metric_boot_timestamp to verify unprivileged_init ran.
    metric_boot_timestamp,
};

pub const CounterSchemaEntry = struct { idx: u8, field: CounterField };

pub const LaunchMode = enum { tile, stem };

/// A tile's part in the diagnostic fan-in (plans/v2.10-s14-tkdiag-fan-in.md).
/// A `producer` may have one extra, optional output link to tkdiag, which is
/// not part of its pipeline link count (`in_cnt`/`out_cnt`); the `collector`
/// (tkdiag) takes one such link from each producer and has no pipeline link.
pub const DiagRole = enum { none, producer, collector };

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
    /// Number of processes of this tile type a topology may configure, each
    /// with a distinct compact `kind_id` (Topology.validateIdentities). Only
    /// tkmodl is multi-instance; its per-instance link shape (in_cnt/out_cnt)
    /// is checked for each descriptor separately.
    max_instances: u8 = 1,
    /// How the expected link counts follow from the configured tkmodl
    /// instances. `.fixed` uses in_cnt/out_cnt as written.
    cardinality: Cardinality = .fixed,
    /// Role in the diagnostic fan-in. Links to and from tkdiag are validated
    /// separately from `in_cnt`/`out_cnt`; see `validate`.
    diag: DiagRole = .none,
};

/// Link-count rule for a tile whose links depend on how many tkmodl instances a
/// topology configures (N).
pub const Cardinality = enum {
    /// in_cnt / out_cnt as written.
    fixed,
    /// tkaudt: one model-audit link per tkmodl plus one agent-audit link per
    /// tkagnt, one idle link per tktool and tkadpt, and the payment chain's link
    /// from each tkpoly; with no tkmodl, `in_cnt` (the payment-pipeline chain end).
    audit_fan_in,
    /// tkagnt: one request input plus one result input per tkmodl; one request
    /// output per tkmodl plus the audit and terminal-result outputs, and one idle
    /// output to each tktool.
    agent_fan,
    /// tkdisp: a terminal-result sink (one input) when the topology has no
    /// tkcase; a scheduler (an event input from tkcase and tkagnt's results in,
    /// the agent request link out) when it has one.
    disp_shape,
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
    // One pipeline output, plus the optional diagnostic link to tkdiag. validate()
    // guarantees that a second output is that link and comes last.
    if (spec.out_cnt < 1 or spec.out_cnt > 2) return error.MissingOutputLink;
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    var diag_link: ?rt.link.Producer = null;
    defer if (diag_link) |*d| d.leave();
    var diag_sender: ?tiles.process.DiagSender = null;
    if (spec.out_cnt == 2) {
        diag_link = try rt.link.Producer.join(wksp, spec.outLinks()[1]);
        diag_sender = try tiles.process.DiagSender.init(&diag_link.?, spec.tile_idx);
    }
    const cfg = try loadProcessConfig(io, spec);
    if (cfg.pipeline.model_requests != null) {
        // Test-build model-request stream for the tkmodl topologies.
        std.debug.print("[tkings] producing model requests (event_count={d})...\n", .{cfg.pipeline.event_count});
        try tiles.process.runModelRequestSourceProcess(cfg, spec.tile_idx, &output, cnc);
        std.debug.print("[tkings] done producing\n", .{});
        return;
    }
    std.debug.print("[tkings] producing events (event_count={d})...\n", .{cfg.pipeline.event_count});
    tiles.process.runIngestProcess(cfg, spec.tile_idx, &output, if (diag_sender) |*d| d else null, cnc);
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
        .diag = .producer,
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
        .diag = .producer,
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
        .diag = .producer,
    },
    .{
        .id = tile_ids.tkpoly,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{ .{ .idx = 0, .field = .allowed }, .{ .idx = 1, .field = .denied } },
        .in_cnt = 1,
        .out_cnt = 1,
        .diag = .producer,
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
        .cardinality = .audit_fan_in,
        .diag = .producer,
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
    // tkdiag migrated to fd_stem tile — lifecycle owned by
    // TK_DIAG_RUN's privileged_init / stem_run, not the process-mode
    // callback path. The diagnostic collector: no pipeline link and no output;
    // its inputs are the unreliable diagnostic links of the diagnostic
    // producers (DiagRole), when the topology wires them. tk_diag_stem.c is the
    // sole writer of these five slots. Slot 0 counts the tiles that died
    // abnormally or reported a fatal fault (the supervisor's diag_crash_count);
    // slot 1 those that died before they ran. The field names predate the
    // fan-in.
    .{
        .id = tile_ids.tkdiag,
        .launch_mode = .stem,
        .counters = &.{
            .{ .idx = 0, .field = .diag_crashed_tile },
            .{ .idx = 1, .field = .diag_sandbox_failures },
            .{ .idx = 2, .field = .diag_tiles_reporting },
            .{ .idx = 3, .field = .diag_fragments_accepted },
            .{ .idx = 4, .field = .diag_fragments_rejected },
        },
        .diag = .collector,
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
        .max_instances = rt.model_tier.max_model_instances,
    },
    // tkagnt: the agent worker. One agent-request input and one result input
    // per configured tkmodl; one request output per tkmodl plus the audit
    // (tkaudt) and terminal-result (tkdisp) outputs. Its counters are written
    // by the tile; slots follow tk_agent_stem.c.
    .{
        .id = tile_ids.tkagnt,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{
            .{ .idx = 0, .field = .agent_dispatched },
            .{ .idx = 1, .field = .agent_results },
            .{ .idx = 2, .field = .agent_denied },
            .{ .idx = 3, .field = .agent_tokens },
            .{ .idx = 4, .field = .agent_embeddings },
        },
        .cardinality = .agent_fan,
    },
    // tkdisp: a bounded sink for tkagnt's terminal results, or, in the full
    // workflow, the scheduler that also turns each event from tkcase into one
    // agent request. Its committed results are read from scratch, so it
    // publishes no CNC counter slot.
    .{
        .id = tile_ids.tkdisp,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{},
        .cardinality = .disp_shape,
    },
    // tkcase, tktool and tkadpt: config-driven placeholders of the full
    // workflow (tk_pass_stem.c). They carry no case, tool or adapter logic:
    // tkcase forwards each event to its two consumers, tktool and tkadpt are
    // idle bounded consumers. Nothing is published on their audit links.
    .{
        .id = tile_ids.tkcase,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{},
        .in_cnt = 1,
        .out_cnt = 2,
    },
    .{
        .id = tile_ids.tktool,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{},
        .in_cnt = 1,
        .out_cnt = 2,
    },
    .{
        .id = tile_ids.tkadpt,
        .launch_mode = .stem,
        .process_fn = null,
        .counters = &.{},
        .in_cnt = 1,
        .out_cnt = 1,
    },
};

pub fn findById(tile_id: rt.tile.TileId) ?*const TileEntry {
    for (&entries) |*e| {
        if (e.id.eql(tile_id)) return e;
    }
    return null;
}

fn countTilesNamed(topo: rt.topology.Topology, name: rt.tile.TileId) usize {
    var n: usize = 0;
    for (topo.tiles) |t| {
        if (t.name.eql(name)) n += 1;
    }
    return n;
}

/// Inbound links this entry expects for one descriptor of the topology.
pub fn expectedInCnt(entry: *const TileEntry, topo: rt.topology.Topology) usize {
    const models = countTilesNamed(topo, tile_ids.tkmodl);
    return switch (entry.cardinality) {
        .fixed => entry.in_cnt,
        .audit_fan_in => if (models > 0)
            models + countTilesNamed(topo, tile_ids.tkagnt) + countTilesNamed(topo, tile_ids.tktool) +
                countTilesNamed(topo, tile_ids.tkadpt) + countTilesNamed(topo, tile_ids.tkpoly)
        else
            entry.in_cnt,
        .agent_fan => 1 + models,
        .disp_shape => if (countTilesNamed(topo, tile_ids.tkcase) > 0) 2 else 1,
    };
}

/// Outbound links this entry expects for one descriptor of the topology.
pub fn expectedOutCnt(entry: *const TileEntry, topo: rt.topology.Topology) usize {
    return switch (entry.cardinality) {
        .fixed, .audit_fan_in => entry.out_cnt,
        .agent_fan => countTilesNamed(topo, tile_ids.tkmodl) + 2 + countTilesNamed(topo, tile_ids.tktool),
        .disp_shape => if (countTilesNamed(topo, tile_ids.tkcase) > 0) 1 else 0,
    };
}

/// Checks tile registration and instance identity: every tile is registered,
/// only tiles with `max_instances > 1` repeat, and repeated tiles carry
/// distinct compact `kind_id`s in descriptor order.
pub fn validateInstances(topo: rt.topology.Topology) !void {
    for (topo.tiles) |t| {
        const entry = findById(t.name) orelse return error.UnregisteredTopologyTile;
        const instances = countTilesNamed(topo, t.name);
        if (instances > entry.max_instances) {
            return if (entry.max_instances == 1) error.DuplicateTopologyTile else error.TooManyTileInstances;
        }
    }
    try topo.validateIdentities();
}

/// Validates each configured tile against its registry entry and link shape.
/// The registry can contain tiles absent from a particular topology.
///
/// Diagnostic links (channels whose destination is tkdiag) are checked apart
/// from the pipeline cardinality: they must come from a `.producer` tile, at
/// most one per producer, be `.lossy` so a slow tkdiag can never backpressure
/// the event path, and be the producer's last output so a process tile finds it
/// at a fixed position. tkdiag's own input count is whatever diagnostic links
/// the topology wires, so only its pipeline links and outputs are compared.
pub fn validate(topo: rt.topology.Topology) !void {
    try validateInstances(topo);
    for (topo.tiles, 0..) |t, i| {
        const entry = findById(t.name).?;
        var in_cnt: usize = 0;
        var out_cnt: usize = 0;
        var diag_out_cnt: usize = 0;
        var last_pipeline_out: ?usize = null;
        var diag_out_pos: usize = 0;
        for (topo.channels, 0..) |ch, ch_idx| {
            if (ch.dst_idx >= topo.tiles.len) return error.LinkCardinalityMismatch;
            const to_diag = topo.tiles[ch.dst_idx].name.eql(tile_ids.tkdiag);
            if (to_diag and ch.reliability != .lossy) return error.DiagLinkMustBeLossy;
            if (ch.dst_idx == i and !to_diag) in_cnt += 1;
            if (ch.src_idx == i) {
                if (to_diag) {
                    diag_out_cnt += 1;
                    diag_out_pos = ch_idx;
                } else {
                    out_cnt += 1;
                    last_pipeline_out = ch_idx;
                }
            }
        }
        if (diag_out_cnt > 0 and (entry.diag != .producer or diag_out_cnt > 1)) return error.LinkCardinalityMismatch;
        if (in_cnt != expectedInCnt(entry, topo) or out_cnt != expectedOutCnt(entry, topo)) return error.LinkCardinalityMismatch;
        if (last_pipeline_out) |pipeline_pos| {
            if (diag_out_cnt == 1 and diag_out_pos < pipeline_pos) return error.DiagLinkNotLast;
        }
    }
}

test {
    _ = @import("tile_registry_test.zig");
}
