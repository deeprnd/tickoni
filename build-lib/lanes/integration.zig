/// Integration module creation and test lane strategy.
///
/// Extracts all inline integration module definitions and test registration
/// from build.zig into callable functions.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const shims = @import("../lib/shims.zig");

// Re-export the canonical types so callers can pass them directly.
pub const Shared = @import("../mod/modules.zig").Shared;
pub const Tm = @import("../mod/test_modules.zig").TestModules;

/// Integration modules — the cross-referencing graph passed to strategy().
pub const IntegrationModules = struct {
    tkpoly_int_mod: *std.Build.Module,
    model_int_mod: *std.Build.Module,
    adapter_int_mod: *std.Build.Module,
    tool_int_mod: *std.Build.Module,
    case_int_mod: *std.Build.Module,
    disp_int_mod: *std.Build.Module,
    agent_int_mod: *std.Build.Module,
    replay_int_mod: *std.Build.Module,
    investment_audit_int_mod: *std.Build.Module,
    investment_support_int_mod: *std.Build.Module,
    investment_demo_test_mod: *std.Build.Module,
    investment_demo_mod: *std.Build.Module,
    supervisor_named_mod: *std.Build.Module,
    mock_http_support_mod: *std.Build.Module,
    mock_broker_market_server_mod: *std.Build.Module,
    mock_openai_server_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    shared_audit_tile: *std.Build.Module,
    shared_basket: *std.Build.Module,
    shared_portfolio: *std.Build.Module,
    shared_thesis: *std.Build.Module,
    shared_trade_ticket: *std.Build.Module,
    shared_runtime: *std.Build.Module,
    shared_c_abi: *std.Build.Module,
    shared_util: *std.Build.Module,
    shared_topologies: *std.Build.Module,
};

/// Create the cross-referencing module graph for integration tests.
pub fn createIntModules(
    b: *std.Build,
    shared: Shared,
    tm: Tm,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe: *std.Build.Step.Compile,
) IntegrationModules {
    const tkpoly_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "runtime", .module = shared.runtime },
        },
    });

    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = tm.model_messages },
            .{ .name = "mock_model", .module = tm.mock_model },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "adapter_messages", .module = tm.adapter_messages },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const case_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const disp_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const agent_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "mock_adapter", .module = tm.mock_adapter },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "capability", .module = shared.capability },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "mock_model", .module = tm.mock_model },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = shared.audit_tile },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const investment_demo_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "cards", .module = tm.cards },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "impact", .module = tm.impact },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "cards", .module = tm.cards },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "impact", .module = tm.impact },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const mock_http_support_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_http_support.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mock_broker_market_server_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mock_http_support", .module = mock_http_support_mod },
        },
    });

    const mock_openai_server_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mock_http_support", .module = mock_http_support_mod },
        },
    });

    const supervisor_named_mod = b.addModule("supervisor", .{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "logger", .module = shared.logger },
        },
    });

    return IntegrationModules{
        .tkpoly_int_mod = tkpoly_int_mod,
        .model_int_mod = model_int_mod,
        .adapter_int_mod = adapter_int_mod,
        .tool_int_mod = tool_int_mod,
        .case_int_mod = case_int_mod,
        .disp_int_mod = disp_int_mod,
        .agent_int_mod = agent_int_mod,
        .replay_int_mod = replay_int_mod,
        .investment_audit_int_mod = investment_audit_int_mod,
        .investment_support_int_mod = investment_support_int_mod,
        .investment_demo_test_mod = investment_demo_test_mod,
        .investment_demo_mod = investment_demo_mod,
        .supervisor_named_mod = supervisor_named_mod,
        .mock_http_support_mod = mock_http_support_mod,
        .mock_broker_market_server_mod = mock_broker_market_server_mod,
        .mock_openai_server_mod = mock_openai_server_mod,
        .exe = exe,
        .shared_audit_tile = shared.audit_tile,
        .shared_basket = shared.basket,
        .shared_portfolio = shared.portfolio,
        .shared_thesis = shared.thesis,
        .shared_trade_ticket = tm.trade_ticket,
        .shared_runtime = shared.runtime,
        .shared_c_abi = shared.c_abi,
        .shared_util = shared.util,
        .shared_topologies = shared.topologies,
    };
}

