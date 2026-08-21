/// Integration test specs for the Tickoni build system.
///
/// Lists integration test binaries with their module imports and linkage flags.
/// Mirrors the inline integration test definitions from the original build.zig.

const std = @import("std");
const Registry = @import("registry.zig");
const helpers = @import("helpers.zig");

/// ModuleImport is a reference to a module by name for integration test imports.
pub const ModuleImport = struct {
    name: []const u8,
    module: *std.Build.Module,
};

/// Register integration test lanes using module references.
/// This function creates test binaries from the module references provided
/// by the caller and adds them to the integration test step.
pub fn registerIntegrationSpecs(
    b: *std.Build,
    modules: @import("../mod.zig").Modules,
    test_modules: @import("../mod.zig").TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    integration_step: *std.Build.Step,
    lib_dir: []const u8,
    shim_archives: []const *std.Build.Step.Compile,
) void {

    // Create test-integration modules that are specific to integration tests.
    // These are different from the test-unit modules and are created inline here.

    // Model integration module (test)
    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = test_modules.model_messages },
            .{ .name = "mock_model", .module = test_modules.mock_model },
            .{ .name = "c_abi", .module = modules.c_abi },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            .{ .name = "thesis", .module = modules.thesis },
        },
    });

    // TKpolicy integration module (test) - must come before replay_int_mod
    const tkpoly_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "capability", .module = modules.capability },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Adapter integration module (test) — must come before replay/tool/integration modules
    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter_messages", .module = test_modules.adapter_messages },
            .{ .name = "mock_adapter", .module = test_modules.mock_adapter },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "fixture_portfolio", .module = modules.fixture_portfolio },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "thesis", .module = modules.thesis },
        },
    });

    // Tool integration module (test)
    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            .{ .name = "thesis", .module = modules.thesis },
        },
    });

    // Replay integration module (test) - must come before investment_demo_mod
    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "c_abi", .module = modules.c_abi },
            .{ .name = "drift", .module = modules.drift },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Investment support integration module (test) - must come before investment_demo_mod
    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Investment demo module
    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "cards", .module = modules.cards },
            .{ .name = "drift", .module = modules.drift },
            .{ .name = "impact", .module = modules.impact },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Investment audit integration module (test)
    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Case integration module (test)
    const case_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = modules.runtime },
            .{ .name = "audit_schema", .module = modules.audit_schema },
        },
    });

    // Disp integration module (test)
    const disp_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = modules.runtime },
            .{ .name = "case", .module = case_int_mod },
        },
    });

    // Agent integration module (test)
    const agent_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "capability", .module = modules.capability },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "case", .module = case_int_mod },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
        },
    });

    // Mock HTTP support module (already in test_modules, but referenced here for clarity)
    const mock_http_support_mod = test_modules.mock_http_support;
    const mock_broker_market_server_mod = test_modules.mock_broker_market_server;
    const mock_openai_server_mod = test_modules.mock_openai_server;

    // Test 1: model_tile_http_test
    const model_tile_http_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_model_tile_http.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
                .{ .name = "mock_openai_server", .module = mock_openai_server_mod },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(model_tile_http_test).step);

    // Test 2: replay_integration_test
    const replay_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_replay.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "audit_tile", .module = modules.tiles },
                .{ .name = "basket", .module = modules.basket },
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_audit", .module = investment_audit_int_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = modules.portfolio },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = modules.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
                .{ .name = "tkcase", .module = case_int_mod },
                .{ .name = "tkdisp", .module = disp_int_mod },
                .{ .name = "tkagnt", .module = agent_int_mod },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(replay_integration_test).step);

    // Test 3: decision_cards_integration_test
    const decision_cards_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_decision_cards.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(decision_cards_integration_test).step);

    // Test 4: mock_servers_test
    const mock_servers_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_servers.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
                .{ .name = "mock_broker_market_server", .module = mock_broker_market_server_mod },
                .{ .name = "mock_openai_server", .module = mock_openai_server_mod },
            },
        }),
    });
    integration_step.dependOn(&mock_servers_test.step);

    // Test 5: link_bounds_test
    const link_bounds_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_link_bounds.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, link_bounds_test, lib_dir, shim_archives);

    // Test 6: process_demo_parity_test
    const process_demo_parity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_demo_parity.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_demo_parity_test, lib_dir, shim_archives);

    // Test 7: process_topology_test
    const process_topology_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_topology.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_topology_test, lib_dir, shim_archives);

    // Test 8: process_topology_linux_test
    const process_topology_linux_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_topology_linux.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_topology_linux_test, lib_dir, shim_archives);

    // Test 9: process_pipeline_test
    const process_pipeline_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_pipeline.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_pipeline_test, lib_dir, shim_archives);

    // Test 10: process_cpu_placement_test
    const process_cpu_placement_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_cpu_placement_test, lib_dir, shim_archives);

    // Test 11: process_cpu_placement_linux_test
    const process_cpu_placement_linux_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement_linux.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = modules.runtime },
                .{ .name = "c_abi", .module = modules.c_abi },
                .{ .name = "util", .module = modules.util },
                .{ .name = "supervisor", .module = modules.supervisor },
                .{ .name = "topologies", .module = modules.topologies_named },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, integration_step, process_cpu_placement_linux_test, lib_dir, shim_archives);

    // Test 12: test_investment_allowed_trade
    const test_investment_allowed_trade = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = modules.portfolio },
                .{ .name = "basket", .module = modules.basket },
                .{ .name = "thesis", .module = modules.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tkcase", .module = case_int_mod },
                .{ .name = "tkdisp", .module = disp_int_mod },
                .{ .name = "tkagnt", .module = agent_int_mod },
                .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(test_investment_allowed_trade).step);

    // Test 13: test_investment_blocked_limits
    const test_investment_blocked_limits = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_blocked_limits.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "investment_audit", .module = investment_audit_int_mod },
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = modules.portfolio },
                .{ .name = "basket", .module = modules.basket },
                .{ .name = "thesis", .module = modules.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tkcase", .module = case_int_mod },
                .{ .name = "tkdisp", .module = disp_int_mod },
                .{ .name = "tkagnt", .module = agent_int_mod },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(test_investment_blocked_limits).step);

    // Test 14: test_investment_input_policy_denials
    const test_investment_input_policy_denials = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_input_policy_denials.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = modules.portfolio },
                .{ .name = "basket", .module = modules.basket },
                .{ .name = "thesis", .module = modules.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(test_investment_input_policy_denials).step);

    // Test 15: test_investment_restricted_instrument
    const test_investment_restricted_instrument = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/integration/test_investment_restricted_instrument.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
                .{ .name = "adapter", .module = adapter_int_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = modules.portfolio },
                .{ .name = "basket", .module = modules.basket },
                .{ .name = "thesis", .module = modules.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "trade_ticket", .module = test_modules.trade_ticket },
            },
        }),
    });
    integration_step.dependOn(&b.addRunArtifact(test_investment_restricted_instrument).step);
}
