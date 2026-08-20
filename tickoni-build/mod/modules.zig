/// Shared module declarations for the Tickoni build system.
///
/// All named modules used across the exe, unit tests, integration tests,
/// system tests, and coverage tests are declared here so the main build.zig
/// can import them via `build_mod.modules(b, target, optimize)` and get a
/// struct with all modules as fields.

const std = @import("std");

/// Struct containing all shared named modules.
pub const Modules = struct {
    c_abi: *std.Build.Module,
    util: *std.Build.Module,
    logger: *std.Build.Module,
    runtime: *std.Build.Module,
    topologies_named: *std.Build.Module,
    audit_schema: *std.Build.Module,
    audit_codec: *std.Build.Module,
    fixture_audit_gen: *std.Build.Module,
    audit_tile: *std.Build.Module,
    tier: *std.Build.Module,
    version: *std.Build.Module,
    version_opts: *std.Build.Step.Options,
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
    fixture_portfolio: *std.Build.Module,
    trade_ticket: *std.Build.Module,
    impact: *std.Build.Module,
    cards: *std.Build.Module,
    drift: *std.Build.Module,
    model_messages: *std.Build.Module,
    mock_model: *std.Build.Module,
    adapter_messages: *std.Build.Module,
    mock_adapter: *std.Build.Module,
    tiles: *std.Build.Module,
    supervisor: *std.Build.Module,
};

