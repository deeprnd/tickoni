/// System test specs for the Tickoni build system.
///
/// Lists system test binaries with their module imports and linkage flags.
/// Mirrors the inline system test definitions from the original build.zig.

const std = @import("std");
const Registry = @import("registry.zig");
const helpers = @import("helpers.zig");
const codec = @import("../lib/codec.zig");

/// Register system test lanes using module references.
pub fn registerSystemSpecs(
    b: *std.Build,
    modules: @import("../mod.zig").Modules,
    _test_modules: @import("../mod.zig").TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    system_step: *std.Build.Step,
    fd_lib_dir: []const u8,
) void {
    _ = _test_modules;
    _ = fd_lib_dir;

    // Create system-level modules (investment_demo, investment_support)
    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter_messages", .module = modules.mock_adapter },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
        },
    });

    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = modules.mock_model },
            .{ .name = "basket", .module = modules.basket },
            .{ .name = "portfolio", .module = modules.portfolio },
        },
    });

    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = modules.portfolio },
            .{ .name = "basket", .module = modules.basket },
        },
    });

    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "investment_support", .module = investment_support_int_mod },
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
    system_step.dependOn(&b.addRunArtifact(system_test).step);

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
    system_step.dependOn(&b.addRunArtifact(portfolio_cash_demo_test).step);
}
