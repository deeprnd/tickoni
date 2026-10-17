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

/// Which subset of integration tests to register.
///
/// infra = infrastructure layer: supervisor, tile lifecycle, Tango links,
///         CPU placement, mock server infrastructure, model tile HTTP.
/// domain = financial domain: investment policy, allowed/blocked trades,
///          replay, decision cards.
pub const LaneKind = enum {
    all,
    infra,
    domain,
};

/// Max possible run count across all lane kinds (all=15).
const max_run_count: usize = 15;

/// Register integration tests for the requested lane kind.
pub fn strategy(
    b: *std.Build,
    int_mods: IntegrationModules,
    kind: LaneKind,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    integration_step: *std.Build.Step,
    exe_install: *std.Build.Step.InstallArtifact,
) void {
    var test_runs: [max_run_count]*std.Build.Step.Run = undefined;
    var test_run_count: usize = 0;

    // infra_imports — shared by infra test files that use supervisor/topology.
    const infra_imports = [_]std.Build.Module.Import{
        .{ .name = "runtime", .module = int_mods.shared_runtime },
        .{ .name = "c_abi", .module = int_mods.shared_c_abi },
        .{ .name = "util", .module = int_mods.shared_util },
        .{ .name = "supervisor", .module = int_mods.supervisor_named_mod },
        .{ .name = "topologies", .module = int_mods.shared_topologies },
    };

    // ------------------------------------------------------------------
    // Infra tests (8)
    // ------------------------------------------------------------------
    const register_infra: bool = switch (kind) {
        .all => true,
        .infra => true,
        .domain => false,
    };

    if (register_infra) {
        // 1-7. Process-mode files share infra_imports.
        const infra_proc_files: []const []const u8 = &.{
            "src/tickoni/test/integration/test_metric_tile_integration.zig",
            "src/tickoni/test/integration/test_process_topology.zig",
            "src/tickoni/test/integration/test_process_pipeline.zig",
            "src/tickoni/test/integration/test_process_shutdown_reap.zig",
            "src/tickoni/test/integration/test_process_cpu_placement.zig",
            "src/tickoni/test/integration/test_process_demo_parity.zig",
            "src/tickoni/test/integration/test_link_bounds.zig",
        };

        for (infra_proc_files) |path| {
            const test_bin = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &infra_imports,
                }),
            });
            codec.linkTickoniCodec(b, test_bin, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, test_bin, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, test_bin, fd_lib_dir);
            // libfd_waltz.a contains fd_http_server.o, which references ZSTD.
            test_bin.root_module.addObjectFile(.{
                .cwd_relative = b.fmt("{s}/libfd_zstd.a", .{fd_lib_dir}),
            });
            test_runs[test_run_count] = shims.addPlainTestRun(b, test_bin);
            test_runs[test_run_count].step.dependOn(&exe_install.step);
            test_run_count += 1;
        }

        // 8. Mock servers + model tile HTTP (series — two binaries, one step).
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
        firedancer.linkTickoniFiredancer(b, mock_servers_test, fd_lib_dir);

        const model_tile_http_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_model_tile_http.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "model", .module = int_mods.model_int_mod },
                    .{ .name = "mock_http_support", .module = int_mods.mock_http_support_mod },
                    .{ .name = "mock_openai_server", .module = int_mods.mock_openai_server_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, model_tile_http_test, fd_lib_dir);
        firedancer.linkTickoniFiredancer(b, model_tile_http_test, fd_lib_dir);

        test_runs[test_run_count] = shims.addPlainTestRunSeries(
            b,
            &.{ mock_servers_test, model_tile_http_test },
        );
        test_run_count += 1;
    }

    // ------------------------------------------------------------------
    // Domain tests (7)
    // ------------------------------------------------------------------
    const register_domain: bool = switch (kind) {
        .all => true,
        .infra => false,
        .domain => true,
    };

    if (register_domain) {
        // 1. Investment replay — full domain stack.
        const replay_integration_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_replay.zig",
                ),
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
        test_runs[test_run_count] = shims.addPlainTestRun(b, replay_integration_test);
        test_run_count += 1;

        // 2. Investment decision cards.
        const decision_cards_integration_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_decision_cards.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "investment_demo", .module = int_mods.investment_demo_mod },
                    .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, decision_cards_integration_test, fd_lib_dir);
        test_runs[test_run_count] = shims.addPlainTestRun(b, decision_cards_integration_test);
        test_run_count += 1;

        // 3. Investment allowed trade.
        const allowed_trade_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_allowed_trade.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = int_mods.adapter_int_mod },
                    .{ .name = "model", .module = int_mods.model_int_mod },
                    .{ .name = "portfolio", .module = int_mods.shared_portfolio },
                    .{ .name = "thesis", .module = int_mods.shared_thesis },
                    .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket },
                    .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                    .{ .name = "tkagnt", .module = int_mods.agent_int_mod },
                    .{ .name = "tkcase", .module = int_mods.case_int_mod },
                    .{ .name = "tkdisp", .module = int_mods.disp_int_mod },
                    .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, allowed_trade_test, fd_lib_dir);
        test_runs[test_run_count] = shims.addPlainTestRun(b, allowed_trade_test);
        test_run_count += 1;

        // 4. Investment blocked limits.
        const blocked_limits_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_blocked_limits.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = int_mods.adapter_int_mod },
                    .{ .name = "audit_tile", .module = int_mods.shared_audit_tile },
                    .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod },
                    .{ .name = "model", .module = int_mods.model_int_mod },
                    .{ .name = "portfolio", .module = int_mods.shared_portfolio },
                    .{ .name = "replay", .module = int_mods.replay_int_mod },
                    .{ .name = "thesis", .module = int_mods.shared_thesis },
                    .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket },
                    .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                    .{ .name = "tkagnt", .module = int_mods.agent_int_mod },
                    .{ .name = "tkcase", .module = int_mods.case_int_mod },
                    .{ .name = "tkdisp", .module = int_mods.disp_int_mod },
                    .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, blocked_limits_test, fd_lib_dir);
        test_runs[test_run_count] = shims.addPlainTestRun(b, blocked_limits_test);
        test_run_count += 1;

        // 5. Investment input policy denials.
        const input_denials_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_input_policy_denials.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = int_mods.adapter_int_mod },
                    .{ .name = "portfolio", .module = int_mods.shared_portfolio },
                    .{ .name = "thesis", .module = int_mods.shared_thesis },
                    .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
                    .{ .name = "tool", .module = int_mods.tool_int_mod },
                    .{ .name = "trade_ticket", .module = int_mods.shared_trade_ticket },
                    .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, input_denials_test, fd_lib_dir);
        test_runs[test_run_count] = shims.addPlainTestRun(b, input_denials_test);
        test_run_count += 1;

        // 6. Investment restricted instrument.
        const restricted_instrument_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(
                    "src/tickoni/test/integration/test_investment_restricted_instrument.zig",
                ),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "audit_tile", .module = int_mods.shared_audit_tile },
                    .{ .name = "basket", .module = int_mods.shared_basket },
                    .{ .name = "investment_audit", .module = int_mods.investment_audit_int_mod },
                    .{ .name = "replay", .module = int_mods.replay_int_mod },
                    .{ .name = "thesis", .module = int_mods.shared_thesis },
                    .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
                    .{ .name = "tkagnt", .module = int_mods.agent_int_mod },
                    .{ .name = "tkcase", .module = int_mods.case_int_mod },
                    .{ .name = "tkdisp", .module = int_mods.disp_int_mod },
                    .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
                },
            }),
        });
        codec.linkTickoniCodec(b, restricted_instrument_test, fd_lib_dir);
        test_runs[test_run_count] = shims.addPlainTestRun(b, restricted_instrument_test);
        test_run_count += 1;
    }

    // Chain sequential execution only for the populated entries.
    for (test_runs[0..test_run_count], 0..) |run, idx| {
        if (idx > 0) run.step.dependOn(&test_runs[idx - 1].step);
        integration_step.dependOn(&run.step);
    }
}
