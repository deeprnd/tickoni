/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run harness unit tests (separate from 'make run-unit-test'):
///   zig build test
///
/// Install Zig test binaries for kcov coverage (used by just test-cov-tk):
///   zig build cov
///
/// The existing GNUmakefile (C/Firedancer build) is unchanged.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/native/gcc/lib)") orelse "build/native/gcc/lib";
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;
    const clap_dep = b.dependency("clap", .{});
    const clap_mod = clap_dep.module("clap");

    // Shared modules used by both the exe and test binaries.
    const c_abi_mod = b.addModule("c_abi", .{
        .root_source_file = b.path("src/tickoni/c_abi/c_abi.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Generic, Tickoni-domain-free Linux utility bindings (CPU affinity,
    // clock, process primitives). No knowledge of tiles or topology.
    const util_mod = b.addModule("util", .{
        .root_source_file = b.path("src/tickoni/util/util.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const logger_mod = b.addModule("logger", .{
        .root_source_file = b.path("src/tickoni/logger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
        },
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
    // Concrete Tickoni product topologies (src/app/tickoni/topologies.zig),
    // layered on the generic runtime.topology schema. Declared here (ahead
    // of main_mod/sup_mod below) so every consumer — the exe, the
    // supervisor module, and integration tests — imports it by name
    // instead of by relative path, so the file belongs to exactly one
    // module instance.
    const topologies_named_mod = b.addModule("topologies", .{
        .root_source_file = b.path("src/app/tickoni/topologies.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = runtime_mod },
        },
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
    // ---------------------------------------------------------------------------
    // Version / doctor / demo modules — T2 scaffolding for V2.21.S3.
    // ---------------------------------------------------------------------------
    const tier_mod = b.addModule("tier", .{
        .root_source_file = b.path("src/tickoni/util/tier.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Build-time version injection via options (V1: build-time env var + git SHA)
    // Version is set via: zig build -Dversion=1.2.3-beta
    // Default is 0.1.0-dev
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

    // Git SHA from current repo HEAD
    const version_opts = b.addOptions();
    version_opts.addOption([]const u8, "BUILD_VERSION", build_version_option);
    version_opts.addOption(u16, "BUILD_VERSION_MAJOR", bv_major);
    version_opts.addOption(u16, "BUILD_VERSION_MINOR", bv_minor);
    version_opts.addOption(u16, "BUILD_VERSION_PATCH", bv_patch);
    version_opts.addOption([]const u8, "BUILD_VERSION_PRE", bv_pre);
    version_opts.addOption([]const u8, "BUILD_GIT_SHA", "unknown");
    version_opts.addOption([]const u8, "BUILD_ID", "dev-unknown");

    const version_mod = b.addModule("version", .{
        .root_source_file = b.path("src/tickoni/version.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "tier", .module = tier_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "build_options", .module = version_opts.createModule() },
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
        .imports = &.{
            .{ .name = "diagnostic", .module = demo_diagnostic_mod },
        },
    });
    const demo_comparator_mod = b.addModule("demo_comparator", .{
        .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "conformance", .module = demo_conformance_mod },
        },
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

    // ---------------------------------------------------------------------------
    // Shared schema modules — single instances used across all test lanes.
    // All cross-module imports use named imports (@import("name")) so each
    // source file belongs to exactly one module instance, eliminating the
    // "file exists in modules X and Y" build constraint.
    // ---------------------------------------------------------------------------
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
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
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
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });
    const fixture_portfolio_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });
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

    // Tile-local message types promoted to singleton modules solely so that
    // src/tickoni/test/mocks/*_mock.zig (pure test doubles, not part of a
    // tile's production surface) can reference the exact same request/response
    // types used by each tile's own Backend union, without an import cycle.
    const model_messages_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mock_model_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
        },
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

    // Supervisor executable.
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = version_mod },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "tiles", .module = tiles_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "util", .module = util_mod },
            .{ .name = "topologies", .module = topologies_named_mod },
            .{ .name = "doctor_checks", .module = doctor_checks_mod },
            .{ .name = "doctor_output", .module = doctor_output_mod },
            .{ .name = "demo_preflight", .module = demo_preflight_mod },
            .{ .name = "demo_cli", .module = demo_cli_mod },
            .{ .name = "demo_conformance", .module = demo_conformance_mod },
            .{ .name = "demo_comparator", .module = demo_comparator_mod },
            .{ .name = "demo_runner", .module = demo_runner_mod },
            .{ .name = "demo_substitution", .module = demo_substitution_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = "tickoni-supervisor",
        .root_module = main_mod,
    });
    if (target.result.os.tag == .windows) {
        exe.root_module.linkLibrary(addTickoniSupervisorShimLibrary(b, target, optimize));
        addWindowsFdManifestFixups(b, exe, b.fmt("{s}/fd_windows_zig_supervisor_link.txt", .{fd_lib_dir}));
        linkTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    } else if (target.result.cpu.arch == .aarch64) {
        // ARM64 Linux: use explicit archive paths (like Windows) to preserve link order
        // with ld.lld, and link libatomic for ARM64 CAS intrinsics.
        addTickoniCodecShim(b, exe);
        addTickoniFiredancerShims(b, exe);
        addTickoniTopoRunShims(b, exe);
        addTickoniTileRunShim(b, exe);
        linkTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
        exe.root_module.linkSystemLibrary("atomic", .{});
    } else {
        addTickoniCodecShim(b, exe);
        addTickoniFiredancerShims(b, exe);
        addTickoniTopoRunShims(b, exe);
        addTickoniTileRunShim(b, exe);
        linkTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    }
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |argv| run_exe.addArgs(argv);
    }
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // ---------------------------------------------------------------------------
    // Check step — compile-check Zig + C without full link dependencies.
    // This is what CI's lint-check-tk runs to validate syntax before the
    // full build. Only verifies that all source files parse and type-check.
    // ---------------------------------------------------------------------------
    const check_step = b.step("check", "Check Zig + C compilation without full link dependencies");

    // ---------------------------------------------------------------------------
    // Test / integration / system / coverage steps — gated behind -Dtest=1
    // so `zig build` alone never compiles test binaries (important for macOS
    // CI where we only need the exe).  Use `zig build -Dtest=true ...` to compile + run
    // them.
    // ---------------------------------------------------------------------------
    const tkpoly_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });

    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = model_messages_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });
    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "adapter_messages", .module = adapter_messages_mod },
        },
    });
    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const case_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const disp_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const agent_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "mock_adapter", .module = mock_adapter_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "mock_model", .module = mock_model_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
            .{ .name = "capability", .module = capability_mod },
        },
    });
    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = audit_tile_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    // Dedicated test instance of investment_demo_mod so that linkTickoniCodec
    // adds ballet.c only to the test binary's root module — not to the shared
    // investment_demo_mod which is also imported by system test binaries
    // (portfolio_cash_demo_test, test_investment_demo_live_test, etc.).
    const investment_demo_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "impact", .module = impact_mod },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    const investment_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = basket_mod },
            .{ .name = "cards", .module = cards_mod },
            .{ .name = "drift", .module = drift_mod },
            .{ .name = "impact", .module = impact_mod },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = trade_ticket_mod },
        },
    });
    // Diagnostic C compile-check: compiles each shim file individually and
    // prints errors to stdout (not stderr) so CI can surface them. Zig's
    // C compiler writes to stderr via --listen=- which CI captures as
    // opaque; this step forces compilation output into stdout.
    const shim_c_files = &.{
        "tango.c",
        "util.c",
        "wksp.c",
        "sandbox.c",
        "os.c",
        "topo_run.c",
        "topob.c",
        "tile_run.c",
        "ballet.c",
    };
    const shim_flags = shimCFlagsFor(target.result);
    const arch_name = switch (target.result.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .x86 => "x86",
        .arm => "arm",
        else => b.fmt("{s}", .{@tagName(target.result.cpu.arch)}),
    };
    const os_name = switch (target.result.os.tag) {
        .linux => "linux",
        .windows => "windows",
        .macos => "macos",
        else => b.fmt("{s}", .{@tagName(target.result.os.tag)}),
    };
    const abi_name = switch (target.result.abi) {
        .gnu => "gnu",
        .gnuabi64 => "gnu",
        .musl => "musl",
        .msvc => "msvc",
        else => "",
    };
    const triple = if (abi_name.len > 0)
        b.fmt("{s}-{s}-{s}", .{ arch_name, os_name, abi_name })
    else
        b.fmt("{s}-{s}", .{ arch_name, os_name });
    const c_compile_check_step = b.step("check-c-compile", "Compile-check all C shim files and print errors to stdout");
    inline for (shim_c_files) |shim_file| {
        const c_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -std=c17 -UBMI2 -ULZCNT -DFD_HAS_HOSTED=1 {s} {s} 2>&1 || true", .{
                triple,
                shim_flags[0],
                b.fmt("src/tickoni/c_abi/shim/{s}", .{shim_file}),
            }),
        });
        c_compile_check_step.dependOn(&c_check.step);
    }
    check_step.dependOn(c_compile_check_step);

    if (build_tests) {
        const investment_demo_test = b.addTest(.{ .root_module = investment_demo_test_mod });

        // ---------------------------------------------------------------------------
        // Test step — offline Tickoni unit tests only.
        // Pure logic and fixture/mock-backed proofs belong here; no running servers.
        // Run with: zig build -Dtest=true test
        // ---------------------------------------------------------------------------
        const test_step = b.step("test", "Compile offline Tickoni unit test binaries");
        const run_tests_step = b.step("run-tests", "Run offline Tickoni unit tests");
        test_step.dependOn(c_compile_check_step);
        run_tests_step.dependOn(c_compile_check_step);

        // Run all compiled test binaries sequentially via a bash script.
        // This avoids Zig's --listen=- parallel coordination which panics
        // with EndOfStream when 48+ test binaries communicate over the same pipe.
        const run_tests_cmd = std.Build.Step.Run.create(b, "run-tests");
        run_tests_cmd.addArgs(&.{ "bash", "contrib/test/run_test_series.sh" });
        run_tests_cmd.step.dependOn(test_step);
        run_tests_step.dependOn(&run_tests_cmd.step);

        // Files with no cross-module imports: standalone test binaries.
        for ([_][]const u8{
            "src/tickoni/runtime/topology.zig",
            "src/tickoni/runtime/tile.zig",
            "src/tickoni/util/cpu.zig",
            "src/tickoni/util/process.zig",
            "src/tickoni/util/tier.zig",
            "src/tickoni/util/linux_ids.zig",
            "src/tickoni/util/sizes.zig",
            "src/tickoni/util/sandbox_defaults.zig",
            "src/tickoni/runtime/sandbox.zig",
            "src/tickoni/c_abi/ballet.zig",
            "src/tickoni/c_abi/queue.zig",
            "src/tickoni/c_abi/sandbox.zig",
            "src/tickoni/c_abi/dcache.zig",
            "src/tickoni/c_abi/fseq.zig",
            "src/tickoni/c_abi/fctl.zig",
            "src/tickoni/c_abi/cnc.zig",
            "src/tickoni/c_abi/tempo.zig",
            "src/tickoni/c_abi/wksp.zig",
            "src/tickoni/c_abi/boot.zig",
            "src/tickoni/tiles/audit/mod.zig",
            "src/tickoni/tiles/payment_pipeline/mod.zig",
            "src/tickoni/tiles/case/mod.zig",
            "src/tickoni/tiles/disp/mod.zig",
        }) |path| {
            const t_mod = if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_codec", .module = audit_codec_mod },
                        .{ .name = "audit_schema", .module = audit_schema_mod },
                        .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
                    },
                })
            else if (std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_tile", .module = audit_tile_mod },
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "logger", .module = logger_mod },
                    },
                })
            else if (std.mem.eql(u8, path, "src/tickoni/runtime/sandbox.zig"))
                b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "util", .module = util_mod },
                    },
                })
            else
                b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                });
            const t = b.addTest(.{ .root_module = t_mod });
            if (std.mem.eql(u8, path, "src/tickoni/util/tier.zig")) {
                t.root_module.addCSourceFiles(.{
                    .files = &.{"src/tickoni/util/compiler_version.c"},
                });
                t.root_module.link_libc = true;
            }
            if (std.mem.eql(u8, path, "src/tickoni/tiles/audit/mod.zig")) {
                linkTickoniCodec(b, t, fd_lib_dir);
            }
            if (std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig")) {
                linkTickoniCodec(b, t, fd_lib_dir);
                // Logger module imports util -> c_abi.os which needs shim/os.c
                linkTickoniFiredancer(b, t, fd_lib_dir);
            }
            if (std.mem.eql(u8, path, "src/tickoni/c_abi/queue.zig") or
                std.mem.eql(u8, path, "src/tickoni/c_abi/dcache.zig") or
                std.mem.eql(u8, path, "src/tickoni/c_abi/fseq.zig") or
                std.mem.eql(u8, path, "src/tickoni/c_abi/fctl.zig") or
                std.mem.eql(u8, path, "src/tickoni/c_abi/cnc.zig") or
                std.mem.eql(u8, path, "src/tickoni/c_abi/tempo.zig"))
            {
                // These tests call real Firedancer substrate through the tk_ shim
                // layer, not native Zig mirrors or direct fd_* externs.
                linkTickoniFiredancer(b, t, fd_lib_dir);
            }
            if (std.mem.eql(u8, path, "src/tickoni/c_abi/ballet.zig")) {
                // siphash/pb/json primitives live in shim/ballet.c, linked via
                // linkTickoniCodec.
                linkTickoniCodec(b, t, fd_lib_dir);
            }
            // Compile from run so compiler errors are visible on CI.
            // `zig build test` only compiles; `zig build run-tests` also executes.
            test_step.dependOn(&t.step);
            run_tests_cmd.addArtifactArg(t);
        }

        // ---------------------------------------------------------------------------
        // V2.21.S3 modules — version, doctor, demo manifest, preflight (T2 scaffolding).
        // Each has its own test binary with its own import graph.
        // ---------------------------------------------------------------------------

        // version.zig imports: tier, audit_schema, build_options
        const version_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/version.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "tier", .module = tier_mod },
                    .{ .name = "audit_schema", .module = audit_schema_mod },
                    .{ .name = "build_options", .module = version_opts.createModule() },
                },
            }),
        });
        version_test.root_module.addCSourceFiles(.{
            .files = &.{"src/tickoni/util/compiler_version.c"},
        });
        version_test.root_module.link_libc = true;
        test_step.dependOn(&version_test.step);
        run_tests_cmd.addArtifactArg(version_test);

        // doctor/checks.zig — standalone (no imports beyond std)
        const doctor_checks_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&doctor_checks_test.step);
        run_tests_cmd.addArtifactArg(doctor_checks_test);

        // doctor/output.zig imports: doctor_checks
        const doctor_output_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/doctor/output.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "doctor_checks", .module = doctor_checks_mod },
                },
            }),
        });
        test_step.dependOn(&doctor_output_test.step);
        run_tests_cmd.addArtifactArg(doctor_output_test);

        // demo/manifest.zig — standalone (no cross-module imports)
        const demo_manifest_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "logger", .module = logger_mod },
                },
            }),
        });
        test_step.dependOn(&demo_manifest_test.step);
        run_tests_cmd.addArtifactArg(demo_manifest_test);

        // demo/preflight.zig imports: demo_manifest, demo_semver, tier
        const demo_preflight_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "demo_manifest", .module = demo_manifest_mod },
                    .{ .name = "demo_semver", .module = demo_semver_mod },
                    .{ .name = "diagnostic", .module = demo_diagnostic_mod },
                    .{ .name = "tier", .module = tier_mod },
                },
            }),
        });
        test_step.dependOn(&demo_preflight_test.step);
        run_tests_cmd.addArtifactArg(demo_preflight_test);

        const demo_diagnostic_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/diagnostic.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&demo_diagnostic_test.step);
        run_tests_cmd.addArtifactArg(demo_diagnostic_test);

        const demo_conformance_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "diagnostic", .module = demo_diagnostic_mod },
                },
            }),
        });
        test_step.dependOn(&demo_conformance_test.step);
        run_tests_cmd.addArtifactArg(demo_conformance_test);

        const demo_comparator_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "conformance", .module = demo_conformance_mod },
                },
            }),
        });
        test_step.dependOn(&demo_comparator_test.step);
        run_tests_cmd.addArtifactArg(demo_comparator_test);

        const demo_runner_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/runner.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "conformance", .module = demo_conformance_mod },
                    .{ .name = "diagnostic", .module = demo_diagnostic_mod },
                },
            }),
        });
        test_step.dependOn(&demo_runner_test.step);
        run_tests_cmd.addArtifactArg(demo_runner_test);

        const demo_substitution_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "diagnostic", .module = demo_diagnostic_mod },
                    .{ .name = "runner", .module = demo_runner_mod },
                },
            }),
        });
        test_step.dependOn(&demo_substitution_test.step);
        run_tests_cmd.addArtifactArg(demo_substitution_test);

        // src/tickoni/codec/thesis.zig: dedicated wrapper tests over the canonical
        // consumer-money schema hash APIs.
        const thesis_codec_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/codec/thesis.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "basket", .module = basket_mod },
                },
            }),
        });
        linkTickoniCodec(b, thesis_codec_test, fd_lib_dir);
        test_step.dependOn(&thesis_codec_test.step);
        run_tests_cmd.addArtifactArg(thesis_codec_test);

        // thesis.zig: fresh root module so linkTickoniCodec adds C sources only to
        // this binary's root module.
        const thesis_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "classification", .module = classification_mod },
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        linkTickoniCodec(b, thesis_test, fd_lib_dir);
        test_step.dependOn(&thesis_test.step);
        run_tests_cmd.addArtifactArg(thesis_test);

        const catalog_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "classification", .module = classification_mod },
                    .{ .name = "catalog_schema", .module = catalog_schema_mod },
                },
            }),
        });
        linkTickoniCodec(b, catalog_test, fd_lib_dir);
        test_step.dependOn(&catalog_test.step);
        run_tests_cmd.addArtifactArg(catalog_test);

        // logger.zig: structured, env-driven Zig logger with module filtering,
        // colors, and flush — unit tests for level parsing, module filter,
        // KV output, colorize detection, and enter/exit tracing.
        const logger_test = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/logger.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = util_mod }},
        })});
        // Link the os.c shim for C runtime calls (monotonicNanos, fflush, write, isatty).
        logger_test.root_module.addCSourceFiles(.{
            .files = &.{ "src/tickoni/c_abi/shim/os.c" },
            .flags = &.{ "-std=c17" },
        });
        logger_test.root_module.linkSystemLibrary("c", .{});
        test_step.dependOn(&logger_test.step);
        run_tests_cmd.addArtifactArg(logger_test);

        const catalog_schema_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                },
            }),
        });
        linkTickoniCodec(b, catalog_schema_test, fd_lib_dir);
        test_step.dependOn(&catalog_schema_test.step);
        run_tests_cmd.addArtifactArg(catalog_schema_test);

        const basket_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "catalog", .module = catalog_mod },
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        linkTickoniCodec(b, basket_test, fd_lib_dir);
        test_step.dependOn(&basket_test.step);
        run_tests_cmd.addArtifactArg(basket_test);

        const portfolio_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "basket", .module = basket_mod },
                },
            }),
        });
        linkTickoniCodec(b, portfolio_test, fd_lib_dir);
        test_step.dependOn(&portfolio_test.step);
        run_tests_cmd.addArtifactArg(portfolio_test);

        const fixture_portfolio_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "basket", .module = basket_mod },
                },
            }),
        });
        linkTickoniCodec(b, fixture_portfolio_test, fd_lib_dir);
        test_step.dependOn(&fixture_portfolio_test.step);
        run_tests_cmd.addArtifactArg(fixture_portfolio_test);
        const model_messages_test = b.addTest(.{ .root_module = model_messages_mod });
        test_step.dependOn(&model_messages_test.step);
        run_tests_cmd.addArtifactArg(model_messages_test);
        const mock_model_test = b.addTest(.{ .root_module = mock_model_mod });
        test_step.dependOn(&mock_model_test.step);
        run_tests_cmd.addArtifactArg(mock_model_test);

        // link handle/type roots keep their own unit tests independent of the
        // aggregate runtime module.
        const link_handles_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/link/handles.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&link_handles_test.step);
        run_tests_cmd.addArtifactArg(link_handles_test);

        const link_types_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/link/types.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&link_types_test.step);
        run_tests_cmd.addArtifactArg(link_types_test);

        // boot.zig imports c_abi for the raw fd_boot bridge call.
        const boot_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/boot.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        test_step.dependOn(&boot_test.step);
        run_tests_cmd.addArtifactArg(boot_test);

        // cnc_counters.zig imports c_abi and calls the real tk_cnc_app_laddr
        // shim (via c_abi.cnc.appLaddr) in its round-trip test.
        const cnc_counters_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/cnc_counters.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        linkTickoniFiredancer(b, cnc_counters_test, fd_lib_dir);
        test_step.dependOn(&cnc_counters_test.step);
        run_tests_cmd.addArtifactArg(cnc_counters_test);

        // cpu_placement.zig imports util (for the CpuSet primitive) alongside
        // its sibling topology.zig.
        const cpu_placement_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "util", .module = util_mod },
                },
            }),
        });
        test_step.dependOn(&cpu_placement_test.step);
        run_tests_cmd.addArtifactArg(cpu_placement_test);

        // launch_spec.zig embeds link.LinkHandles, which imports c_abi.
        const launch_spec_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/launch_spec.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        test_step.dependOn(&launch_spec_test.step);
        run_tests_cmd.addArtifactArg(launch_spec_test);

        // topology_spec.zig (v2.14.S8.T4): small tiles+channels round-trip,
        // same import needs as launch_spec.zig.
        const topology_spec_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/topology_spec.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        test_step.dependOn(&topology_spec_test.step);
        run_tests_cmd.addArtifactArg(topology_spec_test);

        // topo_run.zig (v2.14.S8.T3/T4): fd_topo_run_tile adapter plus the
        // simple process-mode launcher dispatch contract. Tests assert Linux
        // stays on upstream fd_topo_run_tile while non-Linux falls back to the
        // Tickoni shim, so this target links both topo_run.c and tile_run.c
        // plus a tiny C file providing no-op callback stubs for TK_TILE_RUN.
        const topo_run_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/c_abi/topo_run.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const _topo_test_target = topo_run_test.root_module.resolved_target.?.result;
        topo_run_test.root_module.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/tile_run_test_stubs.c"},
            .flags = shimCFlagsFor(_topo_test_target),
        });
        linkTickoniFiredancer(b, topo_run_test, fd_lib_dir);
        linkTickoniTopoRun(b, topo_run_test, fd_lib_dir);
        linkTickoniTileRun(b, topo_run_test, fd_lib_dir);
        test_step.dependOn(&topo_run_test.step);
        run_tests_cmd.addArtifactArg(topo_run_test);

        // topob.zig (v2.14.S8.T12): fd_topob topology builder. Same
        // no-test-blocks-yet rationale as topo_run_test above; proves the
        // shim (including Tickoni's own object-callbacks array) compiles and
        // links.
        const topob_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/c_abi/topob.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        linkTickoniFiredancer(b, topob_test, fd_lib_dir);
        linkTickoniTopoRun(b, topob_test, fd_lib_dir);
        test_step.dependOn(&topob_test.step);
        run_tests_cmd.addArtifactArg(topob_test);

        // topo_build.zig (v2.14.S8.T12): shared topology-builder, actually
        // calls into topob.zig against a real 8-tile-shaped Topology, so
        // needs the same c_abi + util imports as cpu_placement_test plus the
        // Firedancer/topo-adapter link surface.
        const topo_build_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/runtime/topo_build.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "c_abi", .module = c_abi_mod },
                    .{ .name = "util", .module = util_mod },
                },
            }),
        });
        linkTickoniFiredancer(b, topo_build_test, fd_lib_dir);
        linkTickoniTopoRun(b, topo_build_test, fd_lib_dir);
        test_step.dependOn(&topo_build_test.step);
        run_tests_cmd.addArtifactArg(topo_build_test);

        // model tile: unit tests are mock/fixture-backed and must not start servers.
        const model_test_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = model_messages_mod },
                .{ .name = "mock_model", .module = mock_model_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        });
        // model/mod.zig: fresh root module so linkTickoniCodec adds C sources
        // only to this binary's root module, not to the shared model_test_mod
        // reused as an import by other test artifacts (agent_test etc.).
        const model_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "model_messages", .module = model_messages_mod },
                    .{ .name = "mock_model", .module = mock_model_mod },
                    .{ .name = "c_abi", .module = c_abi_mod },
                },
            }),
        });
        linkTickoniCodec(b, model_test, fd_lib_dir);
        test_step.dependOn(&model_test.step);
        run_tests_cmd.addArtifactArg(model_test);

        const tkpoly_test_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
            },
        });
        const adapter_test_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
                .{ .name = "adapter_messages", .module = adapter_messages_mod },
            },
        });
        const adapter_test = b.addTest(.{
            .root_module = adapter_test_mod,
        });
        test_step.dependOn(&adapter_test.step);
        run_tests_cmd.addArtifactArg(adapter_test);
        const mock_adapter_test = b.addTest(.{ .root_module = mock_adapter_mod });
        test_step.dependOn(&mock_adapter_test.step);
        run_tests_cmd.addArtifactArg(mock_adapter_test);

        // trade_ticket.zig imports basket, portfolio, fixture_portfolio, and thesis.
        const trade_ticket_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                    .{ .name = "thesis", .module = thesis_mod },
                },
            }),
        });
        linkTickoniCodec(b, trade_ticket_test, fd_lib_dir);
        test_step.dependOn(&trade_ticket_test.step);
        run_tests_cmd.addArtifactArg(trade_ticket_test);

        // impact.zig: portfolio and cash impact model (V1.3.S1).
        const impact_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                },
            }),
        });
        linkTickoniCodec(b, impact_test, fd_lib_dir);
        test_step.dependOn(&impact_test.step);
        run_tests_cmd.addArtifactArg(impact_test);

        // cards.zig: thesis and money proposal card schemas (V1.3.S2).
        const cards_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "impact", .module = impact_mod },
                },
            }),
        });
        linkTickoniCodec(b, cards_test, fd_lib_dir);
        test_step.dependOn(&cards_test.step);
        run_tests_cmd.addArtifactArg(cards_test);

        // drift.zig: drift conditions, assessment, and suggestion generation (V1.3.S3).
        const drift_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "c_abi", .module = c_abi_mod },
                    .{ .name = "cards", .module = cards_mod },
                },
            }),
        });
        linkTickoniCodec(b, drift_test, fd_lib_dir);
        test_step.dependOn(&drift_test.step);
        run_tests_cmd.addArtifactArg(drift_test);

        const allowed_trade_fixture_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_allowed_trade.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                },
            }),
        });
        linkTickoniCodec(b, allowed_trade_fixture_test, fd_lib_dir);
        test_step.dependOn(&allowed_trade_fixture_test.step);
        run_tests_cmd.addArtifactArg(allowed_trade_fixture_test);

        const denied_trade_fixture_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_denied_trade.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "basket", .module = basket_mod },
                },
            }),
        });
        linkTickoniCodec(b, denied_trade_fixture_test, fd_lib_dir);
        test_step.dependOn(&denied_trade_fixture_test.step);
        run_tests_cmd.addArtifactArg(denied_trade_fixture_test);

        const tool_test_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_test_mod },
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                .{ .name = "trade_ticket", .module = trade_ticket_mod },
            },
        });
        const tool_test = b.addTest(.{ .root_module = tool_test_mod });
        test_step.dependOn(&tool_test.step);
        run_tests_cmd.addArtifactArg(tool_test);

        const disp_unit_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
            .target = target,
            .optimize = optimize,
        });
        const agent_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/tiles/agent/mod.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = adapter_test_mod },
                    .{ .name = "mock_adapter", .module = mock_adapter_mod },
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "disp", .module = disp_unit_mod },
                    .{ .name = "model", .module = model_test_mod },
                    .{ .name = "mock_model", .module = mock_model_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "tkpoly", .module = tkpoly_test_mod },
                    .{ .name = "tool", .module = tool_test_mod },
                    .{ .name = "trade_ticket", .module = trade_ticket_mod },
                    .{ .name = "capability", .module = capability_mod },
                },
            }),
        });
        linkTickoniCodec(b, agent_test, fd_lib_dir);
        test_step.dependOn(&agent_test.step);
        run_tests_cmd.addArtifactArg(agent_test);

        const replay_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = adapter_test_mod },
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "c_abi", .module = c_abi_mod },
                    .{ .name = "drift", .module = drift_mod },
                    .{ .name = "model", .module = model_test_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "tkpoly", .module = tkpoly_test_mod },
                    .{ .name = "trade_ticket", .module = trade_ticket_mod },
                },
            }),
        });
        linkTickoniCodec(b, replay_test, fd_lib_dir);
        test_step.dependOn(&replay_test.step);
        run_tests_cmd.addArtifactArg(replay_test);

        // supervisor.zig imports runtime, tiles, and c_abi modules.
        const sup_mod = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "tiles", .module = tiles_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "util", .module = util_mod },
                .{ .name = "topologies", .module = topologies_named_mod },
                .{ .name = "logger", .module = logger_mod },
            },
        });
        // Named module (vs. sup_mod's anonymous instance above) so
        // src/tickoni/test/integration process-mode tests can import the
        // Supervisor type without a cross-tree relative path.
        const supervisor_named_mod = b.addModule("supervisor", .{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "tiles", .module = tiles_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "util", .module = util_mod },
                .{ .name = "topologies", .module = topologies_named_mod },
                .{ .name = "logger", .module = logger_mod },
            },
        });
        const sup_test = b.addTest(.{ .root_module = sup_mod });
        linkTickoniCodec(b, sup_test, fd_lib_dir);
        // supervisor.zig now calls into tile_registry.zig's `entries` array
        // (v2.14.S8.T1), which embeds every tile's process-mode function
        // pointer (including tiles.process/rt.link/c_abi callers) as static
        // data even for tests that only exercise thread mode — needs the same
        // Firedancer link set as the process-mode integration tests.
        linkTickoniFiredancer(b, sup_test, fd_lib_dir);
        test_step.dependOn(&sup_test.step);
        run_tests_cmd.addArtifactArg(sup_test);

        // tile_registry.zig (v2.14.S8.T1): single source of truth for tile id
        // -> behavior, imported by supervisor.zig and tile_main.zig. Same
        // import set as sup_mod since it needs the same tile-identity types.
        const tile_registry_mod = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/tile_registry.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "tiles", .module = tiles_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        });
        const tile_registry_test = b.addTest(.{ .root_module = tile_registry_mod });
        linkTickoniCodec(b, tile_registry_test, fd_lib_dir);
        linkTickoniFiredancer(b, tile_registry_test, fd_lib_dir);
        test_step.dependOn(&tile_registry_test.step);
        run_tests_cmd.addArtifactArg(tile_registry_test);

        // topologies.zig: fresh root module (not the shared topologies_named_mod)
        // so it gets its own dedicated test run, since named-import module
        // boundaries do not propagate test discovery to importers.
        const topologies_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/app/tickoni/topologies.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "runtime", .module = runtime_mod },
                },
            }),
        });
        test_step.dependOn(&topologies_test.step);
        run_tests_cmd.addArtifactArg(topologies_test);

        // ---------------------------------------------------------------------------
        // V2.22.S7 evidence module — standalone (only imports std).
        // Run with: zig build test
        // ---------------------------------------------------------------------------
        const evidence_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/evidence/mod.zig"),
            .target = target,
            .optimize = optimize,
        });
        const evidence_test = b.addTest(.{
            .root_module = evidence_mod,
        });
        test_step.dependOn(&evidence_test.step);
        run_tests_cmd.addArtifactArg(evidence_test);

        // ---------------------------------------------------------------------------
        // Integration-test step — transport and boundary wiring against local mocks.
        // Local mock HTTP servers live here; this lane must stay deterministic.
        // Run with: zig build integration-test
        // ---------------------------------------------------------------------------
        const integration_step = b.step("integration-test", "Run Tickoni mock-backed integration tests");

        // Schema modules are shared (thesis_mod, basket_mod, portfolio_mod, etc.).
        // Integration tile modules are fresh instances so they don't inherit any
        // C source additions from the unit test lane.
        linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
        test_step.dependOn(&investment_demo_test.step);
        for ([_][]const u8{
            "src/tickoni/test/integration/test_investment_allowed_trade.zig",
            "src/tickoni/test/integration/test_investment_blocked_limits.zig",
            "src/tickoni/test/integration/test_investment_restricted_instrument.zig",
            "src/tickoni/test/integration/test_investment_input_policy_denials.zig",
        }) |path| {
            const integration_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path(path),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "adapter", .module = adapter_int_mod },
                        .{ .name = "audit_tile", .module = audit_tile_mod },
                        .{ .name = "basket", .module = basket_mod },
                        .{ .name = "investment_audit", .module = investment_audit_int_mod },
                        .{ .name = "investment_support", .module = investment_support_int_mod },
                        .{ .name = "model", .module = model_int_mod },
                        .{ .name = "portfolio", .module = portfolio_mod },
                        .{ .name = "replay", .module = replay_int_mod },
                        .{ .name = "thesis", .module = thesis_mod },
                        .{ .name = "tkpoly", .module = tkpoly_int_mod },
                        .{ .name = "tool", .module = tool_int_mod },
                        .{ .name = "trade_ticket", .module = trade_ticket_mod },
                        .{ .name = "tkcase", .module = case_int_mod },
                        .{ .name = "tkdisp", .module = disp_int_mod },
                        .{ .name = "tkagnt", .module = agent_int_mod },
                    },
                }),
            });
            linkTickoniCodec(b, integration_test, fd_lib_dir);
            integration_step.dependOn(&b.addRunArtifact(integration_test).step);
        }

        // Shared by every process-mode integration test below: each self-execs
        // zig-out/bin/tickoni-supervisor per tile (see
        // ProcessPipelineConfig.tile_exe_path). One shared install step, not
        // one addInstallArtifact(exe, .{}) call per test — three separate
        // install actions targeting the same destination file were the prime
        // suspect for a hang where one test's install raced another test's
        // already-spawned children exec'ing that same path.
        const process_mode_exe_install = b.addInstallArtifact(exe, .{});

        if (target.result.os.tag == .linux) {
            // v2.14.S1 process-mode payment pipeline: spawns real supervisor-managed
            // tile processes over Firedancer Tango shared memory. Tickoni internals
            // run for real; the "external tool" substituted per
            // doc/execution/testing-tickoni.md's integration-lane rule is the
            // operator-managed host workspace path, replaced by a scratch
            // FD_SHMEM_PATH directory under zig-cache/tmp. No huge pages or sudo.
            // Retail targets intentionally exclude these tests because the product
            // tier contract disables shared-memory topology outside linux_full.
            const process_pipeline_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_pipeline.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_pipeline_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_pipeline_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_pipeline_test, fd_lib_dir);
            const run_process_pipeline_test = addPlainTestRun(b, process_pipeline_test);
            run_process_pipeline_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_pipeline_test.step);

            // v2.14.S1 M5: explicit shared-core CPU placement and the
            // CPU-unavailable fail-closed path, both through the real supervisor.
            const process_cpu_placement_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_cpu_placement_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_cpu_placement_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_cpu_placement_test, fd_lib_dir);
            const run_process_cpu_placement_test = addPlainTestRun(b, process_cpu_placement_test);
            run_process_cpu_placement_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_cpu_placement_test.step);

            const process_cpu_placement_linux_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement_linux.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_cpu_placement_linux_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_cpu_placement_linux_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_cpu_placement_linux_test, fd_lib_dir);
            const run_process_cpu_placement_linux_test = addPlainTestRun(b, process_cpu_placement_linux_test);
            run_process_cpu_placement_linux_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_cpu_placement_linux_test.step);
            // v2.14.S1 M6: process isolation (T13: one OS process per tile,
            // parented by the supervisor), crash isolation (T12: SIGKILL one
            // tile, siblings unaffected), and the remaining process-mode
            // fail-closed configuration checks.
            const process_topology_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_topology.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_topology_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_topology_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_topology_test, fd_lib_dir);
            const run_process_topology_test = addPlainTestRun(b, process_topology_test);
            run_process_topology_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_topology_test.step);

            const process_topology_linux_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_topology_linux.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_topology_linux_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_topology_linux_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_topology_linux_test, fd_lib_dir);
            const run_process_topology_linux_test = addPlainTestRun(b, process_topology_linux_test);
            run_process_topology_linux_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_topology_linux_test.step);
            // v2.14.S1 M6: demo/replay parity — floating vs. explicit shared-core
            // CPU placement must reach identical final pipeline metrics through the
            // real supervisor (T14).
            const process_demo_parity_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_demo_parity.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = topologies_named_mod },
                    },
                }),
            });
            linkTickoniCodec(b, process_demo_parity_test, fd_lib_dir);
            linkTickoniFiredancer(b, process_demo_parity_test, fd_lib_dir);
            linkTickoniTopoRun(b, process_demo_parity_test, fd_lib_dir);
            const run_process_demo_parity_test = addPlainTestRun(b, process_demo_parity_test);
            run_process_demo_parity_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_demo_parity_test.step);

            // v2.14.S1 M6: runtime link fail-closed matrix (dcache bounds, missing link
            // objects) and backpressure visibility. Single-process — no tile spawn,
            // so no stdio-inheritance hang risk — uses the normal test-runner path.
            const link_bounds_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_link_bounds.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "util", .module = util_mod },
                    },
                }),
            });
            linkTickoniCodec(b, link_bounds_test, fd_lib_dir);
            linkTickoniFiredancer(b, link_bounds_test, fd_lib_dir);
            integration_step.dependOn(&b.addRunArtifact(link_bounds_test).step);
        }

        // Mock HTTP servers (test/mocks): self-tests of the mock
        // infrastructure itself, no tile schema imports required. Wired to
        // test_step (not integration_step): src/tickoni/test/integration is the
        // integration-test boundary, and this root lives under test/mocks.
        const mock_http_support_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_http_support.zig"),
            .target = target,
            .optimize = optimize,
        });
        const mock_broker_market_server_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_broker_market_server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
            },
        });
        const mock_openai_server_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_openai_server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mock_http_support", .module = mock_http_support_mod },
            },
        });
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
        test_step.dependOn(&mock_servers_test.step);

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

        const replay_integration_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tickoni/test/integration/test_investment_replay.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "adapter", .module = adapter_int_mod },
                    .{ .name = "audit_tile", .module = audit_tile_mod },
                    .{ .name = "basket", .module = basket_mod },
                    .{ .name = "investment_demo", .module = investment_demo_mod },
                    .{ .name = "investment_audit", .module = investment_audit_int_mod },
                    .{ .name = "investment_support", .module = investment_support_int_mod },
                    .{ .name = "model", .module = model_int_mod },
                    .{ .name = "portfolio", .module = portfolio_mod },
                    .{ .name = "replay", .module = replay_int_mod },
                    .{ .name = "thesis", .module = thesis_mod },
                    .{ .name = "tkpoly", .module = tkpoly_int_mod },
                    .{ .name = "tool", .module = tool_int_mod },
                    .{ .name = "trade_ticket", .module = trade_ticket_mod },
                    .{ .name = "tkcase", .module = case_int_mod },
                    .{ .name = "tkdisp", .module = disp_int_mod },
                    .{ .name = "tkagnt", .module = agent_int_mod },
                },
            }),
        });
        // Imported modules do not propagate their root-module link settings to
        // this test binary. Reuse the codec seam directly so Windows links the
        // concrete archives instead of invoking pkg-config for fd_ballet/fd_util.
        linkTickoniCodec(b, replay_integration_test, fd_lib_dir);
        integration_step.dependOn(&b.addRunArtifact(replay_integration_test).step);

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
        linkTickoniCodec(b, decision_cards_integration_test, fd_lib_dir);
        integration_step.dependOn(&b.addRunArtifact(decision_cards_integration_test).step);

        // System step — every root under src/tickoni/test/system, run with
        // `zig build system-test` (`just test-system-tk`). This includes both the
        // live `tkmodl` smoke proof and offline deterministic demo proofs; the
        // directory is the boundary, not per-file live/offline status.
        const system_step = b.step("system-test", "Run all src/tickoni/test/system proofs");
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
        linkTickoniCodec(b, system_test, fd_lib_dir);
        const run_system_test = addPlainTestRun(b, system_test);
        system_step.dependOn(&run_system_test.step);

        // V1.3.S4: combined portfolio/cash demo. Fixture-backed and deterministic
        // (no live model, broker, or execution), but lives under
        // src/tickoni/test/system so it runs as part of the system-test lane
        // alongside the live tkmodl proof.
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
        // Imported modules do not carry their root-module C/link settings into
        // this test binary, so wire the codec seam explicitly here too.
        linkTickoniCodec(b, portfolio_cash_demo_test, fd_lib_dir);
        const run_portfolio_cash_demo_test = addPlainTestRun(b, portfolio_cash_demo_test);
        system_step.dependOn(&run_portfolio_cash_demo_test.step);

        // Compatibility alias for the old live-model smoke command.
        const live_model_step = b.step("integration-test-live-model", "Alias for the live V1.1 system/demo lane");
        live_model_step.dependOn(system_step);
    }

    const cli_main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni_cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "investment_demo", .module = investment_demo_mod },
            .{ .name = "tier", .module = tier_mod },
            .{ .name = "doctor_output", .module = doctor_output_mod },
            .{ .name = "demo_manifest", .module = demo_manifest_mod },
            .{ .name = "demo_preflight", .module = demo_preflight_mod },
            .{ .name = "version", .module = version_mod },
        },
    });
    const cli_exe = b.addExecutable(.{
        .name = "tickoni",
        .root_module = cli_main_mod,
    });
    cli_exe.root_module.addCSourceFiles(.{
        .files = &.{"src/tickoni/util/compiler_version.c"},
    });
    if (target.result.os.tag == .windows) {
        cli_exe.root_module.linkLibrary(addTickoniCodecShimLibrary(b, target, optimize, "tickoni-codec-shims"));
        addWindowsFdManifestFixups(b, cli_exe, b.fmt("{s}/fd_windows_zig_codec_link.txt", .{fd_lib_dir}));
        linkTickoniSystemLibraries(b, cli_exe, fd_lib_dir, &.{ "fd_ballet", "fd_util" });
        // crypt32 is a Windows system library, not a pkg-config dependency.
        cli_exe.root_module.linkSystemLibrary("crypt32", .{ .use_pkg_config = .no });
    } else {
        linkTickoniCodec(b, cli_exe, fd_lib_dir);
    }
    b.installArtifact(cli_exe);

    const run_cli = b.addRunArtifact(cli_exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |argv| run_cli.addArgs(argv);
    }
    const run_cli_step = b.step("run-cli", "Run tickoni demo CLI");
    run_cli_step.dependOn(&run_cli.step);

    // ---------------------------------------------------------------------------
    // Coverage step — install test binaries to zig-out/cov/ for kcov
    // Run with: zig build cov
    // Then: bash contrib/coverage.sh coverage-tk
    // ---------------------------------------------------------------------------
    const cov_step = b.step("cov", "Install Zig test binaries to zig-out/cov/ for kcov coverage");

    for ([_][2][]const u8{
        .{ "test-topology", "src/tickoni/runtime/topology.zig" },
        .{ "test-tile", "src/tickoni/runtime/tile.zig" },
        .{ "test-queue", "src/tickoni/c_abi/queue.zig" },
        .{ "test-sandbox", "src/tickoni/c_abi/sandbox.zig" },
        .{ "test-dcache", "src/tickoni/c_abi/dcache.zig" },
        .{ "test-fseq", "src/tickoni/c_abi/fseq.zig" },
        .{ "test-fctl", "src/tickoni/c_abi/fctl.zig" },
        .{ "test-cnc", "src/tickoni/c_abi/cnc.zig" },
        .{ "test-tempo", "src/tickoni/c_abi/tempo.zig" },
        .{ "test-wksp", "src/tickoni/c_abi/wksp.zig" },
        .{ "test-cpu", "src/tickoni/util/cpu.zig" },
        .{ "test-cpu-placement", "src/tickoni/runtime/cpu_placement.zig" },
        .{ "test-process", "src/tickoni/util/process.zig" },
        .{ "test-sandbox-config", "src/tickoni/runtime/sandbox.zig" },
        .{ "test-cnc-counters", "src/tickoni/runtime/cnc_counters.zig" },
        .{ "test-audit", "src/tickoni/tiles/audit/mod.zig" },
        .{ "test-payment-pipeline", "src/tickoni/tiles/payment_pipeline/mod.zig" },
        .{ "test-case", "src/tickoni/tiles/case/mod.zig" },
        .{ "test-disp", "src/tickoni/tiles/disp/mod.zig" },
    }) |entry| {
        const t = b.addTest(.{
            .name = entry[0],
            .root_module = if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_codec", .module = audit_codec_mod },
                        .{ .name = "audit_schema", .module = audit_schema_mod },
                        .{ .name = "fixture_audit_gen", .module = fixture_audit_gen_mod },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_tile", .module = audit_tile_mod },
                        .{ .name = "runtime", .module = runtime_mod },
                        .{ .name = "c_abi", .module = c_abi_mod },
                        .{ .name = "logger", .module = logger_mod },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/cnc_counters.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "c_abi", .module = c_abi_mod },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/cpu_placement.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "util", .module = util_mod },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/sandbox.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "util", .module = util_mod },
                    },
                })
            else
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                }),
        });
        if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/audit/mod.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline/mod.zig"))
        {
            linkTickoniCodec(b, t, fd_lib_dir);
            // Logger imports util -> c_abi.os which needs shim/os.c
            linkTickoniFiredancer(b, t, fd_lib_dir);
        }
        if (std.mem.eql(u8, entry[1], "src/tickoni/c_abi/queue.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/dcache.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/fseq.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/fctl.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/cnc.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/tempo.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/runtime/cnc_counters.zig"))
        {
            linkTickoniFiredancer(b, t, fd_lib_dir);
        }
        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    const thesis_cov_test = b.addTest(.{
        .name = "test-thesis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "classification", .module = classification_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    linkTickoniCodec(b, thesis_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(thesis_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const catalog_cov_test = b.addTest(.{
        .name = "test-catalog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "classification", .module = classification_mod },
                .{ .name = "catalog_schema", .module = catalog_schema_mod },
            },
        }),
    });
    linkTickoniCodec(b, catalog_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(catalog_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const catalog_schema_cov_test = b.addTest(.{
        .name = "test-catalog-schema",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, catalog_schema_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(catalog_schema_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const portfolio_cov_test = b.addTest(.{
        .name = "test-portfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, portfolio_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(portfolio_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const fixture_portfolio_cov_test = b.addTest(.{
        .name = "test-portfolio-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "basket", .module = basket_mod },
            },
        }),
    });
    linkTickoniCodec(b, fixture_portfolio_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(fixture_portfolio_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const trade_ticket_cov_test = b.addTest(.{
        .name = "test-trade-ticket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
                .{ .name = "fixture_portfolio", .module = fixture_portfolio_mod },
                .{ .name = "thesis", .module = thesis_mod },
            },
        }),
    });
    linkTickoniCodec(b, trade_ticket_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(trade_ticket_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const impact_cov_test = b.addTest(.{
        .name = "test-impact",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = basket_mod },
                .{ .name = "portfolio", .module = portfolio_mod },
            },
        }),
    });
    linkTickoniCodec(b, impact_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(impact_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const basket_cov_test = b.addTest(.{
        .name = "test-basket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = thesis_mod },
                .{ .name = "catalog", .module = catalog_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
            },
        }),
    });
    linkTickoniCodec(b, basket_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(basket_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const sup_cov_test = b.addTest(.{
        .name = "test-supervisor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
                .{ .name = "tiles", .module = tiles_mod },
                .{ .name = "c_abi", .module = c_abi_mod },
                .{ .name = "util", .module = util_mod },
                .{ .name = "topologies", .module = topologies_named_mod },
                .{ .name = "logger", .module = logger_mod },
            },
        }),
    });
    linkTickoniCodec(b, sup_cov_test, fd_lib_dir);
    linkTickoniFiredancer(b, sup_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(sup_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const topologies_cov_test = b.addTest(.{
        .name = "test-topologies",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/topologies.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = runtime_mod },
            },
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(topologies_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}
/// b.addRunArtifact on a test binary always enables Zig's test-server
/// protocol (--listen=- plus .stdio = .zig_test), which communicates with
/// the build runner over the test binary's own stdin/stdout. A test that
/// spawns real child OS processes (v2.14 process-mode tests) risks those
/// children inheriting that stdout descriptor, which keeps the pipe's
/// write end open after the test itself finishes and hangs the build
/// runner waiting for EOF that never arrives. This builds the Run step by
/// hand instead, skipping std.Build.addRunArtifact's
/// enableTestRunnerMode call entirely (plain argv + exit-code check, real
/// stdio inherited, no IPC protocol for a spawned process to interfere
/// with).
fn addPlainTestRun(b: *std.Build, test_compile: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run_step = std.Build.Step.Run.create(b, b.fmt("run {s} (plain)", .{test_compile.name}));
    run_step.producer = test_compile;
    run_step.addArtifactArg(test_compile);
    run_step.has_side_effects = true;
    return run_step;
}

/// Links the Firedancer substrate used by Tickoni runtime wrappers. Tickoni
/// code crosses Firedancer only through src/tickoni/c_abi/shim/**, so this
/// compiles the required Tickoni-owned shim files alongside upstream libs.
fn shimCFlagsFor(target: std.Target) []const []const u8 {
    return switch (target.os.tag) {
        .linux => &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_LINUX=1" },
        .macos => &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_MACOS=1" },
        .windows => switch (target.cpu.arch) {
            .aarch64 => &.{
                "-std=c17",                  "-U__BMI2__",        "-U__LZCNT__",       "-DFD_HAS_HOSTED=1",  "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",   "-DFD_LOG_STYLE=1",  "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_ARM64=1",          "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1",  "-Wno-format",
                "-Wno-format-extra-args",
            },
            .x86_64 => &.{
                "-std=c17",                  "-U__BMI2__",        "-U__LZCNT__",       "-DFD_HAS_HOSTED=1",  "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",   "-DFD_LOG_STYLE=1",  "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_X86=1",            "-DFD_HAS_SSE=1",    "-DFD_HAS_AVX=1",    "-DFD_HAS_AVX2=1",    "-DFD_HAS_AESNI=1",
                "-DFD_IS_X86_64=1",          "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1",  "-Wno-format",
                "-Wno-format-extra-args",
            },
            else => &.{
                "-std=c17",                  "-U__BMI2__",             "-U__LZCNT__",      "-DFD_HAS_HOSTED=1",  "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",        "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-Wno-format",               "-Wno-format-extra-args",
            },
        },
        else => &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1" },
    };
}

fn linkTickoniFiredancer(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniFiredancerShims(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        linkTickoniWindowsUuid(b, step, fd_lib_dir);
        // Windows doesn't have pkg-config, so use link_libcpp instead of
        // linkSystemLibrary("stdc++", .{}) which would invoke pkg-config.
        step.root_module.link_libcpp = true;
        return;
    }
    linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_tango", "fd_util" });
}

fn addTickoniFiredancerShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/util.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
        },
        .flags = shimCFlagsFor(target_info),
    });
}

