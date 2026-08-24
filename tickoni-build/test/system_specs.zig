/// System test specs for the Tickoni build system.
///
/// Lists system test binaries with their module imports and linkage flags.
/// System tests link against Firedancer/Tickoni C libraries via the test_system group.

const std = @import("std");
const helpers = @import("helpers.zig");
const config = @import("../generated/config.zig");

/// Register system test lanes using module references.
pub fn registerSystemSpecs(
    b: *std.Build,
    modules: @import("../mod.zig").Modules,
    _test_modules: @import("../mod.zig").TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    system_step: *std.Build.Step,
    lib_dir: []const u8,
    shim_archives: []const *std.Build.Step.Compile,
) void {
    _ = _test_modules;

    // System-level modules (investment_demo, investment_support)
    // model_int_mod must be declared before adapter_int_mod
    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mock_model", .module = modules.mock_model },
            .{ .name = "model_messages", .module = modules.model_messages },
            .{ .name = "c_abi", .module = modules.c_abi },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter_messages", .module = modules.adapter_messages },
            .{ .name = "mock_adapter", .module = modules.mock_adapter },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "fixture_portfolio", .module = modules.fixture_portfolio },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "thesis", .module = modules.thesis },
        },
    });

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
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    // Reusable replay module for system tests (inline, since replay is not in Modules struct)
    const replay_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    // Inline tkpoly module for investment_demo (policy tile module used in demo)
    const tkpoly_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    // Inline tool module for investment_demo (tool broker module used in demo)
    const tool_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "fixture_portfolio", .module = modules.fixture_portfolio },
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "cards", .module = modules.cards },
            .{ .name = "drift", .module = modules.drift },
            .{ .name = "impact", .module = modules.impact },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "replay", .module = replay_mod },
            .{ .name = "thesis", .module = modules.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int },
            .{ .name = "tool", .module = tool_int },
            .{ .name = "trade_ticket", .module = modules.trade_ticket },
        },
    });

    // System Test 1: test_investment_demo_live
    const system_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_investment_demo_live.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, system_step, system_test, lib_dir, shim_archives);

    // System Test 2: test_portfolio_cash_demo
    const portfolio_cash_demo_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/system/test_portfolio_cash_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "investment_demo", .module = investment_demo_mod },
                .{ .name = "investment_support", .module = investment_support_int_mod },
            },
        }),
    });
    _ = helpers.addPlainTestRun(b, system_step, portfolio_cash_demo_test, lib_dir, shim_archives);
}
