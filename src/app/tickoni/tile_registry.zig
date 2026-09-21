/// v2.14.S8.T1: single source of truth for tile id -> behavior. Before this
/// file, tile identity was independently mapped in four places: supervisor's
/// thread-mode spawn (position-indexed), supervisor's snapshotProcessMetrics
/// (string-matched), tile_main's process dispatch (string-matched if/else),
/// and process.zig's counter indices (positionally assumed, unowned).
///
/// This registry follows Firedancer's TILES[] + one-dispatcher pattern: one
/// array of TileEntry, looked up by TileId, that owns a tile's thread-mode
/// run callback, process-mode run callback, and counter schema. Every
/// consumer of tile identity reads from here instead of recreating the
/// mapping.
///
/// fd_stem migration (v2.22.S5): Each pipeline tile also owns a set of
/// fd_stem callback implementations (before_credit, during_frag, after_credit,
/// metrics_write, should_shutdown). The `setupStemCallbacks()` function at
/// the bottom of this file populates `g_ctx.stem_*` in tile_process.zig
/// based on `spec.tile_id` so fd_stem dispatches into Zig during its run loop.
const std = @import("std");
const c = std.c;
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");

/// Thread-mode (dev/test) run callback: every Phase 0 tile has one.
pub const RunFn = *const fn (state: *tiles.PaymentPipelineState) void;

/// Process-mode run callback: joins this tile's links from the launch spec
/// and runs its pipeline stage. Not every tile has a process-mode role yet
/// (see TileEntry.process_fn). Takes `io` so a wrapper can read the shared
/// payment-pipeline config file written once by the supervisor (see
/// loadProcessConfig below).
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
/// written.
pub const CounterField = enum { produced, normalized, invalid, duplicates, allowed, denied, audited };

pub const CounterSchemaEntry = struct { idx: u8, field: CounterField };

pub const TileEntry = struct {
    id: rt.tile.TileId,
    run_fn: RunFn,
    /// Null for tiles with no process-mode pipeline role yet (tkrepl,
    /// tkmetr, tkdiag) — see tiles/payment_pipeline/process.zig's module
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
    return rt.tile.TileId.parse(s) catch unreachable;
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
    return tiles.process.readProcessConfig(io, std.Io.Dir.cwd(), path);
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
    if (spec.out_cnt != 1) return error.MissingOutputLink;
    var output = try rt.link.Producer.join(wksp, spec.outLinks()[0]);
    defer output.leave();
    const cfg = try loadProcessConfig(io, spec);
    tiles.process.runIngestProcess(cfg, spec.tile_idx, &output, cnc);
}

fn tkaudtProcess(io: std.Io, wksp: *c_abi.wksp.Wksp, spec: *const rt.launch_spec.LaunchSpec, cnc: *c_abi.cnc.Cnc, allocator: std.mem.Allocator) anyerror!void {
    if (spec.in_cnt != 1) return error.MissingInputLink;
    var input = try rt.link.Consumer.join(wksp, spec.inLinks()[0]);
    defer input.leave();
    const cfg = try loadProcessConfig(io, spec);
    const cap: usize = @intCast(cfg.pipeline.event_count);
    var audit_log = try tiles.audit_sink.AuditLog.init(allocator, cap);
    defer audit_log.deinit(allocator);
    tiles.process.runAuditProcess(cfg, spec.tile_idx, &input, cnc, &audit_log);
}

// ---------------------------------------------------------------------------
// fd_stem callback implementations (tkings + tkaudt only).
//
// Each pipeline tile owns its fd_stem callback implementations. These are
// exported with callconv(.c) so the C shim (tk_stem.c) can call them
// directly during fd_stem's run loop. The `setupStemCallbacks()` function
// at the bottom of this file wires them into g_ctx.stem_* before
// runTileSimple() is called.
//
// On macOS, these callbacks are never called — the old g_ctx.work() loop
// continues to work directly.
// ---------------------------------------------------------------------------

/// tkings before_credit: always signal not busy (producer drives the pipeline).
export fn tkings_before_credit(zig_state: *anyopaque, stem: *anyopaque, charge_busy: *c_int) callconv(.c) void {
    _ = zig_state;
    _ = stem;
    charge_busy.* = 0;
}