fn linkTickoniWindowsUuid(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;
    // Windows FD archives carry a libuuid.a default-library reference. The
    // FD build creates this compatibility archive from libuuid_stub.c; add
    // the archive explicitly for every Windows link.
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libuuid.a", .{fd_lib_dir}) });
}

fn linkTickoniSystemLibraries(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8, libs: []const []const u8) void {
    step.root_module.addLibraryPath(b.path(fd_lib_dir));
    const os_tag = step.root_module.resolved_target.?.result.os.tag;
    const cpu_arch = step.root_module.resolved_target.?.result.cpu.arch;
    if (os_tag == .windows or (os_tag == .linux and cpu_arch == .aarch64)) {
        // Windows and ARM64 Linux: use explicit archive paths. On Windows this avoids
        // pkg-config.BAT probing; on ARM64 Linux it preserves link order with ld.lld,
        // which is required because fd_sandbox_* symbols from libfd_util.a must be
        // resolved after the shim wrappers in sandbox.c reference them.
        for (libs) |lib| {
            step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.a", .{ fd_lib_dir, lib }) });
        }
        linkTickoniWindowsUuid(b, step, fd_lib_dir);
        step.root_module.link_libcpp = true;
    } else {
        for (libs) |lib| step.root_module.linkSystemLibrary(lib, .{});
        step.root_module.linkSystemLibrary("stdc++", .{});
    }
}

