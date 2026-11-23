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

/// Shape of every diagnostic link into tkdiag, taken from the one definition in
/// shim/tk_diag_fragment.h (the MTU is the fragment size).
pub const diag_link_depth: u32 = audit_mod.TK_DIAG_LINK_DEPTH;
pub const diag_link_mtu: u32 = audit_mod.TK_DIAG_LINK_MTU;

/// MTU of every spine link: one TkEvent per fragment (shim/tk_event_wire.h).
pub const event_link_mtu: u32 = audit_mod.TK_EVENT_LINK_MTU;

/// tkings's input in the isolation fixtures, which have no tkapi: the one link
/// no tile produces (`rt.link.external_src`, Firedancer's permit_no_producers),
/// on which the integration test harness publishes TkEvents directly. In the
/// product topologies tkings's input is tkapi's output (`apiOutput`).
fn ingestInput(workspace: []const u8) Channel {
    return .{
        .src_idx = rt.link.external_src,
        .dst_idx = 0,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse(workspace) catch unreachable,
    };
}

/// tkapi's input: the link from the terminal tile (the Qt CaseOps desktop
/// application). No tile produces it yet (`rt.link.external_src`, Firedancer's
/// permit_no_producers): the integration test harness stands in for the
/// terminal tile until it exists.
fn apiInput(api_idx: u32, workspace: []const u8) Channel {
    return .{
        .src_idx = rt.link.external_src,
        .dst_idx = api_idx,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse(workspace) catch unreachable,
    };
}

/// tkapi -> tkings: tkings's only input wherever the topology has tkapi. A
/// reliable link, like every link between tiles: tkapi waits on tkings's
/// credits and never drops.
fn apiOutput(api_idx: u32, ings_idx: u32, workspace: []const u8) Channel {
    return .{
        .src_idx = api_idx,
        .dst_idx = ings_idx,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse(workspace) catch unreachable,
    };
}

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
    .{ .id = 8, .name = tile_ids.tkapi },
};
/// Index of tkapi in `payment_tiles`.
const payment_api_idx: u32 = 8;
const payment_channels = [_]Channel{
    .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = event_link_mtu },
    .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = event_link_mtu },
    .{ .src_idx = 2, .dst_idx = 3, .depth = 64, .mtu = event_link_mtu },
    .{ .src_idx = 3, .dst_idx = 4, .depth = 64, .mtu = event_link_mtu },
    apiOutput(payment_api_idx, 0, "tkpay0"),
    apiInput(payment_api_idx, "tkpay0"),
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
    .{ .id = 14, .name = tile_ids.tkapi },
};
/// Index of tkapi in `investment_tiles`.
const investment_api_idx: u32 = 14;

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
    investmentLink(0, 1, 64, event_link_mtu),
    investmentLink(1, 2, 64, event_link_mtu),
    investmentLink(2, 3, 64, event_link_mtu),
    // tkcase -> tkpoly (the policy path) and tkcase -> tkdisp (the dispatch path).
    investmentLink(3, 4, 64, event_link_mtu),
    investmentLink(3, 6, 64, event_link_mtu),
    // tkdisp -> tkagnt carries agent requests: one fixed record each.
    investmentLink(6, 7, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_AGENT_REQUEST_LINK_MTU),
    // tkagnt -> tkmodl carries model requests: a multipart content link.
    investmentLink(7, 8, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_MP_LINK_MTU),
    // tkagnt -> tktool -> tkadpt: the tool and adapter paths. No tool call exists
    // yet, so these links are declared and bound and carry nothing.
    investmentLink(7, 9, 32, 512),
    investmentLink(9, 10, 32, 512),
    // Every audit producer feeds tkaudt. tktool and tkadpt have no audit record
    // type yet, so their links are idle.
    investmentLink(4, 5, 64, event_link_mtu),
    investmentLink(8, 5, 32, 256),
    investmentLink(9, 5, 32, 256),
    investmentLink(10, 5, 32, 256),
    // tkagnt -> tkaudt: the agent's audit record (proposal or denial).
    investmentLink(7, 5, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_AGENT_AUDIT_LINK_MTU),
    // The agent's return paths: the model's result back to tkagnt (a multipart
    // content link), and tkagnt's terminal result to tkdisp.
    investmentLink(8, 7, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_MP_LINK_MTU),
    investmentLink(7, 6, audit_mod.TK_MP_LINK_DEPTH, audit_mod.TK_AGENT_RESULT_LINK_MTU),
    apiOutput(investment_api_idx, 0, "tkinv0"),
    apiInput(investment_api_idx, "tkinv0"),
};

