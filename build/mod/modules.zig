/// Shared named modules for the Tickoni build system.
///
/// Creates all modules (shared + test-only) and returns them in one struct.
/// This avoids circular import issues by having one source of truth for modules.

const std = @import("std");

/// All modules (shared + test-only), indexed by name.
pub const Modules = struct {
    // Shared modules
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
    logger: *std.Build.Module,
    runtime: *std.Build.Module,
    topologies_named: *std.Build.Module,
    audit_schema: *std.Build.Module,
    audit_codec: *std.Build.Module,
    tier: *std.Build.Module,
    version: *std.Build.Module,
    doctor_checks: *std.Build.Module,
    doctor_output: *std.Build.Module,
    demo_manifest: *std.Build.Module,
    demo_semver: *std.Build.Module,
    demo_diagnostic: *std.Build.Module,
    demo_preflight: *std.Build.Module,
    demo_cli: *std.Build.Module,
    demo_conformance: *std.Build.Module,
    demo_comparator: *std.Build.Module,
    demo_runner: *std.Build.Module,
    demo_substitution: *std.Build.Module,
    classification: *std.Build.Module,
    capability: *std.Build.Module,
    thesis: *std.Build.Module,
    catalog_schema: *std.Build.Module,
    catalog: *std.Build.Module,
    basket: *std.Build.Module,
    portfolio: *std.Build.Module,
    tiles: *std.Build.Module,
    supervisor_named: *std.Build.Module,
    // Test-only modules
    trade_ticket: *std.Build.Module,
    impact: *std.Build.Module,
    cards: *std.Build.Module,
    drift: *std.Build.Module,
    fixture_portfolio: *std.Build.Module,
    fixture_audit_gen: *std.Build.Module,
    model_messages: *std.Build.Module,
    mock_model: *std.Build.Module,
    adapter_messages: *std.Build.Module,
    mock_adapter: *std.Build.Module,
};

