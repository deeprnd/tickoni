/// Coverage specs for the Tickoni build system.
///
/// Lists test binaries to install to zig-out/cov/ for kcov coverage.
/// Uses the same TestSpec format as unit_specs.zig.

const std = @import("std");
const Registry = @import("registry.zig");
const helpers = @import("helpers.zig");

/// Cov specs: install test binaries to zig-out/cov/ for kcov.
pub fn covSpecs(
    b: *std.Build,
    modules: @import("../mod.zig").Modules,
    _test_modules: @import("../mod.zig").TestModules,
    _build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
) []const Registry.TestSpec {
    _ = _test_modules;
    _ = _build_options;
    const c_abi_mod = modules.c_abi;
    const util_mod = modules.util;
    const logger_mod = modules.logger;
    const runtime_mod = modules.runtime;
    const audit_schema_mod = modules.audit_schema;
    const audit_codec_mod = modules.audit_codec;
    const classification_mod = modules.classification;
    const thesis_mod = modules.thesis;
    const catalog_schema_mod = modules.catalog_schema;
    const basket_mod = modules.basket;
    const portfolio_mod = modules.portfolio;

    // Build cov-specific modules with correct imports
    const audit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "audit_codec", .module = audit_codec_mod },
            .{ .name = "audit_schema", .module = audit_schema_mod },
            .{ .name = "fixture_audit_gen", .module = modules.fixture_audit_gen },
        },
    });

    const payment_pipeline_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "audit_tile", .module = modules.tiles },
            .{ .name = "runtime", .module = runtime_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
            .{ .name = "logger", .module = logger_mod },
        },
    });

    const cnc_counters_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/runtime/cnc_counters.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });

    const cpu_placement_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
        },
    });

    const sandbox_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/runtime/sandbox.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "util", .module = util_mod },
        },
    });

    const thesis_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });

    const catalog_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "classification", .module = classification_mod },
            .{ .name = "catalog_schema", .module = catalog_schema_mod },
        },
    });

    const catalog_schema_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
        },
    });

    const portfolio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "basket", .module = basket_mod },
        },
    });

    const fixture_portfolio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "portfolio", .module = portfolio_mod },
            .{ .name = "basket", .module = basket_mod },
        },
    });

    const basket_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
        .target = target,
        .optimize = .Debug,
        .imports = &.{
            .{ .name = "thesis", .module = thesis_mod },
            .{ .name = "catalog", .module = modules.catalog },
            .{ .name = "c_abi", .module = c_abi_mod },
        },
    });

    // Cov specs: install test binaries to zig-out/cov/ for kcov.
    const cov_specs = &.{
        Registry.TestSpec{
            .name = "test-topology",
            .source_file = "src/tickoni/runtime/topology.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-tile",
            .source_file = "src/tickoni/runtime/tile.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-queue",
            .source_file = "src/tickoni/c_abi/queue.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-sandbox",
            .source_file = "src/tickoni/c_abi/sandbox.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-dcache",
            .source_file = "src/tickoni/c_abi/dcache.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-fseq",
            .source_file = "src/tickoni/c_abi/fseq.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-fctl",
            .source_file = "src/tickoni/c_abi/fctl.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cnc",
            .source_file = "src/tickoni/c_abi/cnc.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-tempo",
            .source_file = "src/tickoni/c_abi/tempo.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-wksp",
            .source_file = "src/tickoni/c_abi/wksp.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cpu",
            .source_file = "src/tickoni/util/cpu.zig",
            .imports = &.{},
            .linkage = .{ .needs_libc = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cpu-placement",
            .source_file = "src/tickoni/runtime/cpu_placement.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-process",
            .source_file = "src/tickoni/util/process.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-sandbox-config",
            .source_file = "src/tickoni/runtime/sandbox.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cnc-counters",
            .source_file = "src/tickoni/runtime/cnc_counters.zig",
            .imports = &.{},
            .linkage = .{ .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-audit",
            .source_file = "src/tickoni/tiles/audit/mod.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true, .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-payment-pipeline",
            .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true, .needs_firedancer = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-case",
            .source_file = "src/tickoni/tiles/case/mod.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-disp",
            .source_file = "src/tickoni/tiles/disp/mod.zig",
            .imports = &.{},
            .linkage = .{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-thesis",
            .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-catalog",
            .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-catalog-schema",
            .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-portfolio",
            .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-portfolio-fixtures",
            .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-basket",
            .source_file = "src/tickoni/schema/consumer_money/basket.zig",
            .imports = &.{},
            .linkage = .{ .needs_codec = true },
            .action = .cov,
        },
    };

    _ = audit_test_mod;
    _ = payment_pipeline_test_mod;
    _ = cnc_counters_test_mod;
    _ = cpu_placement_test_mod;
    _ = sandbox_test_mod;
    _ = thesis_test_mod;
    _ = catalog_test_mod;
    _ = catalog_schema_test_mod;
    _ = portfolio_test_mod;
    _ = fixture_portfolio_test_mod;
    _ = basket_test_mod;

    return cov_specs;
}