/// Create all shared modules given a build context, target, and optimize mode.
/// Returns a Modules struct with all named module fields populated.
pub fn modules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) Modules {
    const c_abi = b.addModule("c_abi", .{
        .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const util = b.addModule("util", .{
        .root_source_file = b.path("src/tickoni/util/util.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "c_abi", .module = c_abi } },
    });

    const logger = b.addModule("logger", .{
        .root_source_file = b.path("src/tickoni/logger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "util", .module = util } },
    });

    const runtime = b.addModule("runtime", .{
        .root_source_file = b.path("src/tickoni/runtime/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi },
            .{ .name = "util", .module = util },
            .{ .name = "logger", .module = logger },
        },
    });

    const topologies_named = b.addModule("topologies", .{
        .root_source_file = b.path("src/app/tickoni/topologies.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "runtime", .module = runtime } },
    });

    const audit_schema = b.addModule("audit_schema", .{
        .root_source_file = b.path("src/tickoni/schema/audit/audit.zig"),
        .target = target,
        .optimize = optimize,
    });

    const audit_codec = b.addModule("audit_codec", .{
        .root_source_file = b.path("src/tickoni/codec/audit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi },
            .{ .name = "audit_schema", .module = audit_schema },
        },
    });

    const fixture_audit_gen = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/fixture_audit_gen.zig"),
        .target = target,
        .optimize = optimize,
    });

    const audit_tile = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_codec", .module = audit_codec },
            .{ .name = "audit_schema", .module = audit_schema },
            .{ .name = "fixture_audit_gen", .module = fixture_audit_gen },
        },
    });

    // Version / doctor / demo modules
    const tier = b.addModule("tier", .{
        .root_source_file = b.path("src/tickoni/util/tier.zig"),
        .target = target,
        .optimize = optimize,
    });

    const build_version_option = b.option([]const u8, "version", "Build version string") orelse "0.1.0";
    var bv_major: u16 = 0;
    var bv_minor: u16 = 0;
    var bv_patch: u16 = 0;
    var bv_pre: []const u8 = "dev";
    {
        const parts = std.mem.splitScalar(u8, build_version_option, '.');
        var parts_it = parts;
        if (parts_it.next()) |s| bv_major = std.fmt.parseInt(u16, s, 10) catch 0;
        if (parts_it.next()) |s| bv_minor = std.fmt.parseInt(u16, s, 10) catch 0;
        if (parts_it.next()) |s| {
            if (std.mem.indexOf(u8, s, "-")) |dash| {
                bv_patch = std.fmt.parseInt(u16, s[0..dash], 10) catch 0;
                bv_pre = s[dash + 1 ..];
            } else {
                bv_patch = std.fmt.parseInt(u16, s, 10) catch 0;
            }
        }
    }

    const version_opts = b.addOptions();
    version_opts.addOption([]const u8, "BUILD_VERSION", build_version_option);
    version_opts.addOption(u16, "BUILD_VERSION_MAJOR", bv_major);
    version_opts.addOption(u16, "BUILD_VERSION_MINOR", bv_minor);
    version_opts.addOption(u16, "BUILD_VERSION_PATCH", bv_patch);
    version_opts.addOption([]const u8, "BUILD_VERSION_PRE", bv_pre);
    version_opts.addOption([]const u8, "BUILD_GIT_SHA", "unknown");
    version_opts.addOption([]const u8, "BUILD_ID", "dev-unknown");

    const version = b.addModule("version", .{
        .root_source_file = b.path("src/tickoni/version.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tier", .module = tier },
            .{ .name = "audit_schema", .module = audit_schema },
            .{ .name = "build_options", .module = version_opts.createModule() },
        },
    });

    const doctor_checks = b.addModule("doctor_checks", .{
        .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
        .target = target,
        .optimize = optimize,
    });

    const doctor_output = b.addModule("doctor_output", .{
        .root_source_file = b.path("src/tickoni/doctor/output.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "doctor_checks", .module = doctor_checks },
            .{ .name = "tier", .module = tier },
        },
    });

    const demo_manifest = b.addModule("demo_manifest", .{
        .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo_semver = b.addModule("demo_semver", .{
        .root_source_file = b.path("src/tickoni/demo/semver.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo_diagnostic = b.addModule("demo_diagnostic", .{
        .root_source_file = b.path("src/tickoni/demo/diagnostic.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo_preflight = b.addModule("demo_preflight", .{
        .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "demo_manifest", .module = demo_manifest },
            .{ .name = "demo_semver", .module = demo_semver },
            .{ .name = "diagnostic", .module = demo_diagnostic },
        },
    });

    const demo_cli = b.addModule("demo_cli", .{
        .root_source_file = b.path("src/tickoni/demo/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const demo_conformance = b.addModule("demo_conformance", .{
        .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "diagnostic", .module = demo_diagnostic } },
    });

    const demo_comparator = b.addModule("demo_comparator", .{
        .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "conformance", .module = demo_conformance } },
    });

    const demo_runner = b.addModule("demo_runner", .{
        .root_source_file = b.path("src/tickoni/demo/runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance },
            .{ .name = "diagnostic", .module = demo_diagnostic },
        },
    });

    const demo_substitution = b.addModule("demo_substitution", .{
        .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic },
            .{ .name = "runner", .module = demo_runner },
        },
    });

    // Shared schema modules
    const classification = b.addModule("classification", .{
        .root_source_file = b.path("src/tickoni/schema/classification/classification.zig"),
        .target = target,
        .optimize = optimize,
    });

    const capability = b.addModule("capability", .{
        .root_source_file = b.path("src/tickoni/schema/capability/capability.zig"),
        .target = target,
        .optimize = optimize,
    });

    const thesis = b.addModule("thesis", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "classification", .module = classification },
            .{ .name = "c_abi", .module = c_abi },
        },
    });

    const catalog_schema = b.addModule("catalog_schema", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "thesis", .module = thesis } },
    });

    const catalog = b.addModule("catalog", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis },
            .{ .name = "classification", .module = classification },
            .{ .name = "catalog_schema", .module = catalog_schema },
        },
    });

    const basket = b.addModule("basket", .{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "thesis", .module = thesis },
            .{ .name = "catalog", .module = catalog },
            .{ .name = "c_abi", .module = c_abi },
        },
    });

    const portfolio = b.addModule("portfolio", .{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "basket", .module = basket } },
    });

    const fixture_portfolio = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio },
            .{ .name = "basket", .module = basket },
        },
    });

    const trade_ticket = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket },
            .{ .name = "portfolio", .module = portfolio },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio },
            .{ .name = "thesis", .module = thesis },
        },
    });

    const impact = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket },
            .{ .name = "portfolio", .module = portfolio },
        },
    });

    const cards = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket },
            .{ .name = "impact", .module = impact },
        },
    });

    const drift = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket },
            .{ .name = "c_abi", .module = c_abi },
            .{ .name = "cards", .module = cards },
        },
    });

    // Tile-local message types
    const model_messages = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mock_model = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "model_messages", .module = model_messages } },
    });

    const adapter_messages = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket },
            .{ .name = "portfolio", .module = portfolio },
            .{ .name = "trade_ticket", .module = trade_ticket },
        },
    });

    const mock_adapter = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_adapter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio },
            .{ .name = "trade_ticket", .module = trade_ticket },
            .{ .name = "adapter_messages", .module = adapter_messages },
        },
    });

    const tiles = b.addModule("tiles", .{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile },
            .{ .name = "runtime", .module = runtime },
            .{ .name = "c_abi", .module = c_abi },
            .{ .name = "util", .module = util },
            .{ .name = "logger", .module = logger },
        },
    });

    const supervisor = b.addModule("supervisor", .{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime },
            .{ .name = "tiles", .module = tiles },
            .{ .name = "c_abi", .module = c_abi },
            .{ .name = "util", .module = util },
            .{ .name = "topologies", .module = topologies_named },
            .{ .name = "logger", .module = logger },
        },
    });

    return .{
        .c_abi = c_abi,
        .util = util,
        .logger = logger,
        .runtime = runtime,
        .topologies_named = topologies_named,
        .audit_schema = audit_schema,
        .audit_codec = audit_codec,
        .fixture_audit_gen = fixture_audit_gen,
        .audit_tile = audit_tile,
        .tier = tier,
        .version = version,
        .version_opts = version_opts,
        .doctor_checks = doctor_checks,
        .doctor_output = doctor_output,
        .demo_manifest = demo_manifest,
        .demo_semver = demo_semver,
        .demo_diagnostic = demo_diagnostic,
        .demo_preflight = demo_preflight,
        .demo_cli = demo_cli,
        .demo_conformance = demo_conformance,
        .demo_comparator = demo_comparator,
        .demo_runner = demo_runner,
        .demo_substitution = demo_substitution,
        .classification = classification,
        .capability = capability,
        .thesis = thesis,
        .catalog_schema = catalog_schema,
        .catalog = catalog,
        .basket = basket,
        .portfolio = portfolio,
        .fixture_portfolio = fixture_portfolio,
        .trade_ticket = trade_ticket,
        .impact = impact,
        .cards = cards,
        .drift = drift,
        .model_messages = model_messages,
        .mock_model = mock_model,
        .adapter_messages = adapter_messages,
        .mock_adapter = mock_adapter,
        .tiles = tiles,
        .supervisor = supervisor,
    };
}