/// Links shim/topo_run.c (the fd_topo_run_tile adapter, v2.14.S8.T3) and
/// shim/topob.c (the fd_topob topology builder, v2.14.S8.T12) — the two
/// halves of Tickoni's Firedancer topology adapter, same link surface.
/// Callers must also call linkTickoniFiredancer (tango/util) — this only
/// adds the additional disco/ballet/waltz link surface these files and
/// their callees (fd_metrics, fd_event_report, both compiled into
/// fd_disco) need, following the same link set as
/// src/disco/topo/Local.mk's own test_topob unit test.
fn linkTickoniTopoRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniTopoRunShims(b, step);
    linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

fn addTickoniTopoRunShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;

    const topo_run_platform_file = switch (target_info.os.tag) {
        .macos => "src/tickoni/c_abi/shim/topo_run_platform_macos.c",
        .windows => "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        else => "src/tickoni/c_abi/shim/topo_run_platform_linux.c",
    };

    step.root_module.addCSourceFiles(.{
        .files = &.{ "src/tickoni/c_abi/shim/topo_run.c", topo_run_platform_file, "src/tickoni/c_abi/shim/topob.c" },
        .flags = shimCFlagsFor(target_info),
    });
}

/// Links shim/tile_run.c (v2.14.S8.T4's fd_topo_run_tile_t wiring).
/// Deliberately separate from linkTickoniTopoRun: this file's static
/// TK_TILE_RUN struct references tk_tile_privileged_init/tk_tile_run,
/// Zig `export fn`s defined only in runtime/tile_process.zig, so only
/// call this for targets that also link tile_process.zig (the exe and
/// the process-mode integration tests) — never for topo_run.c/topob.c's
/// own standalone adapter unit tests, which don't include
/// tile_process.zig and would fail to link if this were folded into
/// linkTickoniTopoRun instead. Callers must also call
/// linkTickoniFiredancer and linkTickoniTopoRun.
fn linkTickoniTileRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniTileRunShim(b, step);
    linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

