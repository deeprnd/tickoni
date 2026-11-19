/// Concrete Tickoni product topologies: which tiles run and their channel
/// wiring for the payment pipeline and investment workflow. Layered
/// on the generic topology graph in src/tickoni/runtime/topology.zig, which
/// composes tile/link descriptor types from the runtime owners and validates
/// only graph structure, not the product tile plan itself.
const std = @import("std");
const rt = @import("runtime");
const tile_ids = rt.tile_ids;
const audit_mod = @import("audit_mod");

const TileId = rt.tile.TileId;
const TileDescriptor = rt.tile.TileDescriptor;
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
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tknorm },
    .{ .id = 2, .name = tile_ids.tkdedu },
    .{ .id = 3, .name = tile_ids.tkpoly },
    .{ .id = 4, .name = tile_ids.tkaudt },
    .{ .id = 5, .name = tile_ids.tkrepl },
    .{ .id = 6, .name = tile_ids.metric },
    .{ .id = 7, .name = tile_ids.tkdiag },
};
const payment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
    .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
    .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = 128 },
    .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = 128 },
};

const investment_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tknorm },
    .{ .id = 2, .name = tile_ids.tkdedu },
    .{ .id = 3, .name = tile_ids.tkcase },
    .{ .id = 4, .name = tile_ids.tkpoly },
    .{ .id = 5, .name = tile_ids.tkaudt },
    .{ .id = 6, .name = tile_ids.tkdisp },
    .{ .id = 7, .name = tile_ids.tkagnt },
    .{ .id = 8, .name = tile_ids.tkmodl },
    .{ .id = 9, .name = tile_ids.tktool },
    .{ .id = 10, .name = tile_ids.tkadpt },
    .{ .id = 11, .name = tile_ids.tkrepl },
    .{ .id = 12, .name = tile_ids.metric },
    .{ .id = 13, .name = tile_ids.tkdiag },
};

/// One reliable shared-memory link of the full workflow, in the one workspace
/// every process-mode tile joins.
fn investmentLink(src: u32, dst: u32, depth: u32, mtu: u32) Channel {
    return .{
        .src_idx = src,
        .dst_idx = dst,
        .depth = depth,
        .mtu = mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkinv0") catch unreachable,
    };
}

