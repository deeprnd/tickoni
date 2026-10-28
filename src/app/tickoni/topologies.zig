/// Concrete Tickoni product topologies: which tiles run and their channel
/// wiring for the payment pipeline and investment workflow. Layered
/// on the generic topology graph in src/tickoni/runtime/topology.zig, which
/// composes tile/link descriptor types from the runtime owners and validates
/// only graph structure, not the product tile plan itself.
const std = @import("std");
const rt = @import("runtime");

const TileId = rt.tile.TileId;
const TileDescriptor = rt.tile.TileDescriptor;
const TileScratchReqs = rt.tile.TileScratchReqs;
const Channel = rt.link.Channel;
pub const Topology = rt.topology.Topology;
const WorkspaceName = rt.link.WorkspaceName;

/// Whether a declared product topology has a supervisor/CLI dispatch path
/// today, so callers do not have to infer runtime support from tile count.
/// `runnable`: src/app/tickoni/supervisor.zig has a start path for it and
/// src/app/tickoni/main.zig's CLI exposes a command for that path.
/// `planned`: a declared architectural target with no dispatch path yet —
/// Supervisor.startPaymentPipelineProcess() assumes exactly the 8 Phase 0
/// tile roles and will fail closed (assert) if handed a differently-shaped
/// topology.
pub const TopologyStatus = enum { runnable, planned };

// Static backing arrays for paymentPipeline — avoids returning pointers to
// stack-allocated data.
const payment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .scratch_reqs = .{ .scratch_align = 64, .footprint = 4096 } },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile" },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .scratch_reqs = .{ .scratch_align = 64, .footprint = 4096 } },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("metric") catch unreachable, .name = "metric", .scratch_reqs = .{ .scratch_align = 128, .footprint = 33554432 } },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

// Helper: pre-parse the tile IDs used in payment_channels so parse() never
// runs at runtime — comptime/unreachable keeps this zero-cost.
const p_ingest = TileId.parse("tkings") catch unreachable;
const p_normalize = TileId.parse("tknorm") catch unreachable;
const p_dedupe = TileId.parse("tkdedu") catch unreachable;
const p_policy = TileId.parse("tkpoly") catch unreachable;
const p_audit = TileId.parse("tkaudt") catch unreachable;

const payment_channels = [_]Channel{
    .{ .src_id = p_ingest, .dst_id = p_normalize, .depth = 64, .mtu = 128 },
    .{ .src_id = p_normalize, .dst_id = p_dedupe, .depth = 64, .mtu = 128 },
    .{ .src_id = p_dedupe, .dst_id = p_policy, .depth = 64, .mtu = 128 },
    .{ .src_id = p_policy, .dst_id = p_audit, .depth = 64, .mtu = 128 },
};

const investment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile", .scratch_reqs = .{ .scratch_align = 64, .footprint = 4096 } },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkcase") catch unreachable, .name = "case_router_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile" },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile", .scratch_reqs = .{ .scratch_align = 64, .footprint = 4096 } },
    .{ .id = TileId.parse("tkdisp") catch unreachable, .name = "agent_dispatch_tile" },
    .{ .id = TileId.parse("tkagnt") catch unreachable, .name = "agent_worker_tile" },
    .{ .id = TileId.parse("tkmodl") catch unreachable, .name = "model_gateway_tile" },
    .{ .id = TileId.parse("tktool") catch unreachable, .name = "tool_broker_tile" },
    .{ .id = TileId.parse("tkadpt") catch unreachable, .name = "adapter_tile" },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("metric") catch unreachable, .name = "metric", .scratch_reqs = .{ .scratch_align = 128, .footprint = 33554432 } },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

// Helper: pre-parse the tile IDs used in investment_channels so parse()
// never runs at runtime — comptime/unreachable keeps this zero-cost.
const i_ingest = TileId.parse("tkings") catch unreachable;
const i_normalize = TileId.parse("tknorm") catch unreachable;
const i_dedupe = TileId.parse("tkdedu") catch unreachable;
const i_case = TileId.parse("tkcase") catch unreachable;
const i_policy = TileId.parse("tkpoly") catch unreachable;
const i_audit = TileId.parse("tkaudt") catch unreachable;
const i_dispatch = TileId.parse("tkdisp") catch unreachable;
const i_agent = TileId.parse("tkagnt") catch unreachable;
const i_model = TileId.parse("tkmodl") catch unreachable;
const i_tool = TileId.parse("tktool") catch unreachable;
const i_adapter = TileId.parse("tkadpt") catch unreachable;
const i_replay = TileId.parse("tkrepl") catch unreachable;

