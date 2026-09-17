/// Integration module creation and test lane strategy.
///
/// Module creation is delegated to the ModuleFactory in factory.zig.
/// This file owns only the integration test registration (strategy).

const std = @import("std");
const factory = @import("../factory.zig");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const shims = @import("../lib/shims.zig");

// Re-export the canonical types so callers can pass them directly.
pub const Shared = @import("../mod/modules.zig").Shared;
pub const Tm = @import("../mod/test_modules.zig").TestModules;

/// Integration modules — the cross-referencing graph passed to strategy().
pub const IntegrationModules = factory.IntegrationModules;

/// Create the cross-referencing module graph for integration tests
/// using the shared ModuleFactory.
pub fn createIntModules(
    b: *std.Build,
    shared: Shared,
    tm: Tm,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    exe: *std.Build.Step.Compile,
) IntegrationModules {
    var m = factory.ModuleFactory.init(b, shared, tm, target, optimize);
    return m.createIntModules(exe);
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

    const imports = b.allocator.alloc(std.Build.Module.Import, 15) catch |err| {
        std.debug.print("error: Failed to allocate imports slice: {any}\n", .{err});
        return;
    };
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