const investment_channels = [_]Channel{
    investmentLink(0, 1, 64, 128),
    investmentLink(1, 2, 64, 128),
    investmentLink(2, 3, 64, 128),
    // tkcase -> tkpoly (the policy path) and tkcase -> tkdisp (the dispatch path).
    investmentLink(3, 4, 64, 128),
    investmentLink(3, 6, 64, 128),
    // tkdisp -> tkagnt carries agent requests: a multipart content link.
    investmentLink(6, 7, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_MP_LINK_MTU),
    // tkagnt -> tkmodl carries model requests: a multipart content link.
    investmentLink(7, 8, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_MP_LINK_MTU),
    // tkagnt -> tktool -> tkadpt: the tool and adapter paths. No tool call exists
    // yet, so these links are declared and bound and carry nothing.
    investmentLink(7, 9, 32, 512),
    investmentLink(9, 10, 32, 512),
    // Every audit producer feeds tkaudt. tktool and tkadpt have no audit record
    // type yet, so their links are idle.
    investmentLink(4, 5, 64, 128),
    investmentLink(8, 5, 32, 256),
    investmentLink(9, 5, 32, 256),
    investmentLink(10, 5, 32, 256),
    // tkagnt -> tkaudt: the agent's audit record (proposal or denial).
    investmentLink(7, 5, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_AGENT_AUDIT_LINK_MTU),
    // The agent's return paths: the model's result back to tkagnt (a multipart
    // content link), and tkagnt's terminal result to tkdisp.
    investmentLink(8, 7, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_MP_LINK_MTU),
    investmentLink(7, 6, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_AGENT_RESULT_LINK_MTU),
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

/// The full investment workflow: all 14 tiles, one process each, on reliable
/// shared-memory links.
///
///   events:    tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt
///   dispatch:  tkcase -> tkdisp -> tkagnt (agent request)
///   model:     tkagnt -> tkmodl -> tkagnt (request, result); tkmodl -> tkaudt (audit)
///   agent:     tkagnt -> tkaudt (audit), tkagnt -> tkdisp (terminal result)
///   idle:      tkagnt -> tktool -> tkadpt, and tktool, tkadpt -> tkaudt
///   tkrepl, metric and tkdiag observe the run.
///
/// tkcase, tktool and tkadpt are config-driven placeholders: they carry no case,
/// tool or adapter logic. tkdisp is the scheduler that turns each event it
/// receives from tkcase into one agent request from a fixed, config-supplied
/// template. `tkaudt -> tkrepl` is not a link: replay reads the committed audit
/// chain, which has no consumer tile yet.
/// Status: runnable, through the supervisor's process-mode start path
/// (Supervisor.startPaymentPipelineProcess) given a dispatch template and the
/// per-instance tkmodl configuration; exercised end to end by
/// src/tickoni/test/integration/test_tile_tkagnt.zig.
pub const investment_workflow_status: TopologyStatus = .runnable;
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
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 3,
        .dst_idx = 4,
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

/// Minimal 3-tile topology for isolation testing: tkings → tkaudt (+ metric).
/// The metric tile is required so Firedancer's fd_topo_fill_tile can set
/// tile_c->metrics to a non-NULL value; without it every tile gets a NULL
/// metrics pointer and tk_topo_run_tile's FD_TEST(tile_c->metrics) asserts.
const minimal_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tkaudt },
    .{ .id = 2, .name = tile_ids.metric },
};
const minimal_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// Minimal 3-tile topology (tkings → tkaudt + metric observer tile).
pub fn minimalProcess() Topology {
    return .{
        .tiles = &minimal_tiles,
        .channels = &minimal_channels,
    };
}

/// Minimal 4-tile topology for testing tknorm in the event pipeline:
/// tkings → tknorm → tkaudt (+ metric observer).
/// The metric tile is required so Firedancer's fd_topo_fill_tile sets
/// tile_c->metrics to a non-NULL value for every tile.
const minimal_with_norm_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tknorm },
    .{ .id = 2, .name = tile_ids.tkaudt },
    .{ .id = 3, .name = tile_ids.metric },
};
const minimal_with_norm_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// Minimal 4-tile topology (tkings → tknorm → tkaudt + metric observer).
pub fn minimalWithNormProcess() Topology {
    return .{
        .tiles = &minimal_with_norm_tiles,
        .channels = &minimal_with_norm_channels,
    };
}

/// Minimal 5-tile topology for testing tkdedu in the event pipeline:
/// tkings → tknorm → tkdedu → tkaudt (+ metric observer).
/// The metric tile is required so Firedancer's fd_topo_fill_tile sets
/// tile_c->metrics to a non-NULL value for every tile.
const minimal_with_dedu_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tknorm },
    .{ .id = 2, .name = tile_ids.tkdedu },
    .{ .id = 3, .name = tile_ids.tkaudt },
    .{ .id = 4, .name = tile_ids.metric },
};
const minimal_with_dedu_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// Minimal 5-tile topology (tkings → tknorm → tkdedu → tkaudt + metric observer).
pub fn minimalWithDeduProcess() Topology {
    return .{
        .tiles = &minimal_with_dedu_tiles,
        .channels = &minimal_with_dedu_channels,
    };
}