/// Phase 0 in-process pipeline used by the Tickoni product supervisor.
///
///   (terminal tile) -> tkapi -> tkings -> tknorm -> tkdedu -> tkpoly -> tkaudt
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

/// The full investment workflow: all 15 tiles, one process each, on reliable
/// shared-memory links.
///
///   events:    (terminal tile) -> tkapi -> tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt
///   dispatch:  tkcase -> tkdisp -> tkagnt (agent request)
///   model:     tkagnt -> tkmodl -> tkagnt (request, result); tkmodl -> tkaudt (audit)
///   agent:     tkagnt -> tkaudt (audit), tkagnt -> tkdisp (terminal result)
///   idle:      tkagnt -> tktool -> tkadpt, and tktool, tkadpt -> tkaudt
///   tkrepl, metric and tkdiag observe the run.
///
/// tkcase, tktool and tkadpt are config-driven placeholders: they carry no case,
/// tool or adapter logic. tkdisp is the scheduler that turns each event it
/// receives from tkcase into one agent request: an agent-request event's own,
/// or, for a payment event, a fixed, config-supplied template. `tkaudt -> tkrepl` is not a link: replay reads the committed audit
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

// v2.14.S1 process-mode variant of paymentPipeline: same 9 tiles and 4
// core channels, backed by Tango shared memory in one shared workspace
// instead of the heap-backed dev/test ring, plus the 5 lossy diagnostic
// channels of the tkdiag fan-in. All tiles are floating (no
// hard exclusive-core requirement); src/app/tickoni/supervisor.zig's
// process-mode start path assigns concrete CPU placement per config.
const payment_process_channels = [_]Channel{
    .{
        .src_idx = 0,
        .dst_idx = 1,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 3,
        .dst_idx = 4,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    // Diagnostic fan-in (plans/v2.10-s14-tkdiag-fan-in.md): one link from each
    // pipeline tile to tkdiag (tile 7), after the pipeline links so that each
    // producer's diagnostic link is its last output. They are lossy: the
    // producer never waits on tkdiag, which keeps the latest fragment per tile.
    diagLink(0),
    diagLink(1),
    diagLink(2),
    diagLink(3),
    diagLink(4),
    // tkapi -> tkings, and tkapi's input from the terminal tile (no tile's
    // output yet), after the diagnostic links.
    apiOutput(payment_api_idx, 0, "tkpay0"),
    apiInput(payment_api_idx, "tkpay0"),
};

/// The lossy diagnostic link from pipeline tile `src` to tkdiag
/// (`payment_tiles[7]`).
fn diagLink(src: u32) Channel {
    return .{
        .src_idx = src,
        .dst_idx = 7,
        .depth = diag_link_depth,
        .mtu = diag_link_mtu,
        .backing = .tango_shm,
        .reliability = .lossy,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    };
}

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
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    ingestInput("tkpay0"),
};

/// Minimal 3-tile topology (tkings → tkaudt + metric observer tile).
pub fn minimalProcess() Topology {
    return .{
        .tiles = &minimal_tiles,
        .channels = &minimal_channels,
    };
}

/// Minimal 4-tile topology for testing tkapi in front of the event pipeline:
/// (terminal tile) -> tkapi -> tkings -> tkaudt (+ metric observer). The test
/// harness stands in for the terminal tile on tkapi's input.
const minimal_with_api_tiles = [_]TileDescriptor{
    .{ .id = 0, .name = tile_ids.tkapi },
    .{ .id = 1, .name = tile_ids.tkings },
    .{ .id = 2, .name = tile_ids.tkaudt },
    .{ .id = 3, .name = tile_ids.metric },
};
const minimal_with_api_channels = [_]Channel{
    apiOutput(0, 1, "tkpay0"),
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    apiInput(0, "tkpay0"),
};

