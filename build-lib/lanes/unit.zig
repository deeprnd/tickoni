/// Unit test lane strategy — spec-driven.
///
/// Replaces ~960 lines of repetitive individual test registrations with a
/// spec array + TestBuilder. Handles special cases (tier.zig C source,
/// codec-linked tests, schema tests) via per-spec linkage/imports flags.

const std = @import("std");
const factory = @import("../factory.zig");
const lane = @import("../lane.zig");
const shared_mod = @import("../mod/modules.zig");
const test_mod = @import("../mod/test_modules.zig");

/// Register all unit test binaries. Called from build.zig.
/// `test_step` and `run_cmd` are created by build.zig and passed in.
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    test_step: *std.Build.Step,
    run_cmd: *std.Build.Step.Run,
) void {
    // Create shared module graph (same as integration lane).
    // Unit lane doesn't use .exe from the result, so pass null.
    const int_mods = factory.ModuleFactory.init(b, shared, tm, target, optimize).createIntModules(null);

    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // === Tile-based unit tests ===

    tb.registerRunTest(.{
        .name = "test-topology",
        .source_file = "src/tickoni/runtime/topology.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-tile",
        .source_file = "src/tickoni/runtime/tile.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-cpu",
        .source_file = "src/tickoni/util/cpu.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-process",
        .source_file = "src/tickoni/util/process.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-sandbox-defaults",
        .source_file = "src/tickoni/util/sandbox_defaults.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-linux-ids",
        .source_file = "src/tickoni/util/linux_ids.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-sizes",
        .source_file = "src/tickoni/util/sizes.zig",
    }, test_step, run_cmd);

    tb.registerRunTest(.{
        .name = "test-cabi-boot",
        .source_file = "src/tickoni/c_abi/boot.zig",
    }, test_step, run_cmd);

    // tier.zig — needs C source (compiler_version.c) and libc.
    const tier_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/util/tier.zig"),
        .target = target,
        .optimize = optimize,
    });
    tier_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/util/compiler_version.c"} });
    tier_mod.link_libc = true;
    const tier_test = b.addTest(.{ .name = "test-tier", .root_module = tier_mod });
    test_step.dependOn(&tier_test.step);
    run_cmd.addArtifactArg(tier_test);

    // === C ABI tests (need firedancer linkage) ===

    const cabi_tests = [_]struct { path: []const u8, name: []const u8 }{
        .{ .path = "src/tickoni/c_abi/queue.zig", .name = "test-queue" },
        .{ .path = "src/tickoni/c_abi/sandbox.zig", .name = "test-sandbox" },
        .{ .path = "src/tickoni/c_abi/dcache.zig", .name = "test-dcache" },
        .{ .path = "src/tickoni/c_abi/fseq.zig", .name = "test-fseq" },
        .{ .path = "src/tickoni/c_abi/fctl.zig", .name = "test-fctl" },
        .{ .path = "src/tickoni/c_abi/cnc.zig", .name = "test-cnc" },
        .{ .path = "src/tickoni/c_abi/tempo.zig", .name = "test-tempo" },
        .{ .path = "src/tickoni/c_abi/wksp.zig", .name = "test-wksp" },
    };

    inline for (cabi_tests) |t| {
        tb.registerRunTest(.{
            .name = t.name,
            .source_file = t.path,
            .linkage = .{ .needs_firedancer = true },
        }, test_step, run_cmd);
    }

    // ballet.zig — needs codec linkage (siphash/pb/json in shim/ballet.c).
    tb.registerRunTest(.{
        .name = "test-cabi-ballet",
        .source_file = "src/tickoni/c_abi/ballet.zig",
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // sandbox.zig — needs util import.
    tb.registerRunTest(.{
        .name = "test-sandbox",
        .source_file = "src/tickoni/runtime/sandbox.zig",
        .imports = &.{.{ .name = "util", .module = shared.util }},
    }, test_step, run_cmd);

    // === Tile tests with special linkage ===

    // audit/mod.zig — needs audit_codec, audit_schema, fixture_audit_gen.
    tb.registerRunTest(.{
        .name = "test-audit",
        .source_file = "src/tickoni/tiles/audit/mod.zig",
        .imports = &.{
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    }, test_step, run_cmd);

    // payment_pipeline/mod.zig — needs audit_tile, runtime, c_abi, logger.
    tb.registerRunTest(.{
        .name = "test-payment-pipeline",
        .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
        .imports = &.{
            .{ .name = "audit_tile", .module = tm.audit_tile },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    }, test_step, run_cmd);

    // case/mod.zig — standalone.
    tb.registerRunTest(.{
        .name = "test-case",
        .source_file = "src/tickoni/tiles/case/mod.zig",
    }, test_step, run_cmd);

    // disp/mod.zig — standalone.
    tb.registerRunTest(.{
        .name = "test-disp",
        .source_file = "src/tickoni/tiles/disp/mod.zig",
    }, test_step, run_cmd);

    // === V2.21.S3 modules ===

    // version.zig — tier, audit_schema, build_options, compiler_version.c.
    {
        const v_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/version.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tier", .module = shared.tier },
                .{ .name = "audit_schema", .module = shared.audit_schema },
                .{ .name = "build_options", .module = shared.version_opts.createModule() },
            },
        });
        v_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/util/compiler_version.c"} });
        v_mod.link_libc = true;
        const v_test = b.addTest(.{ .name = "test-version", .root_module = v_mod });
        test_step.dependOn(&v_test.step);
        run_cmd.addArtifactArg(v_test);
    }

    // doctor/checks.zig — standalone.
    tb.registerRunTest(.{
        .name = "test-doctor-checks",
        .source_file = "src/tickoni/doctor/checks.zig",
    }, test_step, run_cmd);

    // doctor/output.zig — needs doctor_checks.
    tb.registerRunTest(.{
        .name = "test-doctor-output",
        .source_file = "src/tickoni/doctor/output.zig",
        .imports = &.{.{ .name = "doctor_checks", .module = shared.doctor_checks }},
    }, test_step, run_cmd);

    // demo/manifest.zig — needs logger.
    tb.registerRunTest(.{
        .name = "test-demo-manifest",
        .source_file = "src/tickoni/demo/manifest.zig",
        .imports = &.{.{ .name = "logger", .module = shared.logger }},
    }, test_step, run_cmd);

    // demo/preflight.zig — needs demo_manifest, demo_semver, demo_diagnostic, tier.
    tb.registerRunTest(.{
        .name = "test-demo-preflight",
        .source_file = "src/tickoni/demo/preflight.zig",
        .imports = &.{
            .{ .name = "demo_manifest", .module = shared.demo_manifest },
            .{ .name = "demo_semver", .module = shared.demo_semver },
            .{ .name = "diagnostic", .module = shared.demo_diagnostic },
            .{ .name = "tier", .module = shared.tier },
        },
    }, test_step, run_cmd);

    // demo/diagnostic.zig — standalone.
    tb.registerRunTest(.{
        .name = "test-demo-diagnostic",
        .source_file = "src/tickoni/demo/diagnostic.zig",
    }, test_step, run_cmd);

    // demo/conformance.zig — needs diagnostic.
    tb.registerRunTest(.{
        .name = "test-demo-conformance",
        .source_file = "src/tickoni/demo/conformance.zig",
        .imports = &.{.{ .name = "diagnostic", .module = shared.demo_diagnostic }},
    }, test_step, run_cmd);

    // demo/comparator.zig — needs conformance.
    tb.registerRunTest(.{
        .name = "test-demo-comparator",
        .source_file = "src/tickoni/demo/comparator.zig",
        .imports = &.{.{ .name = "conformance", .module = shared.demo_conformance }},
    }, test_step, run_cmd);

    // demo/runner.zig — needs conformance, diagnostic.
    tb.registerRunTest(.{
        .name = "test-demo-runner",
        .source_file = "src/tickoni/demo/runner.zig",
        .imports = &.{
            .{ .name = "conformance", .module = shared.demo_conformance },
            .{ .name = "diagnostic", .module = shared.demo_diagnostic },
        },
    }, test_step, run_cmd);

    // demo/substitution.zig — needs diagnostic, runner.
    tb.registerRunTest(.{
        .name = "test-demo-substitution",
        .source_file = "src/tickoni/demo/substitution.zig",
        .imports = &.{
            .{ .name = "diagnostic", .module = shared.demo_diagnostic },
            .{ .name = "runner", .module = shared.demo_runner },
        },
    }, test_step, run_cmd);

    // === Schema tests (all need codec linkage) ===

    // codec/thesis.zig — thesis, basket.
    tb.registerRunTest(.{
        .name = "test-codec-thesis",
        .source_file = "src/tickoni/codec/thesis.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/thesis.zig — classification, c_abi, fixture_paths.
    tb.registerRunTest(.{
        .name = "test-thesis",
        .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
        .imports = &.{
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/catalog.zig — thesis, classification, catalog_schema.
    tb.registerRunTest(.{
        .name = "test-catalog",
        .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "catalog_schema", .module = shared.catalog_schema },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/catalog_schema.zig — thesis.
    tb.registerRunTest(.{
        .name = "test-catalog-schema",
        .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
        .imports = &.{.{ .name = "thesis", .module = shared.thesis }},
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/portfolio.zig — basket.
    tb.registerRunTest(.{
        .name = "test-portfolio",
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .imports = &.{.{ .name = "basket", .module = shared.basket }},
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // test/fixtures/portfolio/fixture_portfolio.zig — portfolio, basket.
    tb.registerRunTest(.{
        .name = "test-fixture-portfolio",
        .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/trade_ticket.zig — basket, portfolio, fixture_portfolio, thesis.
    tb.registerRunTest(.{
        .name = "test-trade-ticket",
        .source_file = "src/tickoni/schema/consumer_money/trade_ticket.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "thesis", .module = shared.thesis },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/impact.zig — basket, portfolio.
    tb.registerRunTest(.{
        .name = "test-impact",
        .source_file = "src/tickoni/schema/consumer_money/impact.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // schema/basket.zig — thesis, catalog, c_abi, fixture_paths.
    tb.registerRunTest(.{
        .name = "test-basket",
        .source_file = "src/tickoni/schema/consumer_money/basket.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "catalog", .module = shared.catalog },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);

    // === Logger test (needs os.c shim) ===
    {
        const logger_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/logger.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = shared.util }},
        });
        logger_mod.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/os.c"},
            .flags = &.{"-std=c17"},
        });
        logger_mod.linkSystemLibrary("c", .{});
        const logger_test = b.addTest(.{ .name = "test-logger", .root_module = logger_mod });
        test_step.dependOn(&logger_test.step);
        run_cmd.addArtifactArg(logger_test);
    }

    // === Investment demo test (needs codec linkage) ===

    tb.registerRunTest(.{
        .name = "test-investment-demo",
        .source_file = "src/tickoni/test/demo/investment/mod.zig",
        .imports = &.{
            .{ .name = "adapter", .module = int_mods.adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "cards", .module = tm.cards },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "impact", .module = tm.impact },
            .{ .name = "investment_support", .module = int_mods.investment_support_int_mod },
            .{ .name = "model", .module = int_mods.model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = int_mods.replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "tkpoly", .module = int_mods.tkpoly_int_mod },
            .{ .name = "tool", .module = int_mods.tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
        .linkage = .{ .needs_codec = true },
    }, test_step, run_cmd);
}
