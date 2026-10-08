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
    exe_install: *std.Build.Step.InstallArtifact,
) void {
    // TEMPORARY: only run metric tile integration tests.
    // Comment out other tests to avoid noise during debugging.
    const test_run_count: usize = 1; // only isolated_metric
    var test_runs: [test_run_count]*std.Build.Step.Run = undefined;
    var test_run_idx: usize = 0;

    // proc_imports is still needed for isolated_process_tests below
    const proc_imports = [_]std.Build.Module.Import{
        .{ .name = "runtime", .module = int_mods.shared_runtime },
        .{ .name = "c_abi", .module = int_mods.shared_c_abi },
        .{ .name = "util", .module = int_mods.shared_util },
        .{ .name = "supervisor", .module = int_mods.supervisor_named_mod },
        .{ .name = "topologies", .module = int_mods.shared_topologies },
    };

    // Supervisor binary must be installed before process-mode tests
    // can spawn it (tile_exe_path = "build/zig-out/bin/tickoni-supervisor").
    // Each process test run step depends on the install so the file exists.
    // Isolate test_metric_tile_integration.zig - skip the rest
    const isolated_process_tests: []const []const u8 = &.{
        "src/tickoni/test/integration/test_metric_tile_integration.zig",
    };
    for (isolated_process_tests) |path| {
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
        // libfd_waltz.a contains fd_http_server.o, which references ZSTD.
        process_test.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_zstd.a", .{fd_lib_dir}) });
        test_runs[test_run_idx] = shims.addPlainTestRun(b, process_test);
        test_runs[test_run_idx].step.dependOn(&exe_install.step);
        test_run_idx += 1;
    }

    // TEMPORARY: commented out — replay_integration_test
    // const replay_integration_test = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/tickoni/test/integration/test_investment_replay.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "adapter", .module = int_mods.adapter_int_mod },
    //             .{ .name = "audit_tile", .module = int_mods.shared_audit_tile },
    //             .{ .name = "basket", .module = int_mods.shared_basket },
    //             .{ .name = "investment_demo", .module = int_mods.investment_demo_mod },
    //             .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod },
    //             .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
    //             .{ .name = "model", .module = int_mods.model_int_mod },
    //             .{ .name = "portfolio", .module = int_mods.shared_portfolio },
    //             .{ .name = "replay", .module = int_mods.replay_int_mod },
    //             .{ .name = "thesis", .module = int_mods.shared_thesis },
    //             .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
    //             .{ .name = "tool", .module = int_mods.tool_int_mod },
    //             .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket },
    //             .{ .name = "tkcase", .module = int_mods.case_int_mod },
    //             .{ .name = "tkdisp", .module = int_mods.disp_int_mod },
    //             .{ .name = "tkagnt", .module = int_mods.agent_int_mod },
    //         },
    //     }),
    // });
    // codec.linkTickoniCodec(b, replay_integration_test, fd_lib_dir);
    // test_runs[test_run_idx] = shims.addPlainTestRun(b, replay_integration_test);
    // test_run_idx += 1;

    // TEMPORARY: commented out — decision_cards_integration_test
    // const decision_cards_integration_test = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/tickoni/test/integration/test_investment_decision_cards.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "investment_demo", .module = int_mods.investment_demo_mod },
    //             .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
    //         },
    //     }),
    // });
    // codec.linkTickoniCodec(b, decision_cards_integration_test, fd_lib_dir);
    // test_runs[test_run_idx] = shims.addPlainTestRun(b, decision_cards_integration_test);
    // test_run_idx += 1;

    // TEMPORARY: commented out — mock_servers_test + model_tile_http_test
    // const mock_servers_test = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/tickoni/test/mocks/mock_servers.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "mock_http_support", .module = int_mods.mock_http_support_mod },
    //             .{ .name = "mock_broker_market_server", .module = int_mods.mock_broker_market_server_mod },
    //             .{ .name = "mock_openai_server", .module = int_mods.mock_openai_server_mod },
    //         },
    //     }),
    // });
    // firedancer.linkTickoniFiredancer(b, mock_servers_test, fd_lib_dir);
    //
    // const model_tile_http_test = b.addTest(.{
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("src/tickoni/test/integration/test_model_tile_http.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //         .imports = &.{
    //             .{ .name = "model", .module = int_mods.model_int_mod },
    //             .{ .name = "mock_http_support", .module = int_mods.mock_http_support_mod },
    //             .{ .name = "mock_openai_server", .module = int_mods.mock_openai_server_mod },
    //         },
    //     }),
    // });
    // codec.linkTickoniCodec(b, model_tile_http_test, fd_lib_dir);
    // firedancer.linkTickoniFiredancer(b, model_tile_http_test, fd_lib_dir);
    //
    // test_runs[test_run_idx] = shims.addPlainTestRunSeries(b, &.{ mock_servers_test, model_tile_http_test });
    // test_run_idx += 1;

    std.debug.assert(test_run_idx == test_runs.len);
    for (test_runs, 0..) |run, idx| {
        if (idx > 0) run.step.dependOn(&test_runs[idx - 1].step);
        integration_step.dependOn(&run.step);
    }
}