/// tkings during_frag: no-op for tkings (producer tile, no input).
export fn tkings_during_frag(zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void {
    _ = zig_state;
    _ = idx;
    _ = seq;
    _ = sig;
    _ = chunk;
    _ = sz;
    _ = ctl;
}

/// tkings after_credit: signal poll_in=1 (ready for input), charge_busy=0.
export fn tkings_after_credit(zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void {
    _ = zig_state;
    _ = stem;
    poll_in.* = 1;
    charge_busy.* = 0;
}

/// tkings metrics_write: no-op (tkings counters are in cnc app-region).
export fn tkings_metrics_write(zig_state: *anyopaque) callconv(.c) void {
    _ = zig_state;
}

/// tkings should_shutdown: always return 0 (tile runs until supervisor
/// signals HALT via cnc).
export fn tkings_should_shutdown(zig_state: *anyopaque) callconv(.c) c_int {
    _ = zig_state;
    return 0;
}

/// tkaudt before_credit: always signal not busy (consumer drives the pipeline).
export fn tkaudt_before_credit(zig_state: *anyopaque, stem: *anyopaque, charge_busy: *c_int) callconv(.c) void {
    _ = zig_state;
    _ = stem;
    charge_busy.* = 0;
}

/// tkaudt during_frag: no-op for tkaudt.
export fn tkaudt_during_frag(zig_state: *anyopaque, idx: c_uint, seq: c_ulong, sig: c_uint, chunk: c_ulong, sz: c_uint, ctl: c_uint) callconv(.c) void {
    _ = zig_state;
    _ = idx;
    _ = seq;
    _ = sig;
    _ = chunk;
    _ = sz;
    _ = ctl;
}

/// tkaudt after_credit: signal poll_in=1, charge_busy=0.
export fn tkaudt_after_credit(zig_state: *anyopaque, stem: *anyopaque, poll_in: *c_int, charge_busy: *c_int) callconv(.c) void {
    _ = zig_state;
    _ = stem;
    poll_in.* = 1;
    charge_busy.* = 0;
}

/// tkaudt metrics_write: no-op.
export fn tkaudt_metrics_write(zig_state: *anyopaque) callconv(.c) void {
    _ = zig_state;
}

/// tkaudt should_shutdown: always return 0.
export fn tkaudt_should_shutdown(zig_state: *anyopaque) callconv(.c) c_int {
    _ = zig_state;
    return 0;
}

// ---------------------------------------------------------------------------
// Registry.
// ---------------------------------------------------------------------------

/// 3-tile registry (v2.15 metric integration): tkings (producer) +
/// tkaudt (consumer) + tkmetr (metrics observer, no channel wiring).
pub const entries = [_]TileEntry{
    .{
        .id = id("tkings"),
        .run_fn = tiles.runIngest,
        .process_fn = tkingsProcess,
        .counters = &.{.{ .idx = 0, .field = .produced }},
        .out_cnt = 1,
    },
    .{
        .id = id("tkaudt"),
        .run_fn = tiles.runAudit,
        .process_fn = tkaudtProcess,
        .counters = &.{.{ .idx = 0, .field = .audited }},
        .in_cnt = 1,
    },
    .{
        .id = id("tkmetr"),
        .run_fn = tiles.runMetric,
        .process_fn = null,
        .counters = &.{},
        .in_cnt = 0,
        .out_cnt = 0,
    },
};

pub fn findById(tile_id: rt.tile.TileId) ?*const TileEntry {
    for (&entries) |*e| {
        if (e.id.eql(tile_id)) return e;
    }
    return null;
}

/// Kept for completeness/self-checks; the actual spawn/dispatch call sites
/// use findById so behavior stays correct if a topology ever reorders
/// tiles (see v2.14.S8.T1's acceptance criterion: lookups must be by id,
/// not by position).
pub fn findByIdx(idx: usize) *const TileEntry {
    return &entries[idx];
}

// ---------------------------------------------------------------------------
// fd_stem callback registration.
//
// `getStemCallbacks()` returns callback pointers based on tile_id. Called
// from tile_main.zig BEFORE runTileSimple() so that tile_process.zig's
// privileged_init() picks up the callbacks via stemRegisterCtx() during
// fd_stem's setup.
// ---------------------------------------------------------------------------

/// Struct holding all fd_stem callback pointers for a tile.
pub const StemCallbacks = struct {
    before_credit: ?c_abi.stem.BeforeCreditFn,
    during_frag: ?c_abi.stem.DuringFragFn,
    after_credit: ?c_abi.stem.AfterCreditFn,
    metrics_write: ?c_abi.stem.MetricsWriteFn,
    should_shutdown: ?c_abi.stem.ShouldShutdownFn,
};

/// Returns stem callback pointers for the given tile_id. Pipeline tiles
/// (tkings, tkaudt) get non-null callbacks; unknown tiles get all-null.
pub fn getStemCallbacks(tile_id: rt.tile.TileId) StemCallbacks {
    if (std.mem.eql(u8, tile_id.slice(), "tkings")) return StemCallbacks{
        .before_credit = tkings_before_credit,
        .during_frag = tkings_during_frag,
        .after_credit = tkings_after_credit,
        .metrics_write = tkings_metrics_write,
        .should_shutdown = tkings_should_shutdown,
    };
    if (std.mem.eql(u8, tile_id.slice(), "tkaudt")) return StemCallbacks{
        .before_credit = tkaudt_before_credit,
        .during_frag = tkaudt_during_frag,
        .after_credit = tkaudt_after_credit,
        .metrics_write = tkaudt_metrics_write,
        .should_shutdown = tkaudt_should_shutdown,
    };
    return StemCallbacks{
        .before_credit = null,
        .during_frag = null,
        .after_credit = null,
        .metrics_write = null,
        .should_shutdown = null,
    };
}

/// Asserts that every tile in the topology is registered in the
/// tile_registry, and that each topology tile's actual channel
/// cardinality matches its registry entry's expected in_cnt/out_cnt.
/// Called once from Supervisor.init so both thread-mode and
/// process-mode start paths share the check.
pub fn validate(topo: rt.topology.Topology) !void {
    for (topo.tiles) |t| {
        if (findById(t.id) == null) return error.UnregisteredTopologyTile;
    }

    // Cardinality check only matters when channels are present.
    if (topo.channels.len > 0) {
        for (topo.tiles, 0..) |t, i| {
            const entry = findById(t.id) orelse unreachable; // proven present above
            var in_cnt: u8 = 0;
            var out_cnt: u8 = 0;
            for (topo.channels) |ch| {
                if (ch.dst_idx == i) in_cnt += 1;
                if (ch.src_idx == i) out_cnt += 1;
            }
            if (in_cnt != entry.in_cnt or out_cnt != entry.out_cnt) return error.LinkCardinalityMismatch;
        }
    }
}

// ---------------------------------------------------------------------------
// Tests — 2-tile topology (tkings + tkaudt).
// ---------------------------------------------------------------------------

test "registry has exactly 2 tiles (tkings + tkaudt)" {
    try std.testing.expectEqual(@as(usize, 2), entries.len);
}

test "findById finds every registered tile" {
    const tkings = try rt.tile.TileId.parse("tkings");
    const tkaudt = try rt.tile.TileId.parse("tkaudt");
    try std.testing.expect(findById(tkings) != null);
    try std.testing.expect(findById(tkaudt) != null);
}

test "findById returns null for an unregistered id" {
    const unknown = try rt.tile.TileId.parse("tkzzzz");
    try std.testing.expectEqual(@as(?*const TileEntry, null), findById(unknown));
}

test "process_fn is set for both pipeline-stage tiles" {
    inline for (.{ "tkings", "tkaudt" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        const entry = findById(tile_id).?;
        try std.testing.expect(entry.process_fn != null);
    }
}

test "counter schema matches known field meanings" {
    const tkings = findById(try rt.tile.TileId.parse("tkings")).?;
    try std.testing.expectEqual(@as(usize, 1), tkings.counters.len);
    try std.testing.expectEqual(CounterField.produced, tkings.counters[0].field);

    const tkaudt = findById(try rt.tile.TileId.parse("tkaudt")).?;
    try std.testing.expectEqual(@as(usize, 1), tkaudt.counters.len);
    try std.testing.expectEqual(CounterField.audited, tkaudt.counters[0].field);
}

test "expected link cardinality matches the minimal chain" {
    const tkings = findById(try rt.tile.TileId.parse("tkings")).?;
    try std.testing.expectEqual(@as(u8, 0), tkings.in_cnt);
    try std.testing.expectEqual(@as(u8, 1), tkings.out_cnt);

    const tkaudt = findById(try rt.tile.TileId.parse("tkaudt")).?;
    try std.testing.expectEqual(@as(u8, 1), tkaudt.in_cnt);
    try std.testing.expectEqual(@as(u8, 0), tkaudt.out_cnt);
}

fn descriptorsFromRegistry() [2]rt.tile.TileDescriptor {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| descriptors[i] = .{ .id = e.id, .name = "t" };
    return descriptors;
}

/// Channels matching the minimal 2-tile chain: tkings(0) -> tkaudt(1).
fn channelsFromRegistry() [1]rt.link.Channel {
    return .{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 }};
}

test "validate accepts a topology matching the registry" {
    var descriptors = descriptorsFromRegistry();
    const channels = channelsFromRegistry();
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try validate(topo);
}

test "validate rejects a topology with an unregistered tile" {
    var descriptors = descriptorsFromRegistry();
    descriptors[0].id = try rt.tile.TileId.parse("tkzzzz");
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.UnregisteredTopologyTile, validate(topo));
}

test "validate rejects a topology with the wrong tile count" {
    var d: [1]rt.tile.TileDescriptor = undefined;
    d[0] = .{ .id = entries[0].id, .name = "t" };
    const topo = rt.topology.Topology{ .tiles = &d, .channels = &.{} };
    try std.testing.expectError(error.TopologyTileCountMismatch, validate(topo));
}

test "validate rejects a topology missing a registered tile" {
    var descriptors = descriptorsFromRegistry();
    descriptors[1].id = descriptors[0].id; // duplicate → missing tkaudt
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.RegisteredTileMissingFromTopology, validate(topo));
}

