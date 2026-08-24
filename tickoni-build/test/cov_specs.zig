/// Coverage specs for the Tickoni build system.
///
/// Lists test binaries to install to zig-out/cov/ for kcov coverage.
/// Uses the same TestSpec format as unit_specs.zig.

const std = @import("std");
const Registry = @import("registry.zig");

/// Cov specs: install test binaries to zig-out/cov/ for kcov.
pub fn covSpecs(
    _b: *std.Build,
    modules: @import("../mod.zig").Modules,
    _test_modules: @import("../mod.zig").TestModules,
    _build_options: ?std.Build.Module,
    _target: std.Build.ResolvedTarget,
) []const Registry.TestSpec {
    _ = _b;
    _ = modules;
    _ = _test_modules;
    _ = _build_options;
    _ = _target;

    // Cov specs: install test binaries to zig-out/cov/ for kcov.
    const cov_specs = &.{
        Registry.TestSpec{
            .name = "test-topology",
            .source_file = "src/tickoni/runtime/topology.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-tile",
            .source_file = "src/tickoni/runtime/tile.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-queue",
            .source_file = "src/tickoni/c_abi/queue.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-sandbox",
            .source_file = "src/tickoni/c_abi/sandbox.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-dcache",
            .source_file = "src/tickoni/c_abi/dcache.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-fseq",
            .source_file = "src/tickoni/c_abi/fseq.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-fctl",
            .source_file = "src/tickoni/c_abi/fctl.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cnc",
            .source_file = "src/tickoni/c_abi/cnc.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-tempo",
            .source_file = "src/tickoni/c_abi/tempo.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-wksp",
            .source_file = "src/tickoni/c_abi/wksp.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cpu",
            .source_file = "src/tickoni/util/cpu.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cpu-placement",
            .source_file = "src/tickoni/runtime/cpu_placement.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-process",
            .source_file = "src/tickoni/util/process.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-sandbox-config",
            .source_file = "src/tickoni/runtime/sandbox.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-cnc-counters",
            .source_file = "src/tickoni/runtime/cnc_counters.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-audit",
            .source_file = "src/tickoni/tiles/audit/mod.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-payment-pipeline",
            .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-case",
            .source_file = "src/tickoni/tiles/case/mod.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-disp",
            .source_file = "src/tickoni/tiles/disp/mod.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-thesis",
            .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-catalog",
            .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-catalog-schema",
            .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-portfolio",
            .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-portfolio-fixtures",
            .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
            .imports = &.{},
            .action = .cov,
        },
        Registry.TestSpec{
            .name = "test-basket",
            .source_file = "src/tickoni/schema/consumer_money/basket.zig",
            .imports = &.{},
            .action = .cov,
        },
    };

    return cov_specs;
}