/// The agent process graph for `n` configured tkmodl instances (1..11), the
/// shape the tkagnt migration plan counts: N+5 tiles and 3N+3 channels.
///
///   tkings --agent request--> tkagnt --model request--> tkmodl#k   (per model)
///                                    <--model result---
///                             tkmodl#k --model audit---> tkaudt    (per model)
///                             tkagnt --agent audit-----> tkaudt
///                             tkagnt --terminal result-> tkdisp
///   metric observes every link.
///
/// Tile order: tkings, tkagnt, tkaudt, tkdisp, tkmodl kind 0..n-1, metric.
/// Per model k the three channels are request, audit, result, in that order.
/// Which tier a tkmodl instance serves is not part of the topology: it is the
/// per-instance configuration, and the agent binds its links from it and from
/// the verified channel endpoints.
///
/// Link bounds are the approved ones (see the plan's "Chosen numeric bounds"):
/// content links carry the multipart MTU at depth 32 fragments; the single-
/// fragment audit and terminal records use their own sizes.
fn AgentGraph(comptime n: usize) type {
    return struct {
        pub const tile_cnt = 5 + n;
        pub const channel_cnt = 3 + 3 * n;
        const wksp = WorkspaceName.parse("tkpay0") catch unreachable;

        fn channel(src: u32, dst: u32, mtu: u32) Channel {
            return .{
                .src_idx = src,
                .dst_idx = dst,
                .depth = audit_mod.TK_MP_LINK_DEPTH,
                .mtu = mtu,
                .backing = .tango_shm,
                .reliability = .reliable,
                .workspace_name = wksp,
            };
        }

        pub const tiles: [tile_cnt]TileDescriptor = blk: {
            var t: [tile_cnt]TileDescriptor = undefined;
            t[0] = .{ .id = 0, .name = tile_ids.tkings };
            t[1] = .{ .id = 1, .name = tile_ids.tkagnt };
            t[2] = .{ .id = 2, .name = tile_ids.tkaudt };
            t[3] = .{ .id = 3, .name = tile_ids.tkdisp };
            for (0..n) |k| t[4 + k] = .{ .id = 4 + k, .name = tile_ids.tkmodl, .kind_id = @intCast(k) };
            t[4 + n] = .{ .id = 4 + n, .name = tile_ids.metric };
            break :blk t;
        };

        pub const channels: [channel_cnt]Channel = blk: {
            const content_mtu: u32 = audit_mod.TK_MP_LINK_MTU;
            const model_audit_mtu: u32 = 256;
            var c: [channel_cnt]Channel = undefined;
            c[0] = channel(0, 1, content_mtu);
            for (0..n) |k| {
                const model: u32 = @intCast(4 + k);
                c[1 + 3 * k + 0] = channel(1, model, content_mtu);
                c[1 + 3 * k + 1] = channel(model, 2, model_audit_mtu);
                c[1 + 3 * k + 2] = channel(model, 1, content_mtu);
            }
            c[1 + 3 * n] = channel(1, 2, audit_mod.TK_AGENT_AUDIT_LINK_MTU);
            c[2 + 3 * n] = channel(1, 3, audit_mod.TK_AGENT_RESULT_LINK_MTU);
            break :blk c;
        };
    };
}

/// Agent process topology with `n` tkmodl instances (see AgentGraph).
pub fn agentProcess(comptime n: usize) Topology {
    comptime std.debug.assert(n >= 1 and n <= rt.model_tier.max_model_instances);
    const G = AgentGraph(n);
    return .{
        .tiles = &G.tiles,
        .channels = &G.channels,
    };
}

/// Minimal 6-tile topology for testing tkpoly in the event pipeline:
/// tkings → tknorm → tkdedu → tkpoly → tkaudt (+ metric observer).
/// The metric tile is required so Firedancer's fd_topo_fill_tile sets
/// tile_c->metrics to a non-NULL value for every tile.
const minimal_with_poly_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkings },
    .{ .id = 1, .name = tile_ids.tknorm },
    .{ .id = 2, .name = tile_ids.tkdedu },
    .{ .id = 3, .name = tile_ids.tkpoly },
    .{ .id = 4, .name = tile_ids.tkaudt },
    .{ .id = 5, .name = tile_ids.metric },
};
const minimal_with_poly_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 3,
        .dst_idx = 4,
        .depth = 64,
        .mtu = 128,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
};