/// Create test-only tile-local modules (needed for unit/integration lanes).
pub fn testTileModules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, mod: Modules) struct {
    tkpoly_int: *std.Build.Module,
    model_int: *std.Build.Module,
    adapter_int: *std.Build.Module,
    tool_int: *std.Build.Module,
    case_int: *std.Build.Module,
    disp_int: *std.Build.Module,
    agent_int: *std.Build.Module,
    replay_int: *std.Build.Module,
    investment_audit_int: *std.Build.Module,
    investment_support_int: *std.Build.Module,
    investment_demo_test: *std.Build.Module,
    investment_demo: *std.Build.Module,
} {
    const tkpoly_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const model_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = mod.model_messages },
            .{ .name = "mock_model", .module = mod.mock_model },
            .{ .name = "c_abi", .module = mod.c_abi },
        },
    });

    const adapter_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "fixture_portfolio", .module = mod.fixture_portfolio },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
            .{ .name = "adapter_messages", .module = mod.adapter_messages },
        },
    });

    const tool_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "fixture_portfolio", .module = mod.fixture_portfolio },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const case_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const disp_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    const agent_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int },
            .{ .name = "adapter_messages", .module = mod.adapter_messages },
            .{ .name = "mock_adapter", .module = mod.mock_adapter },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "disp", .module = disp_int },
            .{ .name = "model", .module = model_int },
            .{ .name = "mock_model", .module = mod.mock_model },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int },
            .{ .name = "tool", .module = tool_int },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
            .{ .name = "capability", .module = mod.capability },
        },
    });

    const replay_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "c_abi", .module = mod.c_abi },
            .{ .name = "drift", .module = mod.drift },
            .{ .name = "model", .module = model_int },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const investment_audit_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = mod.audit_tile },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "drift", .module = mod.drift },
            .{ .name = "model", .module = model_int },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "replay", .module = replay_int },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const investment_support_int = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const investment_demo_test = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "cards", .module = mod.cards },
            .{ .name = "drift", .module = mod.drift },
            .{ .name = "impact", .module = mod.impact },
            .{ .name = "investment_support", .module = investment_support_int },
            .{ .name = "model", .module = model_int },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "replay", .module = replay_int },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int },
            .{ .name = "tool", .module = tool_int },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    const investment_demo = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int },
            .{ .name = "basket", .module = mod.basket },
            .{ .name = "cards", .module = mod.cards },
            .{ .name = "drift", .module = mod.drift },
            .{ .name = "impact", .module = mod.impact },
            .{ .name = "investment_support", .module = investment_support_int },
            .{ .name = "model", .module = model_int },
            .{ .name = "portfolio", .module = mod.portfolio },
            .{ .name = "replay", .module = replay_int },
            .{ .name = "thesis", .module = mod.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int },
            .{ .name = "tool", .module = tool_int },
            .{ .name = "trade_ticket", .module = mod.trade_ticket },
        },
    });

    return .{
        .tkpoly_int = tkpoly_int,
        .model_int = model_int,
        .adapter_int = adapter_int,
        .tool_int = tool_int,
        .case_int = case_int,
        .disp_int = disp_int,
        .agent_int = agent_int,
        .replay_int = replay_int,
        .investment_audit_int = investment_audit_int,
        .investment_support_int = investment_support_int,
        .investment_demo_test = investment_demo_test,
        .investment_demo = investment_demo,
    };
}
