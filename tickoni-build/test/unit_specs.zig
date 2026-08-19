/// Unit test specs for the Tickoni build system.
///
/// Registers unit test binaries with their module imports.

const std = @import("std");
const helpers = @import("helpers.zig");

/// Register all unit test lanes.
pub fn registerUnitSpecs(
    b: *std.Build,
    modules: @import("../mod.zig").Modules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    step: *std.Build.Step,
    lib_dir: []const u8,
) void {
    const c_abi_mod = modules.c_abi;
    const util_mod = modules.util;
    _ = modules.logger;
    const runtime_mod = modules.runtime;
    _ = modules.topologies_named;
    const audit_schema_mod = modules.audit_schema;
    const audit_codec_mod = modules.audit_codec;
    const tier_mod = modules.tier;
    const demo_diagnostic_mod = modules.demo_diagnostic;
    const demo_semver_mod = modules.demo_semver;
    const demo_conformance_mod = modules.demo_conformance;
    const demo_runner_mod = modules.demo_runner;
    _ = modules.demo_substitution;
    const classification_mod = modules.classification;
    _ = modules.capability;
    const thesis_mod = modules.thesis;
    const catalog_schema_mod = modules.catalog_schema;
    const catalog_mod = modules.catalog;
    const basket_mod = modules.basket;
    const portfolio_mod = modules.portfolio;
    const trade_ticket_mod = modules.trade_ticket;
    const impact_mod = modules.impact;
    const cards_mod = modules.cards;
    _ = modules.drift;
    const fixture_portfolio_mod = modules.fixture_portfolio;
    _ = modules.fixture_audit_gen;
    const model_messages_mod = modules.model_messages;
    const mock_model_mod = modules.mock_model;
    const adapter_messages_mod = modules.adapter_messages;
    const mock_adapter_mod = modules.mock_adapter;

    // Remove: investment tests (investment/ dir doesn't exist)
    // Remove: placeholder tests (src/tickoni/test/unit/ dir doesn't exist)

    // Version test
    const version_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/version.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tier", .module = tier_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "build_options", .module = modules.version_opts.createModule() },
        },
    });
    const version_test = b.addTest(.{ .root_module = version_test_mod });
    _ = helpers.addPlainTestRun(b, step, version_test, fd_lib_dir);

    // Doctor tests
    const doctor_checks_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
        .target = target,
        .optimize = optimize,
    });
    const doctor_checks_test = b.addTest(.{ .root_module = doctor_checks_test_mod });
    _ = helpers.addPlainTestRun(b, step, doctor_checks_test, fd_lib_dir);

    const doctor_output_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/doctor/output.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "doctor_checks", .module = doctor_checks_test_mod },
            .{ .name = "tier", .module = tier_mod },
        },
    });
    const doctor_output_test = b.addTest(.{ .root_module = doctor_output_test_mod });
    _ = helpers.addPlainTestRun(b, step, doctor_output_test, fd_lib_dir);

    // Demo tests
    const demo_manifest_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_manifest_test = b.addTest(.{ .root_module = demo_manifest_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_manifest_test, fd_lib_dir);

    const demo_preflight_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "demo_manifest", .module = demo_manifest_test_mod },
            .{ .name = "demo_semver", .module = demo_semver_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_preflight_test = b.addTest(.{ .root_module = demo_preflight_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_preflight_test, fd_lib_dir);

    // Demo diagnostic test - demo_diagnostic_mod is already a module ref from modules
    const demo_diagnostic_test = b.addTest(.{ .root_module = demo_diagnostic_mod });
    _ = helpers.addPlainTestRun(b, step, demo_diagnostic_test, fd_lib_dir);

    const demo_conformance_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_conformance_test = b.addTest(.{ .root_module = demo_conformance_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_conformance_test, fd_lib_dir);

    const demo_comparator_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
        },
    });
    const demo_comparator_test = b.addTest(.{ .root_module = demo_comparator_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_comparator_test, fd_lib_dir);

    const demo_runner_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_runner_test = b.addTest(.{ .root_module = demo_runner_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_runner_test, fd_lib_dir);

    const demo_substitution_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
            .{ .name = "runner", .module = demo_runner_mod },
        },
    });
    const demo_substitution_test = b.addTest(.{ .root_module = demo_substitution_test_mod });
    _ = helpers.addPlainTestRun(b, step, demo_substitution_test, fd_lib_dir);

    // Thesis and catalog tests
    const thesis_codec_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/codec/audit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
        },
    });
    const thesis_codec_test = b.addTest(.{ .root_module = thesis_codec_test_mod });
    _ = helpers.addPlainTestRun(b, step, thesis_codec_test, fd_lib_dir);

    const thesis_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const thesis_test = b.addTest(.{ .root_module = thesis_test_mod });
    _ = helpers.addPlainTestRun(b, step, thesis_test, fd_lib_dir);

    const catalog_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "catalog_schema", .module = catalog_schema_mod },
        },
    });
    const catalog_test = b.addTest(.{ .root_module = catalog_test_mod });
    _ = helpers.addPlainTestRun(b, step, catalog_test, fd_lib_dir);

    const catalog_schema_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const catalog_schema_test = b.addTest(.{ .root_module = catalog_schema_test_mod });
    _ = helpers.addPlainTestRun(b, step, catalog_schema_test, fd_lib_dir);

    const basket_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "catalog", .module = catalog_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const basket_test = b.addTest(.{ .root_module = basket_test_mod });
    _ = helpers.addPlainTestRun(b, step, basket_test, fd_lib_dir);

    const portfolio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const portfolio_test = b.addTest(.{ .root_module = portfolio_test_mod });
    _ = helpers.addPlainTestRun(b, step, portfolio_test, fd_lib_dir);

    const fixture_portfolio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const fixture_portfolio_test = b.addTest(.{ .root_module = fixture_portfolio_test_mod });
    _ = helpers.addPlainTestRun(b, step, fixture_portfolio_test, fd_lib_dir);

    // Mock model test
    const model_messages_test = b.addTest(.{ .root_module = model_messages_mod });
    _ = helpers.addPlainTestRun(b, step, model_messages_test, fd_lib_dir);

    const mock_model_test = b.addTest(.{ .root_module = mock_model_mod });
    _ = helpers.addPlainTestRun(b, step, mock_model_test, fd_lib_dir);

    // Remove: link tests (src/tickoni/test/unit/ dir doesn't exist)
    // Remove: boot test (src/tickoni/test/unit/test_boot.zig doesn't exist)
    // Remove: launch_spec test (doesn't exist)
    // Remove: topology_spec test (doesn't exist)
    // Remove: topo_run test (doesn't exist)
    // Remove: topob test (doesn't exist)

    // Runtime tests
    const cnc_counters_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/runtime/cnc_counters.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const cnc_counters_test = b.addTest(.{ .root_module = cnc_counters_test_mod });
    _ = helpers.addPlainTestRun(b, step, cnc_counters_test, fd_lib_dir);

    const cpu_placement_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
        },
    });
    const cpu_placement_test = b.addTest(.{ .root_module = cpu_placement_test_mod });
    _ = helpers.addPlainTestRun(b, step, cpu_placement_test, fd_lib_dir);

    // Trade ticket tests
    const trade_ticket_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "thesis", .module = thesis_mod },
        },
    });
    const trade_ticket_test = b.addTest(.{ .root_module = trade_ticket_test_mod });
    _ = helpers.addPlainTestRun(b, step, trade_ticket_test, fd_lib_dir);

    const impact_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
        },
    });
    const impact_test = b.addTest(.{ .root_module = impact_test_mod });
    _ = helpers.addPlainTestRun(b, step, impact_test, fd_lib_dir);

    const cards_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "impact", .module = impact_mod },
        },
    });
    const cards_test = b.addTest(.{ .root_module = cards_test_mod });
    _ = helpers.addPlainTestRun(b, step, cards_test, fd_lib_dir);

    const drift_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "cards", .module = cards_mod },
        },
    });
    const drift_test = b.addTest(.{ .root_module = drift_test_mod });
    _ = helpers.addPlainTestRun(b, step, drift_test, fd_lib_dir);

    // Remove: allowed/denied trade fixture tests (files don't exist)

    // Tile tests — ordered to respect Zig module dependency ordering
    // (policy and disp are independent; model and adapter are independent;
    // tool depends on adapter; agent depends on adapter+disp+model+policy+tool;
    // replay depends on adapter+model+policy)

    // Policy test (independent tile)
    const policy_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const policy_test = b.addTest(.{ .root_module = policy_test_mod });
    _ = helpers.addPlainTestRun(b, step, policy_test, fd_lib_dir);

    // Disp test (independent tile)
    const disp_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "demo_manifest", .module = demo_manifest_test_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const disp_test = b.addTest(.{ .root_module = disp_test_mod });
    _ = helpers.addPlainTestRun(b, step, disp_test, fd_lib_dir);

    // Model test (independent tile)
    const model_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const model_test = b.addTest(.{ .root_module = model_test_mod });
    _ = helpers.addPlainTestRun(b, step, model_test, fd_lib_dir);

    // Adapter test (independent tile)
    const adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const adapter_test = b.addTest(.{ .root_module = adapter_test_mod });
    _ = helpers.addPlainTestRun(b, step, adapter_test, fd_lib_dir);

    const mock_adapter_test = b.addTest(.{ .root_module = mock_adapter_mod });
    _ = helpers.addPlainTestRun(b, step, mock_adapter_test, fd_lib_dir);

    // Tool test (depends on adapter_test_mod)
    const tool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_test_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "demo_manifest", .module = demo_manifest_test_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const tool_test = b.addTest(.{ .root_module = tool_test_mod });
    _ = helpers.addPlainTestRun(b, step, tool_test, fd_lib_dir);

    // Case test (independent tile, no cross-tile imports)
    const case_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "demo_manifest", .module = demo_manifest_test_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const case_test = b.addTest(.{ .root_module = case_test_mod });
    _ = helpers.addPlainTestRun(b, step, case_test, fd_lib_dir);

    // Agent test (depends on adapter_test_mod, disp_test_mod, model_test_mod, policy_test_mod, tool_test_mod)
    const agent_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_test_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "capability", .module = modules.capability },
            .{ .name = "disp", .module = disp_test_mod },
            .{ .name = "model", .module = model_test_mod },
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
            .{ .name = "model_messages", .module = model_messages_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "tkpoly", .module = policy_test_mod },
            .{ .name = "tool", .module = tool_test_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const agent_test = b.addTest(.{ .root_module = agent_test_mod });
    _ = helpers.addPlainTestRun(b, step, agent_test, fd_lib_dir);

    // Audit test (independent tile, no cross-tile imports)
    const audit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "tier", .module = tier_mod },
        },
    });
    const audit_test = b.addTest(.{ .root_module = audit_test_mod });
    _ = helpers.addPlainTestRun(b, step, audit_test, fd_lib_dir);

    // Remove: ingest/normalize/dedup tiles (mod.zig doesn't exist)

    // Replay test (depends on adapter_test_mod, model_test_mod, policy_test_mod)
    const replay_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_test_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "drift", .module = modules.drift },
            .{ .name = "model", .module = model_test_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "tkpoly", .module = policy_test_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const replay_test = b.addTest(.{ .root_module = replay_test_mod });
    _ = helpers.addPlainTestRun(b, step, replay_test, fd_lib_dir);
}