/// Minimal 6-tile topology (tkings → tknorm → tkdedu → tkpoly → tkaudt + metric observer).
pub fn minimalWithPolyProcess() Topology {
    return .{
        .tiles = &minimal_with_poly_tiles,
        .channels = &minimal_with_poly_channels,
    };
}

test "paymentPipeline has Phase 0 product tiles and channels" {
    const topo = paymentPipeline();
    try std.testing.expectEqual(@as(usize, 8), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4), topo.channels.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[4].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkdiag.slice(), topo.tiles[7].name.slice());
    try std.testing.expectEqual(@as(u32, 0), topo.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), topo.channels[0].dst_idx);
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

test "investmentWorkflow is runnable: every link is a reliable shared-memory link in one workspace" {
    try std.testing.expectEqual(TopologyStatus.runnable, investment_workflow_status);
    const topo = investmentWorkflow();
    for (topo.channels) |ch| {
        try std.testing.expectEqual(rt.link.LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqual(rt.link.LinkReliability.reliable, ch.reliability);
        try std.testing.expectEqualStrings("tkinv0", ch.workspace_name.slice());
    }
}

test "investmentWorkflow has no tkaudt -> tkrepl link and keeps the observers unlinked" {
    const topo = investmentWorkflow();
    const audit: u32 = 5;
    const repl: u32 = 11;
    try std.testing.expect(topo.tiles[repl].name.eql(tile_ids.tkrepl));
    for (topo.channels) |ch| {
        try std.testing.expect(ch.src_idx != repl and ch.dst_idx != repl);
        try std.testing.expect(!(ch.src_idx == audit));
    }
    try std.testing.expectEqual(@as(usize, 16), topo.channels.len);
}

test "investmentWorkflow includes tkmodl tktool tkadpt and passes validation" {
    const topo = investmentWorkflow();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 14), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkmodl.slice(), topo.tiles[8].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tktool.slice(), topo.tiles[9].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkadpt.slice(), topo.tiles[10].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkrepl.slice(), topo.tiles[11].name.slice());
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

test "agentProcess has N+5 tiles and 3N+3 channels and passes validation for every supported N" {
    inline for (.{ 1, 2, 3, 5, 11 }) |n| {
        const topo = agentProcess(n);
        try topo.validate();
        try std.testing.expectEqual(@as(usize, n + 5), topo.tiles.len);
        try std.testing.expectEqual(@as(usize, 3 * n + 3), topo.channels.len);
    }
    // The 11-model maximum: 16 tiles, 36 channels (the plan's 15-tile/34-channel
    // base plus the terminal-result consumer and the agent-audit and
    // terminal-result links).
    try std.testing.expectEqual(@as(usize, 16), agentProcess(11).tiles.len);
    try std.testing.expectEqual(@as(usize, 36), agentProcess(11).channels.len);
}

test "agentProcess wires each tkmodl instance to its own request, audit and result links" {
    const topo = agentProcess(3);
    const agent: u32 = 1;
    const audit: u32 = 2;
    const disp: u32 = 3;
    try std.testing.expect(topo.tiles[0].name.eql(tile_ids.tkings));
    try std.testing.expect(topo.tiles[agent].name.eql(tile_ids.tkagnt));
    try std.testing.expect(topo.tiles[audit].name.eql(tile_ids.tkaudt));
    try std.testing.expect(topo.tiles[disp].name.eql(tile_ids.tkdisp));
    try std.testing.expect(topo.tiles[topo.tiles.len - 1].name.eql(tile_ids.metric));

    // tkings feeds the agent.
    try std.testing.expectEqual(@as(u32, 0), topo.channels[0].src_idx);
    try std.testing.expectEqual(agent, topo.channels[0].dst_idx);
    for (0..3) |k| {
        const model: u32 = @intCast(4 + k);
        try std.testing.expect(topo.tiles[model].name.eql(tile_ids.tkmodl));
        try std.testing.expectEqual(@as(u8, @intCast(k)), topo.tiles[model].kind_id);
        const req = topo.channels[1 + 3 * k + 0];
        const aud = topo.channels[1 + 3 * k + 1];
        const res = topo.channels[1 + 3 * k + 2];
        try std.testing.expectEqual(agent, req.src_idx);
        try std.testing.expectEqual(model, req.dst_idx);
        try std.testing.expectEqual(model, aud.src_idx);
        try std.testing.expectEqual(audit, aud.dst_idx);
        try std.testing.expectEqual(model, res.src_idx);
        try std.testing.expectEqual(agent, res.dst_idx);
    }
    // The agent's own audit and terminal-result links.
    try std.testing.expectEqual(agent, topo.channels[10].src_idx);
    try std.testing.expectEqual(audit, topo.channels[10].dst_idx);
    try std.testing.expectEqual(agent, topo.channels[11].src_idx);
    try std.testing.expectEqual(disp, topo.channels[11].dst_idx);
}