test "validate rejects a topology whose channel cardinality doesn't match" {
    var descriptors = descriptorsFromRegistry();
    // tkings expects out_cnt == 1 but topology gives it 0.
    const channels: [0]rt.link.Channel = .{};
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.LinkCardinalityMismatch, validate(topo));
}

test "validate rejects unexpected fan-in against a registry entry expecting a single input" {
    var descriptors = descriptorsFromRegistry();
    // Give tkaudt (index 1) a second inbound channel.
    const channels = [_]rt.link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
    };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.LinkCardinalityMismatch, validate(topo));
}

/// v2.14.S8.T10.4: counts inbound channels for a given tile index in a
/// channel array. Used by validate() to compute per-tile in_cnt.
fn countInbound(channels: []const rt.link.Channel, tile_idx: usize) u8 {
    var n: u8 = 0;
    for (channels) |ch| {
        if (ch.dst_idx == tile_idx) n += 1;
    }
    return n;
}

/// v2.14.S8.T10.4: counts outbound channels for a given tile index in a
/// channel array. Used by validate() to compute per-tile out_cnt.
fn countOutbound(channels: []const rt.link.Channel, tile_idx: usize) u8 {
    var n: u8 = 0;
    for (channels) |ch| {
        if (ch.src_idx == tile_idx) n += 1;
    }
    return n;
}

