/// Coverage test lane strategy — spec-driven, using canonical Shared/Tm types.
///
/// CovShared/CovTm (Phase 0) have been replaced by the canonical
/// `modules.Shared` and `test_modules.TestModules` types (Phase 5).

const std = @import("std");
const lane = @import("../lane.zig");
const shims = @import("../lib/shims.zig");
const modules = @import("../mod/modules.zig");
const test_modules = @import("../mod/test_modules.zig");

/// Register all coverage test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    cov_step: *std.Build.Step,
    shared: modules.Shared,
    tm: test_modules.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // Tile-based cov tests.
    tb.registerCov(.{
        .name = "test-topology",
        .source_file = "src/tickoni/runtime/topology.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-tile",
        .source_file = "src/tickoni/runtime/tile.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-queue",
        .source_file = "src/tickoni/c_abi/queue.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-sandbox",
        .source_file = "src/tickoni/c_abi/sandbox.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-dcache",
        .source_file = "src/tickoni/c_abi/dcache.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-fseq",
        .source_file = "src/tickoni/c_abi/fseq.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-fctl",
        .source_file = "src/tickoni/c_abi/fctl.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-cnc",
        .source_file = "src/tickoni/c_abi/cnc.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-tempo",
        .source_file = "src/tickoni/c_abi/tempo.zig",
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-wksp",
        .source_file = "src/tickoni/c_abi/wksp.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-cpu",
        .source_file = "src/tickoni/util/cpu.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-cpu-placement",
        .source_file = "src/tickoni/runtime/cpu_placement.zig",
        .imports = &.{.{ .name = "util", .module = shared.util }},
    }, cov_step);

    tb.registerCov(.{
        .name = "test-process",
        .source_file = "src/tickoni/util/process.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-sandbox-config",
        .source_file = "src/tickoni/runtime/sandbox.zig",
        .imports = &.{.{ .name = "util", .module = shared.util }},
    }, cov_step);

    tb.registerCov(.{
        .name = "test-cnc-counters",
        .source_file = "src/tickoni/runtime/cnc_counters.zig",
        .imports = &.{.{ .name = "c_abi", .module = shared.c_abi }},
        .linkage = .{ .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-audit",
        .source_file = "src/tickoni/tiles/audit/mod.zig",
        .imports = &.{
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-payment-pipeline",
        .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
        .imports = &.{
            .{ .name = "audit_tile", .module = shared.audit_tile },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-case",
        .source_file = "src/tickoni/tiles/case/mod.zig",
    }, cov_step);

    tb.registerCov(.{
        .name = "test-disp",
        .source_file = "src/tickoni/tiles/disp/mod.zig",
    }, cov_step);

    // Schema-based cov tests.
    tb.registerCov(.{
        .name = "test-thesis",
        .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
        .imports = &.{
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-catalog",
        .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "catalog_schema", .module = shared.catalog_schema },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-catalog-schema",
        .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
        .imports = &.{.{ .name = "thesis", .module = shared.thesis }},
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-portfolio",
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .imports = &.{.{ .name = "basket", .module = shared.basket }},
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-portfolio-fixtures",
        .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-trade-ticket",
        .source_file = "src/tickoni/schema/consumer_money/trade_ticket.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "thesis", .module = shared.thesis },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-impact",
        .source_file = "src/tickoni/schema/consumer_money/impact.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    tb.registerCov(.{
        .name = "test-basket",
        .source_file = "src/tickoni/schema/consumer_money/basket.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "catalog", .module = shared.catalog },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    }, cov_step);

    // Supervisor cov test.
    tb.registerCov(.{
        .name = "test-supervisor",
        .source_file = "src/app/tickoni/supervisor.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    }, cov_step);

    // Topologies cov test.
    tb.registerCov(.{
        .name = "test-topologies",
        .source_file = "src/app/tickoni/topologies.zig",
        .imports = &.{.{ .name = "runtime", .module = shared.runtime }},
    }, cov_step);
}
