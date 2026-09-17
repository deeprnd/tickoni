/// Integration test lane strategy.
///
/// Extracts inline integration test registration from build.zig into a callable
/// function. Preserves identical compile flags, linkage, and module structure.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const shims = @import("../lib/shims.zig");

/// Integration modules passed in from build.zig.
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
    supervisor_named_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
};

/// Register all integration test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    int_mods: IntegrationModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    integration_step: *std.Build.Step,
) void {
    // investment_demo_test — standalone test with codec linkage
    const investment_demo_test = b.addTest(.{ .root_module = int_mods.investment_demo_test_mod });
    codec.linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
    integration_step.dependOn(&b.addRunArtifact(investment_demo_test).step);

    // Static integration tests (mock-backed, no supervisor needed)
    const static_tests: []const []const u8 = &.{
        "src/tickoni/test/integration/test_investment_allowed_trade.zig",
        "src/tickoni/test/integration/test_investment_blocked_limits.zig",
        "src/tickoni/test/integration/test_investment_restricted_instrument.zig",
        "src/tickoni/test/integration/test_investment_input_policy_denials.zig",
    };

    // Build import slice using std.Build.Module.Import so Zig accepts it
    // for .imports.
    const imports = b.allocator.alloc(std.Build.Module.Import, 13) catch unreachable;
    defer b.allocator.free(imports);

    imports[0] = .{ .name = "adapter", .module = int_mods.adapter_int_mod };
    imports[1] = .{ .name = "audit_tile", .module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/audit/fixture_audit_gen.zig"),
        .target = target,
        .optimize = optimize,
    }) };
    imports[2] = .{ .name = "basket", .module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
    }) };
    imports[3] = .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod };
    imports[4] = .{ .name = "investment_support", .module = int_mods.investment_support_int_mod };
    imports[5] = .{ .name = "model", .module = int_mods.model_int_mod };
    imports[6] = .{ .name = "portfolio", .module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
    }) };
    imports[7] = .{ .name = "replay", .module = int_mods.replay_int_mod };
    imports[8] = .{ .name = "thesis", .module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
    }) };
    imports[9] = .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod };
    imports[10] = .{ .name = "tool", .module = int_mods.tool_int_mod };
    imports[11] = .{ .name = "trade_ticket", .module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
    }) };
    imports[12] = .{ .name = "tkcase", .module = int_mods.case_int_mod };

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

    // Process-mode integration tests — Linux only (shared memory topology).
    // Each self-execs zig-out/bin/tickoni-supervisor per tile.
    // One shared install step, not one addInstallArtifact per test.
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

        const runtime_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        const c_abi_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
            .target = target,
            .optimize = optimize,
        });
        const util_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/util.zig"),
            .target = target,
            .optimize = optimize,
        });
        const topologies_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/topologies.zig"),
            .target = target,
            .optimize = optimize,
        });

        const proc_imports = [_]std.Build.Module.Import{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "supervisor", .module = int_mods.supervisor_named_mod },
            .{ .name = "topologies", .module = topologies_mod },
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
}