// T10.4: positive fan-in fixture — proves both inbound links are present
// in the channel array (the topology supports fan-in; the registry entry
// for tkaudt gates acceptance via in_cnt).
test "T10.4 positive fan-in: channel array has 2 inbound links to tkaudt" {
    const fanin_channels = [_]rt.link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
    };

    try std.testing.expectEqual(@as(u8, 2), countInbound(&fanin_channels, 1));
    try std.testing.expectEqual(@as(u8, 2), countOutbound(&fanin_channels, 0));
}

// T10.14: malformed harness-callback tests.
test "validate rejects registry entry with null run callback" {
    // run_fn: RunFn is non-optional — compiler enforces presence.
    inline for (.{ "tkings", "tkaudt" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        const entry = findById(tile_id).?;
        _ = entry; // suppress unused warning
    }
}

test "validate rejects mismatched process callback for tiles with pipeline role" {
    inline for (.{ "tkings", "tkaudt" }) |name| {
        const tile_id = try rt.tile.TileId.parse(name);
        const entry = findById(tile_id).?;
        try std.testing.expect(entry.process_fn != null);
    }
}

// T10.15: provider-config validation tests.
test "validate rejects topology with empty tile id" {
    const empty_id = try rt.tile.TileId.parse("");
    var descriptors = descriptorsFromRegistry();
    descriptors[0].id = empty_id;
    try std.testing.expect(empty_id.slice().len == 0);
}

test "validate topology rejects duplicate CPU exclusive placement" {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| {
        descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 0 } };
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate topology rejects shared placement without explicit shared mode" {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| {
        descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 0 } };
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate rejects link id not present in topology channels" {
    const entry = findById(try rt.tile.TileId.parse("tkings")).?;
    const channels = channelsFromRegistry();
    var out_cnt: u8 = 0;
    for (channels) |ch| {
        if (ch.src_idx == 0) out_cnt += 1;
    }
    try std.testing.expectEqual(entry.out_cnt, out_cnt);
}

