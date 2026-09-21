/// Concrete Tickoni product topologies: which tiles run and their channel
/// wiring for the payment pipeline and investment workflow. Layered
/// on the generic topology graph in src/tickoni/runtime/topology.zig, which
/// composes tile/link descriptor types from the runtime owners and validates
/// only graph structure, not the product tile plan itself.
const std = @import("std");
const rt = @import("runtime");

const TileId = rt.tile.TileId;
const TileDescriptor = rt.tile.TileDescriptor;
const Channel = rt.link.Channel;
const Topology = rt.topology.Topology;
const WorkspaceName = rt.link.WorkspaceName;

/// Whether a declared product topology has a supervisor/CLI dispatch path
/// today, so callers do not have to infer runtime support from tile count.
/// `runnable`: src/app/tickoni/supervisor.zig has a start path for it and
/// src/app/tickoni/main.zig's CLI exposes a command for that path.
/// `planned`: a declared architectural target with no dispatch path yet —
/// Supervisor.startPaymentPipeline()/startPaymentPipelineProcess() assume
/// exactly the 8 Phase 0 tile roles and will fail closed (assert) if handed
/// a differently-shaped topology.
pub const TopologyStatus = enum { runnable, planned };

// Minimal 2-tile topology: tkings (producer) -> tkaudt (consumer).
// One channel backed by tango_shm, one workspace — isolates the
// 2-workspace attach regression with minimal tile surface.
const payment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile" },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile" },
};
const payment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable },
};

const investment_tiles = [_]TileDescriptor{
    .{ .id = TileId.parse("tkings") catch unreachable, .name = "ingest_tile" },
    .{ .id = TileId.parse("tknorm") catch unreachable, .name = "normalize_tile" },
    .{ .id = TileId.parse("tkdedu") catch unreachable, .name = "dedupe_tile" },
    .{ .id = TileId.parse("tkcase") catch unreachable, .name = "case_router_tile" },
    .{ .id = TileId.parse("tkpoly") catch unreachable, .name = "policy_tile" },
    .{ .id = TileId.parse("tkaudt") catch unreachable, .name = "audit_tile" },
    .{ .id = TileId.parse("tkdisp") catch unreachable, .name = "agent_dispatch_tile" },
    .{ .id = TileId.parse("tkagnt") catch unreachable, .name = "agent_worker_tile" },
    .{ .id = TileId.parse("tkmodl") catch unreachable, .name = "model_gateway_tile" },
    .{ .id = TileId.parse("tktool") catch unreachable, .name = "tool_broker_tile" },
    .{ .id = TileId.parse("tkadpt") catch unreachable, .name = "adapter_tile" },
    .{ .id = TileId.parse("tkrepl") catch unreachable, .name = "replay_tile" },
    .{ .id = TileId.parse("tkmetr") catch unreachable, .name = "metric_tile" },
    .{ .id = TileId.parse("tkdiag") catch unreachable, .name = "diag_tile" },
};

const investment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 256 },
    .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 256 },
    .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 256 },
    .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 256 },
    .{ .src_idx = 3, .dst_idx = 6, .depth = 32, .mtu = 256 },
    .{ .src_idx = 6, .dst_idx = 7, .depth = 32, .mtu = 256 },
    .{ .src_idx = 7, .dst_idx = 8, .depth = 32, .mtu = 1024 },
    .{ .src_idx = 7, .dst_idx = 9, .depth = 32, .mtu = 512 },
    .{ .src_idx = 9, .dst_idx = 10, .depth = 32, .mtu = 512 },
    .{ .src_idx = 4, .dst_idx = 5, .depth = 64, .mtu = 256 },
    .{ .src_idx = 8, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 9, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 10, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 7, .dst_idx = 5, .depth = 32, .mtu = 256 },
    .{ .src_idx = 5, .dst_idx = 11, .depth = 32, .mtu = 256 },
};

/// Phase 0 in-process pipeline used by the Tickoni product supervisor.
///
///   tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
///   tkrepl, tkmetr, and tkdiag observe the deterministic run.
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
/// Phase 0 payment-pipeline roles. Exercised directly by demo/integration
/// tests (src/tickoni/test/demo/investment/**), not through the supervisor.
pub const investment_workflow_status: TopologyStatus = .planned;
pub fn investmentWorkflow() Topology {
    return .{
        .tiles = &investment_tiles,
        .channels = &investment_channels,
    };
}

// v2.14.S1 process-mode variant of paymentPipeline: tkings + tkaudt + tkmetr
// with one channel (tkings -> tkaudt); tkmetr has no channel wiring.
// Supervisor spawns all three and verifies they don't crash.
const payment_process_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable },
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

test "paymentPipeline has Phase 0 product tiles and 1 channel" {
    const topo = paymentPipeline();
    try std.testing.expectEqual(@as(usize, 3), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 1), topo.channels.len);
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[1].id.slice());
    try std.testing.expectEqualStrings("tkmetr", topo.tiles[2].id.slice());
}

test "paymentPipeline passes validation" {
    try paymentPipeline().validate();
}

test "runnable topologies have 3-tile shape for minimal debugging" {
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_status);
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_process_status);
    try std.testing.expectEqual(@as(usize, 3), paymentPipeline().tiles.len);
    try std.testing.expectEqual(@as(usize, 3), paymentPipelineProcess().tiles.len);
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

test "paymentPipelineProcess has 2 tiles, 1 channel, and passes validation" {
    const topo = paymentPipelineProcess();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 2), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 1), topo.channels.len);
    try std.testing.expectEqualStrings("tkings", topo.tiles[0].id.slice());
    try std.testing.expectEqualStrings("tkaudt", topo.tiles[1].id.slice());
}