test "agentProcess links are reliable shared-memory links sized for their records" {
    const topo = agentProcess(2);
    for (topo.channels) |ch| {
        try std.testing.expectEqual(rt.link.LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqual(rt.link.LinkReliability.reliable, ch.reliability);
        try std.testing.expectEqual(@as(u32, audit_mod.TK_MP_LINK_DEPTH), ch.depth);
    }
    // Content links carry a full multipart fragment; the single-fragment
    // records fit their own links.
    try std.testing.expectEqual(@as(u32, audit_mod.TK_MP_LINK_MTU), topo.channels[0].mtu);
    try std.testing.expect(topo.channels[2].mtu >= @sizeOf(audit_mod.ModelAuditMsg));
    try std.testing.expect(topo.channels[topo.channels.len - 2].mtu >= @sizeOf(audit_mod.TkAgentAuditMsg));
    try std.testing.expect(topo.channels[topo.channels.len - 1].mtu >= @sizeOf(audit_mod.TkAgentResultMsg));
    // And every fragment fits the 16-bit fd size.
    for (topo.channels) |ch| try std.testing.expect(ch.mtu <= audit_mod.TK_MP_FD_SZ_CEILING);
}

test "investmentWorkflow declares the agent's request, result, audit and terminal-result links" {
    const topo = investmentWorkflow();
    try topo.validate();
    const disp: u32 = 6;
    const agent: u32 = 7;
    const model: u32 = 8;
    const audit: u32 = 5;
    try std.testing.expect(topo.tiles[agent].name.eql(tile_ids.tkagnt));
    try std.testing.expect(topo.tiles[model].name.eql(tile_ids.tkmodl));
    try std.testing.expect(topo.tiles[disp].name.eql(tile_ids.tkdisp));

    const Edge = struct { src: u32, dst: u32, mtu: u32 };
    const wanted = [_]Edge{
        .{ .src = disp, .dst = agent, .mtu = audit_mod.TK_MP_LINK_MTU }, // agent request
        .{ .src = agent, .dst = model, .mtu = audit_mod.TK_MP_LINK_MTU }, // model request
        .{ .src = model, .dst = agent, .mtu = audit_mod.TK_MP_LINK_MTU }, // model result
        .{ .src = model, .dst = audit, .mtu = 256 }, // model audit
        .{ .src = agent, .dst = audit, .mtu = audit_mod.TK_AGENT_AUDIT_LINK_MTU }, // agent audit
        .{ .src = agent, .dst = disp, .mtu = audit_mod.TK_AGENT_RESULT_LINK_MTU }, // terminal result
    };
    for (wanted) |w| {
        var found = false;
        for (topo.channels) |ch| {
            if (ch.src_idx == w.src and ch.dst_idx == w.dst and ch.mtu == w.mtu) found = true;
        }
        try std.testing.expect(found);
    }
    // Content links carry a whole multipart fragment and every fragment fits the fd size.
    for (topo.channels) |ch| try std.testing.expect(ch.mtu <= audit_mod.TK_MP_FD_SZ_CEILING);
}