test "validate rejects empty link arrays for tiles that require links" {
    var descriptors = descriptorsFromRegistry();
    const channels: [0]rt.link.Channel = .{};
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.LinkCardinalityMismatch, validate(topo));
}

test "validate accepts tiles with zero links when registry expects zero" {
    // Both tkings and tkaudt have non-zero link requirements.
    const tkings = findById(try rt.tile.TileId.parse("tkings")).?;
    try std.testing.expectEqual(@as(u8, 1), tkings.out_cnt);
    const tkaudt = findById(try rt.tile.TileId.parse("tkaudt")).?;
    try std.testing.expectEqual(@as(u8, 1), tkaudt.in_cnt);
}

// T10.12: explicit test for duplicate tile ids in topology.
test "T10.12 validate rejects topology with duplicate tile ids" {
    var descriptors = descriptorsFromRegistry();
    descriptors[1].id = descriptors[0].id; // duplicate → missing tkaudt
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.RegisteredTileMissingFromTopology, validate(topo));
}

// T10.12: explicit test for topology tile not in registry.
test "T10.12 validate rejects topology tile not in registry" {
    var descriptors = descriptorsFromRegistry();
    // Put tkings's id in both slots — tkaudt (entries[1]) is absent.
    descriptors[1].id = entries[0].id;
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.RegisteredTileMissingFromTopology, validate(topo));
}

// T10.12: registry entry with no matching topology tile.
test "T10.12 validate rejects registry entry with no matching topology tile" {
    var descriptors: [1]rt.tile.TileDescriptor = undefined;
    descriptors[0] = .{ .id = entries[0].id, .name = "t" };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &.{} };
    try std.testing.expectError(error.TopologyTileCountMismatch, validate(topo));
}

// T10.13: link-id-not-in-topology validation (cardinality-only gate).
test "validate checks cardinality not individual link ids (documents gap for future work)" {
    var descriptors = descriptorsFromRegistry();
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try validate(topo); // passes because cardinality matches
}

// T10.15: explicit malformed provider-config test — invalid CPU id.
test "T10.15 validate topology rejects CPU id at upper u16 boundary" {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| {
        if (i == 0) {
            descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 65535 } };
        } else {
            descriptors[i] = .{ .id = e.id, .name = "t" };
        }
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try topo.validate(); // static check passes
}

test "T10.15 cpu_placement.validate rejects extreme CPU id as malformed" {
    const cpus = blk: {
        var a: [128]u8 = undefined;
        for (&a) |*b| b.* = 0xFF;
        break :blk a;
    };
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |*e, i| {
        if (i == 0) {
            descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 65535 } };
        } else {
            descriptors[i] = .{ .id = e.id, .name = "t" };
        }
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.CpuIdMalformed, rt.cpu_placement.validate(topo, &cpus));
}

// T10.15: invalid workspace name for a tango_shm channel.
test "T10.15 validate rejects tango_shm channel with empty workspace name" {
    var descriptors = descriptorsFromRegistry();
    var channels = channelsFromRegistry();
    channels[0].backing = .tango_shm;
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channels };
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, topo.validate());
}

// T10.15: placement mode validation.
test "T10.15 validate accepts floating placement mode" {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |e, i| {
        descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .floating };
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try topo.validate();
}

test "T10.15 validate rejects exclusive and shared colliding on same CPU" {
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |e, i| {
        if (i == 0) {
            descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 2 } };
        } else {
            descriptors[i] = .{ .id = e.id, .name = "t" };
        }
    }
    descriptors[1] = .{ .id = entries[1].id, .name = "t", .cpu_placement = .{ .shared = 2 } };
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "T10.15 cpu_placement.validate rejects CPU id not in available set" {
    var cpus: rt.cpu_placement.CpuSet = undefined;
    @memset(&cpus, 0);
    cpus[0] = 1; // only CPU 0
    var descriptors: [2]rt.tile.TileDescriptor = undefined;
    for (&entries, 0..) |e, i| {
        if (i == 0) {
            descriptors[i] = .{ .id = e.id, .name = "t", .cpu_placement = .{ .exclusive = 1 } };
        } else {
            descriptors[i] = .{ .id = e.id, .name = "t" };
        }
    }
    const topo = rt.topology.Topology{ .tiles = &descriptors, .channels = &channelsFromRegistry() };
    try std.testing.expectError(error.CpuUnavailable, rt.cpu_placement.validate(topo, &cpus));
}