fn addTickoniTileRunShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{"src/tickoni/c_abi/shim/tile_run.c"},
        .flags = shimCFlagsFor(target_info),
    });
}

fn addTickoniShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    files: []const []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = files,
        .flags = shimCFlagsFor(target.result),
    });
    if (target.result.os.tag == .windows) {
        mod.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/windows_crt.c"},
            .flags = shimCFlagsFor(target.result),
        });
    }
    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });
}

fn addTickoniSupervisorShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, "tickoni-supervisor-shims", &.{
        "src/tickoni/c_abi/shim/ballet.c",
        "src/tickoni/c_abi/shim/tango.c",
        "src/tickoni/c_abi/shim/util.c",
        "src/tickoni/c_abi/shim/wksp.c",
        "src/tickoni/c_abi/shim/sandbox.c",
        "src/tickoni/c_abi/shim/os.c",
        "src/tickoni/c_abi/shim/topo_run.c",
        "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        "src/tickoni/c_abi/shim/topob.c",
        "src/tickoni/c_abi/shim/tile_run.c",
    });
}

fn addTickoniCodecShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, name, &.{
        "src/tickoni/c_abi/shim/ballet.c",
    });
}

fn addWindowsFdManifestFixups(b: *std.Build, step: *std.Build.Step.Compile, manifest_path: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag != .windows) return;

    // Read and apply Windows FD manifest fixups
    var threaded = std.Io.Threaded.init_single_threaded;
    const manifest = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        manifest_path,
        b.allocator,
        .limited(1024 * 1024),
    ) catch @panic("missing Windows FD Zig link manifest; run just build-fd first");
    defer b.allocator.free(manifest);

    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        step.root_module.addObjectFile(.{ .cwd_relative = trimmed });
    }
}

/// Links shim/ballet.c (Firedancer siphash/protobuf/JSON primitives). Audit
/// and canonical consumer-money hash codec logic is Zig; see
/// src/tickoni/codec/audit.zig and src/tickoni/codec/thesis.zig.
fn linkTickoniCodec(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniCodecShim(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        linkTickoniWindowsUuid(b, step, fd_lib_dir);
        // Windows doesn't have pkg-config, so use link_libcpp instead of
        // linkSystemLibrary("stdc++", .{}) which would invoke pkg-config.
        step.root_module.link_libcpp = true;
        return;
    }
    linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_ballet", "fd_util" });
}

fn addTickoniCodecShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/ballet.c",
        },
        .flags = shimCFlagsFor(target_info),
    });
}