const investment_channels = [_]Channel{
    .{ .src_id = i_ingest, .dst_id = i_normalize, .depth = 64, .mtu = 256 },
    .{ .src_id = i_normalize, .dst_id = i_dedupe, .depth = 64, .mtu = 256 },
    .{ .src_id = i_dedupe, .dst_id = i_case, .depth = 64, .mtu = 256 },
    .{ .src_id = i_case, .dst_id = i_policy, .depth = 64, .mtu = 256 },
    .{ .src_id = i_case, .dst_id = i_dispatch, .depth = 32, .mtu = 256 },
    .{ .src_id = i_dispatch, .dst_id = i_agent, .depth = 32, .mtu = 256 },
    .{ .src_id = i_agent, .dst_id = i_model, .depth = 32, .mtu = 1024 },
    .{ .src_id = i_agent, .dst_id = i_tool, .depth = 32, .mtu = 512 },
    .{ .src_id = i_tool, .dst_id = i_adapter, .depth = 32, .mtu = 512 },
    .{ .src_id = i_policy, .dst_id = i_audit, .depth = 64, .mtu = 256 },
    .{ .src_id = i_model, .dst_id = i_audit, .depth = 32, .mtu = 256 },
    .{ .src_id = i_tool, .dst_id = i_audit, .depth = 32, .mtu = 256 },
    .{ .src_id = i_adapter, .dst_id = i_audit, .depth = 32, .mtu = 256 },
    .{ .src_id = i_agent, .dst_id = i_audit, .depth = 32, .mtu = 256 },
    .{ .src_id = i_audit, .dst_id = i_replay, .depth = 32, .mtu = 256 },
};

/// Phase 0 in-process pipeline used by the Tickoni product supervisor.
///
///   tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
///   tkrepl, metric, and tkdiag observe the deterministic run.
///
/// No Solana validator tiles are registered in this topology.
/// Status: runnable, via `tickoni-supervisor start` (Supervisor.startPaymentPipeline).
pub const payment_pipeline_status: TopologyStatus = .runnable;
pub fn paymentPipeline() Topology {
    return .{
        .tiles = &payment_tiles,
        .channels = &payment_channels,
    };
}

/// Declared Phase 1/2 investment workflow shape (tkcase, agent-harness
/// tiles, tkmodl/tktool/tkadpt). Status: planned, not runnable — no CLI
/// command or Supervisor start path dispatches these 14 tiles today;
/// Supervisor.startPaymentPipeline()/startPaymentPipelineProcess() assert
/// exactly 8 tiles and only have thread/process run functions for the
/// Phase 0 payment-pipeline roles. Exercised directly by fixture/integration
/// tests (src/tickoni/test/fixtures/investment/**), not through the supervisor.
pub const investment_workflow_status: TopologyStatus = .planned;
pub fn investmentWorkflow() Topology {
    return .{
        .tiles = &investment_tiles,
        .channels = &investment_channels,
    };
}

// v2.14.S1 process-mode variant of paymentPipeline: same 8 tiles and 4
// core channels, backed by Tango shared memory in one shared workspace
// instead of the heap-backed dev/test ring. All tiles are floating (no
// hard exclusive-core requirement); src/app/tickoni/supervisor.zig's
// process-mode start path assigns concrete CPU placement per config.
const payment_process_channels = [_]Channel{
    .{
        .src_id = p_ingest,
        .dst_id = p_normalize,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_id = p_normalize,
        .dst_id = p_dedupe,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_id = p_dedupe,
        .dst_id = p_policy,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_id = p_policy,
        .dst_id = p_audit,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// v2.14.S1 process-isolated variant of paymentPipeline(): the same tile
/// identities and channel shape, with every core channel backed by a
/// shared Tango workspace instead of a heap-backed ring. CPU placement
/// defaults to floating here; callers that need exclusive/shared pinning
/// build their own TileDescriptor slice with cpu_placement set.
/// Status: runnable, via `tickoni-supervisor start-process <run-dir>`
/// (Supervisor.startPaymentPipelineProcess).
pub const payment_pipeline_process_status: TopologyStatus = .runnable;
pub fn paymentPipelineProcess() Topology {
    return .{
        .tiles = &payment_tiles,
        .channels = &payment_process_channels,
    };
}

test "paymentPipeline has Phase 0 product tiles and channels" {
    const topo = paymentPipeline();
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4), topo.channels.len);
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[4].id.slice());
    try std.testing.expectEqualStrings("tkdiag", topo.tiles[7].id.slice());
    try std.testing.expect(p_ingest.eql(topo.channels[0].src_id));
    try std.testing.expect(p_normalize.eql(topo.channels[0].dst_id));
}

test "paymentPipeline passes validation" {
    try paymentPipeline().validate();
}

test "runnable topologies have the 8-tile shape Supervisor's start paths assert" {
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_status);
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_process_status);
    try std.testing.expectEqual(@as(usize, 8), paymentPipeline().tiles.len);
    try std.testing.expectEqual(@as(usize, 8), paymentPipelineProcess().tiles.len);
}

test "investmentWorkflow is marked planned, not runnable" {
    try std.testing.expectEqual(TopologyStatus.planned, investment_workflow_status);
}

test "investmentWorkflow includes tkmodl tktool tkadpt and passes validation" {
    const topo = investmentWorkflow();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 14), topo.tiles.len);
    try std.testing.expectEqualStrings("tkmodl", topo.tiles[8].id.slice());
    try std.testing.expectEqualStrings("tktool", topo.tiles[9].id.slice());
    try std.testing.expectEqualStrings("tkadpt", topo.tiles[10].id.slice());
    try std.testing.expectEqualStrings("tkrepl", topo.tiles[11].id.slice());
}

test "paymentPipelineProcess has 8 tiles, 4 tango_shm channels, and passes validation" {
    const topo = paymentPipelineProcess();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4), topo.channels.len);
    for (topo.channels) |ch| {
        try std.testing.expectEqual(rt.link.LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqual(rt.link.LinkReliability.reliable, ch.reliability);
        try std.testing.expectEqualStrings("tkpay0", ch.workspace_name.slice());
    }
}