/// Register all integration test binaries.
pub fn strategy(
    b: *std.Build,
    int_mods: IntegrationModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    integration_step: *std.Build.Step,
) void {
    const investment_demo_test_mod = int_mods.investment_demo_test_mod;
    const investment_demo_test = b.addTest(.{ .root_module = investment_demo_test_mod });
    codec.linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
    integration_step.dependOn(&b.addRunArtifact(investment_demo_test).step);

    const static_tests: []const []const u8 = &.{
        "src/tickoni/test/integration/test_investment_allowed_trade.zig",
        "src/tickoni/test/integration/test_investment_blocked_limits.zig",
        "src/tickoni/test/integration/test_investment_restricted_instrument.zig",
        "src/tickoni/test/integration/test_investment_input_policy_denials.zig",
    };

    const imports = b.allocator.alloc(std.Build.Module.Import, 15) catch unreachable;
    defer b.allocator.free(imports);

    imports[0] = .{ .name = "adapter", .module = int_mods.adapter_int_mod };
    imports[1] = .{ .name = "audit_tile", .module = int_mods.shared_audit_tile };
    imports[2] = .{ .name = "basket", .module = int_mods.shared_basket };
    imports[3] = .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod };
    imports[4] = .{ .name = "investment_support", .module = int_mods.investment_support_int_mod };
    imports[5] = .{ .name = "model", .module = int_mods.model_int_mod };
    imports[6] = .{ .name = "portfolio", .module = int_mods.shared_portfolio };
    imports[7] = .{ .name = "replay", .module = int_mods.replay_int_mod };
    imports[8] = .{ .name = "thesis", .module = int_mods.shared_thesis };
    imports[9] = .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod };
    imports[10] = .{ .name = "tool", .module = int_mods.tool_int_mod };
    imports[11] = .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket };
    imports[12] = .{ .name = "tkcase", .module = int_mods.case_int_mod };
    imports[13] = .{ .name = "tkdisp", .module = int_mods.disp_int_mod };
    imports[14] = .{ .name = "tkagnt", .module = int_mods.agent_int_mod };

    inline for (static_tests) |path| {
        const integration_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = imports,
            }),
        });
        codec.linkTickoniCodec(b, integration_test, fd_lib_dir);
        integration_step.dependOn(&b.addRunArtifact(integration_test).step);
    }

    if (target.result.os.tag == .linux) {
        const process_mode_exe_install = b.addInstallArtifact(int_mods.exe, .{});

        const process_tests: []const []const u8 = &.{
            "src/tickoni/test/integration/test_process_pipeline.zig",
            "src/tickoni/test/integration/test_process_cpu_placement.zig",
            "src/tickoni/test/integration/test_process_cpu_placement_linux.zig",
            "src/tickoni/test/integration/test_process_topology.zig",
            "src/tickoni/test/integration/test_process_topology_linux.zig",
            "src/tickoni/test/integration/test_process_demo_parity.zig",
        };

        const proc_imports = [_]std.Build.Module.Import{
            .{ .name = "runtime", .module = int_mods.shared_runtime },
            .{ .name = "c_abi", .module = int_mods.shared_c_abi },
            .{ .name = "util", .module = int_mods.shared_util },
            .{ .name = "supervisor", .module = int_mods.supervisor_named_mod },
            .{ .name = "topologies", .module = int_mods.shared_topologies },
        };

        inline for (process_tests) |path| {
            const process_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &proc_imports,
                }),
            });
            codec.linkTickoniCodec(b, process_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_test, fd_lib_dir);
            const run_proc_test = shims.addPlainTestRun(b, process_test);
            run_proc_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_proc_test.step);
        }
    }

    const mock_servers_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_servers.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = int_mods.mock_http_support_mod },
                .{ .name = "mock_broker_market_server", .module = int_mods.mock_broker_market_server_mod },
                .{ .name = "mock_openai_server", .module = int_mods.mock_openai_server_mod },
            },
        }),
    });
    integration_step.dependOn(&mock_servers_test.step);

    const model_tile_http_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_model_tile_http.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model", .module = int_mods.model_int_mod },
                .{ .name = "mock_http_support", .module = int_mods.mock_http_support_mod },
                .{ .name = "mock_openai_server", .module = int_mods.mock_openai_server_mod },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(model_tile_http_test).step);

    const replay_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_replay.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = int_mods.adapter_int_mod },
                .{ .name = "audit_tile", .module = int_mods.shared_audit_tile },
                .{ .name = "basket", .module = int_mods.shared_basket },
                .{ .name = "investment_demo", .module = int_mods.investment_demo_mod },
                .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod },
                .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                .{ .name = "model", .module = int_mods.model_int_mod },
                .{ .name = "portfolio", .module = int_mods.shared_portfolio },
                .{ .name = "replay", .module = int_mods.replay_int_mod },
                .{ .name = "thesis", .module = int_mods.shared_thesis },
                .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
                .{ .name = "tool", .module = int_mods.tool_int_mod },
                .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket },
                .{ .name = "tkcase", .module = int_mods.case_int_mod },
                .{ .name = "tkdisp", .module = int_mods.disp_int_mod },
                .{ .name = "tkagnt", .module = int_mods.agent_int_mod },
            },
        }),
    });
    codec.linkTickoniCodec(b, replay_integration_test, fd_lib_dir);
    integration_step.dependOn(&b.addRunArtifact(replay_integration_test).step);

    const decision_cards_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_decision_cards.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = int_mods.investment_demo_mod },
                .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
            },
        }),
    });
    codec.linkTickoniCodec(b, decision_cards_integration_test, fd_lib_dir);
    integration_step.dependOn(&b.addRunArtifact(decision_cards_integration_test).step);
}