/// Creates all modules and returns them in a Modules struct.
pub fn modules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options: *std.Build.Module,
) Modules {
    const c_abi_mod = b.addModule("c_abi", .{
        .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    const util_mod = b.addModule("util", .{
        .root_source_file = b.path("src/tickoni/util/util.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c_abi", .module = c_abi_mod }},
    });
    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/tickoni/logger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "util", .module = util_mod }},
    });
    const runtime_mod = b.addModule("runtime", .{
        .root_source_file = b.path("src/tickoni/runtime/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });
    const topologies_named_mod = b.addModule("topologies", .{
        .root_source_file = b.path("src/app/tickoni/topologies.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "runtime", .module = runtime_mod }},
    });
    const audit_schema_mod = b.addModule("audit_schema", .{
        .root_source_file = b.path("src/tickoni/schema/audit/audit.zig"),
        .target = target,
        .optimize = optimize,
    });
    const audit_codec_mod = b.addModule("audit_codec", .{
        .root_source_file = b.path("src/tickoni/codec/audit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
        },
    });
    const tier_mod = b.addModule("tier", .{
        .root_source_file = b.path("src/tickoni/util/tier.zig"),
        .target = target,
        .optimize = optimize,
    });
    const version_mod = b.addModule("version", .{
        .root_source_file = b.path("src/tickoni/version.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tier", .module = tier_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "build_options", .module = build_options },
        },
    });
    const doctor_checks_mod = b.addModule("doctor_checks", .{
        .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
        .target = target,
        .optimize = optimize,
    });
    const doctor_output_mod = b.addModule("doctor_output", .{
        .root_source_file = b.path("src/tickoni/doctor/output.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "doctor_checks", .module = doctor_checks_mod },
            .{ .name = "tier", .module = tier_mod },
        },
    });
    const demo_manifest_mod = b.addModule("demo_manifest", .{
        .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_semver_mod = b.addModule("demo_semver", .{
        .root_source_file = b.path("src/tickoni/demo/semver.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_diagnostic_mod = b.addModule("demo_diagnostic", .{
        .root_source_file = b.path("src/tickoni/demo/diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_preflight_mod = b.addModule("demo_preflight", .{
        .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "demo_manifest", .module = demo_manifest_mod },
            .{ .name = "demo_semver", .module = demo_semver_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_cli_mod = b.addModule("demo_cli", .{
        .root_source_file = b.path("src/tickoni/demo/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    const demo_conformance_mod = b.addModule("demo_conformance", .{
        .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "diagnostic", .module = demo_diagnostic_mod }},
    });
    const demo_comparator_mod = b.addModule("demo_comparator", .{
        .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "conformance", .module = demo_conformance_mod }},
    });
    const demo_runner_mod = b.addModule("demo_runner", .{
        .root_source_file = b.path("src/tickoni/demo/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_substitution_mod = b.addModule("demo_substitution", .{
        .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
            .{ .name = "runner", .module = demo_runner_mod },
        },
    });
    const classification_mod = b.addModule("classification", .{
        .root_source_file = b.path("src/tickoni/schema/classification/classification.zig"),
        .target = target,
        .optimize = optimize,
    });
    const capability_mod = b.addModule("capability", .{
        .root_source_file = b.path("src/tickoni/schema/capability/capability.zig"),
        .target = target,
        .optimize = optimize,
    });
    const thesis_mod = b.addModule("thesis", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const catalog_schema_mod = b.addModule("catalog_schema", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "thesis", .module = thesis_mod }},
    });
    const catalog_mod = b.addModule("catalog", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "catalog_schema", .module = catalog_schema_mod },
        },
    });
    const basket_mod = b.addModule("basket", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "catalog", .module = catalog_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const portfolio_mod = b.addModule("portfolio", .{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "basket", .module = basket_mod }},
    });

    // fixture_portfolio must come before trade_ticket (which imports it)
    const fixture_portfolio_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });

    // Shared test-only modules
    const fixture_audit_gen_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/fixture_audit_gen.zig"),
        .target = target,
        .optimize = optimize,
    });
    const audit_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
        },
    });
    const tiles_mod = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });
    const supervisor_named_mod = b.addModule("supervisor", .{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Test-only schema modules
    const trade_ticket_mod = b.createModule(.{
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
    const impact_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
        },
    });
    const cards_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "impact", .module = impact_mod },
        },
    });
    const drift_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "cards", .module = cards_mod },
        },
    });
    // Test mock modules
    const model_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_model_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "model_messages", .module = model_messages_mod }},
    });
    const adapter_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const mock_adapter_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
        },
    });

    return Modules{
        .c_abi = c_abi_mod,
        .util = util_mod,
        .logger = logger_mod,
        .runtime = runtime_mod,
        .topologies_named = topologies_named_mod,
        .audit_schema = audit_schema_mod,
        .audit_codec = audit_codec_mod,
        .tier = tier_mod,
        .version = version_mod,
        .doctor_checks = doctor_checks_mod,
        .doctor_output = doctor_output_mod,
        .demo_manifest = demo_manifest_mod,
        .demo_semver = demo_semver_mod,
        .demo_diagnostic = demo_diagnostic_mod,
        .demo_preflight = demo_preflight_mod,
        .demo_cli = demo_cli_mod,
        .demo_conformance = demo_conformance_mod,
        .demo_comparator = demo_comparator_mod,
        .demo_runner = demo_runner_mod,
        .demo_substitution = demo_substitution_mod,
        .classification = classification_mod,
        .capability = capability_mod,
        .thesis = thesis_mod,
        .catalog_schema = catalog_schema_mod,
        .catalog = catalog_mod,
        .basket = basket_mod,
        .portfolio = portfolio_mod,
        .tiles = tiles_mod,
        .supervisor_named = supervisor_named_mod,
        .trade_ticket = trade_ticket_mod,
        .impact = impact_mod,
        .cards = cards_mod,
        .drift = drift_mod,
        .fixture_portfolio = fixture_portfolio_mod,
        .fixture_audit_gen = fixture_audit_gen_mod,
        .model_messages = model_messages_mod,
        .mock_model = mock_model_mod,
        .adapter_messages = adapter_messages_mod,
        .mock_adapter = mock_adapter_mod,
    };
}