/// Minimal 4-tile topology (tkapi -> tkings -> tkaudt + metric observer).
pub fn minimalWithApiProcess() Topology {
    return .{
        .tiles = &minimal_with_api_tiles,
        .channels = &minimal_with_api_channels,
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
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    ingestInput("tkpay0"),
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
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    ingestInput("tkpay0"),
};

/// Minimal 5-tile topology (tkings → tknorm → tkdedu → tkaudt + metric observer).
pub fn minimalWithDeduProcess() Topology {
    return .{
        .tiles = &minimal_with_dedu_tiles,
        .channels = &minimal_with_dedu_channels,
    };
}

/// The agent process graph for `n` configured tkmodl instances (1..11): every
/// event takes the spine, and agent requests reach tkagnt only through tkdisp
/// (plan v2.NN rev 2, D2). N+10 tiles and 3N+11 channels.
///
///   (terminal tile) -> tkapi -> tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt
///                                              tkcase -> tkdisp -> tkagnt
///   tkagnt --model request--> tkmodl#k --model result--> tkagnt    (per model)
///                             tkmodl#k --model audit---> tkaudt    (per model)
///   tkagnt --agent audit-----> tkaudt
///   tkagnt --terminal result-> tkdisp
///   metric observes every link.
///
/// Tile order: tkings, tknorm, tkdedu, tkcase, tkpoly, tkaudt, tkdisp, tkagnt,
/// tkmodl kind 0..n-1, metric, tkapi. Channels: the six spine links, tkdisp ->
/// tkagnt, then per model k request, audit, result in that order, then the
/// agent's audit and terminal-result links, then tkapi -> tkings, and last
/// tkapi's externally produced input (`rt.link.external_src`): the test
/// harness publishes TkEvents on it, standing in for the terminal tile.
/// Which tier a tkmodl instance serves is not part of the topology: it is the
/// per-instance configuration, and the agent binds its links from it and from
/// the verified channel endpoints.
///
/// Link bounds are the approved ones (see the tkagnt plan's "Chosen numeric
/// bounds"): model content links carry the multipart MTU at depth 32
/// fragments; the spine links carry one TkEvent and the single-fragment
/// request, audit and terminal records use their own sizes.
fn AgentGraph(comptime n: usize) type {
    return struct {
        pub const idx_ings = 0;
        pub const idx_case = 3;
        pub const idx_poly = 4;
        pub const idx_audit = 5;
        pub const idx_disp = 6;
        pub const idx_agent = 7;
        pub const first_model_idx = 8;
        pub const idx_metric = first_model_idx + n;
        pub const idx_api = idx_metric + 1;
        pub const tile_cnt = 10 + n;
        pub const channel_cnt = 11 + 3 * n;
        /// Index of the tkapi -> tkings channel.
        pub const api_output_idx = channel_cnt - 2;
        /// Index of tkapi's externally produced input channel.
        pub const api_input_idx = channel_cnt - 1;
        const wksp = WorkspaceName.parse("tkpay0") catch unreachable;

        fn channel(src: u32, dst: u32, depth: u32, mtu: u32) Channel {
            return .{
                .src_idx = src,
                .dst_idx = dst,
                .depth = depth,
                .mtu = mtu,
                .backing = .tango_shm,
                .reliability = .reliable,
                .workspace_name = wksp,
            };
        }

        pub const tiles: [tile_cnt]TileDescriptor = blk: {
            var t: [tile_cnt]TileDescriptor = undefined;
            t[0] = .{ .id = 0, .name = tile_ids.tkings };
            t[1] = .{ .id = 1, .name = tile_ids.tknorm };
            t[2] = .{ .id = 2, .name = tile_ids.tkdedu };
            t[3] = .{ .id = 3, .name = tile_ids.tkcase };
            t[4] = .{ .id = 4, .name = tile_ids.tkpoly };
            t[5] = .{ .id = 5, .name = tile_ids.tkaudt };
            t[6] = .{ .id = 6, .name = tile_ids.tkdisp };
            t[7] = .{ .id = 7, .name = tile_ids.tkagnt };
            for (0..n) |k| t[first_model_idx + k] = .{ .id = first_model_idx + k, .name = tile_ids.tkmodl, .kind_id = @intCast(k) };
            t[idx_metric] = .{ .id = idx_metric, .name = tile_ids.metric };
            t[idx_api] = .{ .id = idx_api, .name = tile_ids.tkapi };
            break :blk t;
        };

        pub const channels: [channel_cnt]Channel = blk: {
            const depth: u32 = audit_mod.TK_MP_LINK_DEPTH;
            const content_mtu: u32 = audit_mod.TK_MP_LINK_MTU;
            const model_audit_mtu: u32 = 256;
            var c: [channel_cnt]Channel = undefined;
            c[0] = channel(0, 1, 64, event_link_mtu);
            c[1] = channel(1, 2, 64, event_link_mtu);
            c[2] = channel(2, idx_case, 64, event_link_mtu);
            c[3] = channel(idx_case, idx_poly, 64, event_link_mtu);
            c[4] = channel(idx_case, idx_disp, 64, event_link_mtu);
            c[5] = channel(idx_poly, idx_audit, 64, event_link_mtu);
            c[6] = channel(idx_disp, idx_agent, depth, audit_mod.TK_AGENT_REQUEST_LINK_MTU);
            for (0..n) |k| {
                const model: u32 = @intCast(first_model_idx + k);
                c[7 + 3 * k + 0] = channel(idx_agent, model, depth, content_mtu);
                c[7 + 3 * k + 1] = channel(model, idx_audit, depth, model_audit_mtu);
                c[7 + 3 * k + 2] = channel(model, idx_agent, depth, content_mtu);
            }
            c[7 + 3 * n] = channel(idx_agent, idx_audit, depth, audit_mod.TK_AGENT_AUDIT_LINK_MTU);
            c[8 + 3 * n] = channel(idx_agent, idx_disp, depth, audit_mod.TK_AGENT_RESULT_LINK_MTU);
            c[api_output_idx] = channel(idx_api, idx_ings, 64, event_link_mtu);
            c[api_input_idx] = channel(rt.link.external_src, idx_api, 64, event_link_mtu);
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
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 1,
        .dst_idx = 2,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 2,
        .dst_idx = 3,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    .{
        .src_idx = 3,
        .dst_idx = 4,
        .depth = 64,
        .mtu = event_link_mtu,
        .backing = .tango_shm,
        .reliability = .reliable,
        .workspace_name = WorkspaceName.parse("tkpay0") catch unreachable,
    },
    ingestInput("tkpay0"),
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
    try std.testing.expectEqual(@as(usize, 9), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 6), topo.channels.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), topo.tiles[0].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkaudt.slice(), topo.tiles[4].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkdiag.slice(), topo.tiles[7].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkapi.slice(), topo.tiles[8].name.slice());
    try std.testing.expectEqual(@as(u32, 0), topo.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), topo.channels[0].dst_idx);
}

test "paymentPipeline passes validation" {
    try paymentPipeline().validate();
}

test "runnable topologies have the 9-tile shape Supervisor's start paths assert" {
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_status);
    try std.testing.expectEqual(TopologyStatus.runnable, payment_pipeline_process_status);
    try std.testing.expectEqual(@as(usize, 9), paymentPipeline().tiles.len);
    try std.testing.expectEqual(@as(usize, 9), paymentPipelineProcess().tiles.len);
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
    try std.testing.expectEqual(@as(usize, 18), topo.channels.len);
}

test "investmentWorkflow includes tkmodl tktool tkadpt and passes validation" {
    const topo = investmentWorkflow();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 15), topo.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkmodl.slice(), topo.tiles[8].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tktool.slice(), topo.tiles[9].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkadpt.slice(), topo.tiles[10].name.slice());
    try std.testing.expectEqualStrings(tile_ids.tkrepl.slice(), topo.tiles[11].name.slice());
}

test "paymentPipelineProcess has 9 tiles, 4 reliable pipeline channels, 5 lossy diagnostic channels and tkapi's two links, and passes validation" {
    const topo = paymentPipelineProcess();
    try topo.validate();
    try std.testing.expectEqual(@as(usize, 9), topo.tiles.len);
    try std.testing.expectEqual(@as(usize, 4 + 5 + 2), topo.channels.len);
    for (topo.channels, 0..) |ch, i| {
        try std.testing.expectEqual(rt.link.LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqualStrings("tkpay0", ch.workspace_name.slice());
        // The pipeline and tkapi's links are reliable; the diagnostic links never are.
        const expected: rt.link.LinkReliability = if (i < 4 or i >= 9) .reliable else .lossy;
        try std.testing.expectEqual(expected, ch.reliability);
    }
}

test "paymentPipelineProcess fans one diagnostic link per pipeline tile in to tkdiag, after the pipeline links" {
    const topo = paymentPipelineProcess();
    const diag: u32 = 7;
    try std.testing.expect(topo.tiles[diag].name.eql(tile_ids.tkdiag));
    // Producers in pipeline order: tkings, tknorm, tkdedu, tkpoly, tkaudt.
    const producers = [_]*const rt.tile.TileId{ &tile_ids.tkings, &tile_ids.tknorm, &tile_ids.tkdedu, &tile_ids.tkpoly, &tile_ids.tkaudt };
    for (producers, 0..) |name, i| {
        const ch = topo.channels[4 + i];
        try std.testing.expectEqual(@as(u32, @intCast(i)), ch.src_idx);
        try std.testing.expect(topo.tiles[ch.src_idx].name.eql(name.*));
        try std.testing.expectEqual(diag, ch.dst_idx);
        try std.testing.expectEqual(@as(u32, diag_link_depth), ch.depth);
        try std.testing.expectEqual(@as(u32, diag_link_mtu), ch.mtu);
        try std.testing.expect(std.math.isPowerOfTwo(ch.depth));
    }
    // Nothing else goes to or from tkdiag.
    for (topo.channels) |ch| {
        try std.testing.expect(ch.src_idx != diag);
        if (ch.dst_idx == diag) try std.testing.expect(ch.src_idx <= 4);
    }
}

test "the diagnostic link MTU is the diagnostic fragment size" {
    try std.testing.expectEqual(@as(u32, @sizeOf(audit_mod.diag_fragment_t)), diag_link_mtu);
}

test "only the 9-tile payment process topology carries diagnostic links" {
    // The in-process dev ring, the minimal topologies and the full workflow
    // keep their pipeline-only shape: the diag links are specified for the
    // 5-producer payment topology alone.
    const others = [_]Topology{ paymentPipeline(), minimalProcess(), minimalWithApiProcess(), minimalWithNormProcess(), minimalWithDeduProcess(), minimalWithPolyProcess(), investmentWorkflow() };
    for (others) |topo| {
        for (topo.tiles, 0..) |t, i| {
            if (!t.name.eql(tile_ids.tkdiag)) continue;
            for (topo.channels) |ch| try std.testing.expect(ch.dst_idx != i and ch.src_idx != i);
        }
    }
}

test "agentProcess has N+10 tiles and 3N+11 channels and passes validation for every supported N" {
    inline for (.{ 1, 2, 3, 5, 11 }) |n| {
        const topo = agentProcess(n);
        try topo.validate();
        try std.testing.expectEqual(@as(usize, n + 10), topo.tiles.len);
        try std.testing.expectEqual(@as(usize, 3 * n + 11), topo.channels.len);
    }
    // The 11-model maximum: 21 tiles, 44 channels.
    try std.testing.expectEqual(@as(usize, 21), agentProcess(11).tiles.len);
    try std.testing.expectEqual(@as(usize, 44), agentProcess(11).channels.len);
}

test "agentProcess routes every event through the spine and agent requests only through tkdisp" {
    const G = AgentGraph(3);
    const topo = agentProcess(3);
    const names = [_]rt.tile.TileId{ tile_ids.tkings, tile_ids.tknorm, tile_ids.tkdedu, tile_ids.tkcase, tile_ids.tkpoly, tile_ids.tkaudt, tile_ids.tkdisp, tile_ids.tkagnt };
    for (names, 0..) |name, i| try std.testing.expect(topo.tiles[i].name.eql(name));
    try std.testing.expect(topo.tiles[G.idx_metric].name.eql(tile_ids.metric));
    try std.testing.expect(topo.tiles[G.idx_api].name.eql(tile_ids.tkapi));

    // No link from tkings goes anywhere but tknorm, and tkagnt's only request
    // input is tkdisp's.
    for (topo.channels) |ch| {
        if (ch.src_idx == G.idx_ings) try std.testing.expectEqual(@as(u32, 1), ch.dst_idx);
        if (ch.dst_idx == G.idx_agent and ch.src_idx < G.first_model_idx) try std.testing.expectEqual(@as(u32, G.idx_disp), ch.src_idx);
    }
    for (0..3) |k| {
        const model: u32 = @intCast(G.first_model_idx + k);
        try std.testing.expect(topo.tiles[model].name.eql(tile_ids.tkmodl));
        try std.testing.expectEqual(@as(u8, @intCast(k)), topo.tiles[model].kind_id);
        const req = topo.channels[7 + 3 * k + 0];
        const aud = topo.channels[7 + 3 * k + 1];
        const res = topo.channels[7 + 3 * k + 2];
        try std.testing.expectEqual(@as(u32, G.idx_agent), req.src_idx);
        try std.testing.expectEqual(model, req.dst_idx);
        try std.testing.expectEqual(model, aud.src_idx);
        try std.testing.expectEqual(@as(u32, G.idx_audit), aud.dst_idx);
        try std.testing.expectEqual(model, res.src_idx);
        try std.testing.expectEqual(@as(u32, G.idx_agent), res.dst_idx);
    }
    // tkings's only input is tkapi's output, and tkapi's input has no producer
    // tile: the harness feeds it, standing in for the terminal tile.
    try std.testing.expectEqual(@as(u32, G.idx_api), topo.channels[G.api_output_idx].src_idx);
    try std.testing.expectEqual(@as(u32, G.idx_ings), topo.channels[G.api_output_idx].dst_idx);
    try std.testing.expect(!topo.channels[G.api_input_idx].hasProducerTile());
    try std.testing.expectEqual(@as(u32, G.idx_api), topo.channels[G.api_input_idx].dst_idx);
}

test "agentProcess links are reliable shared-memory links sized for their records" {
    const topo = agentProcess(2);
    for (topo.channels) |ch| {
        try std.testing.expectEqual(rt.link.LinkBacking.tango_shm, ch.backing);
        try std.testing.expectEqual(rt.link.LinkReliability.reliable, ch.reliability);
        try std.testing.expect(std.math.isPowerOfTwo(ch.depth));
        try std.testing.expect(ch.mtu <= audit_mod.TK_MP_FD_SZ_CEILING);
    }
    for (topo.channels[0..6]) |ch| try std.testing.expect(ch.mtu >= @sizeOf(audit_mod.TkEvent));
    try std.testing.expect(topo.channels[6].mtu >= @sizeOf(audit_mod.TkAgentRequestMsg));
    try std.testing.expectEqual(@as(u32, audit_mod.TK_MP_LINK_MTU), topo.channels[7].mtu);
    try std.testing.expect(topo.channels[8].mtu >= @sizeOf(audit_mod.ModelAuditMsg));
    try std.testing.expect(topo.channels[topo.channels.len - 4].mtu >= @sizeOf(audit_mod.TkAgentAuditMsg));
    try std.testing.expect(topo.channels[topo.channels.len - 3].mtu >= @sizeOf(audit_mod.TkAgentResultMsg));
    try std.testing.expect(topo.channels[topo.channels.len - 2].mtu >= @sizeOf(audit_mod.TkEvent));
    try std.testing.expect(topo.channels[topo.channels.len - 1].mtu >= @sizeOf(audit_mod.TkEvent));
}

test "every product topology feeds tkapi from outside the tile graph, and tkapi alone feeds tkings" {
    const product = [_]Topology{ paymentPipeline(), paymentPipelineProcess(), minimalWithApiProcess(), investmentWorkflow(), agentProcess(1) };
    for (product) |topo| {
        var external: usize = 0;
        var into_ings: usize = 0;
        for (topo.channels) |ch| {
            if (topo.tiles[ch.dst_idx].name.eql(tile_ids.tkings)) {
                into_ings += 1;
                try std.testing.expect(ch.hasProducerTile());
                try std.testing.expect(topo.tiles[ch.src_idx].name.eql(tile_ids.tkapi));
                try std.testing.expectEqual(rt.link.LinkReliability.reliable, ch.reliability);
            }
            if (ch.hasProducerTile()) continue;
            external += 1;
            try std.testing.expect(topo.tiles[ch.dst_idx].name.eql(tile_ids.tkapi));
            try std.testing.expect(ch.mtu >= @sizeOf(audit_mod.TkEvent));
        }
        try std.testing.expectEqual(@as(usize, 1), external);
        try std.testing.expectEqual(@as(usize, 1), into_ings);
    }
}

test "the isolation fixtures without tkapi feed tkings from outside the tile graph, and only tkings" {
    const fixtures = [_]Topology{ minimalProcess(), minimalWithNormProcess(), minimalWithDeduProcess(), minimalWithPolyProcess() };
    for (fixtures) |topo| {
        var external: usize = 0;
        for (topo.channels) |ch| {
            if (ch.hasProducerTile()) continue;
            external += 1;
            try std.testing.expect(topo.tiles[ch.dst_idx].name.eql(tile_ids.tkings));
        }
        try std.testing.expectEqual(@as(usize, 1), external);
    }
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
        .{ .src = disp, .dst = agent, .mtu = audit_mod.TK_AGENT_REQUEST_LINK_MTU }, // agent request
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
