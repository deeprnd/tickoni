/// Coverage test lane strategy.
///
/// Extracts inline coverage test registration from build.zig into a callable
/// function. Preserves identical compile flags, linkage, and install paths.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");

/// Cov test module imports for tile-based tests.
const TileImports = struct {
    runtime: *std.Build.Module,
    c_abi: *std.Build.Module,
    logger: *std.Build.Module,
    audit_tile: *std.Build.Module,
    audit_codec: *std.Build.Module,
    audit_schema: *std.Build.Module,
    fixture_audit_gen: *std.Build.Module,
};

/// Register all coverage test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    cov_step: *std.Build.Step,
    shared: struct {
        audit_codec: *std.Build.Module,
        audit_schema: *std.Build.Module,
        runtime: *std.Build.Module,
        c_abi: *std.Build.Module,
        util: *std.Build.Module,
        logger: *std.Build.Module,
        classification: *std.Build.Module,
        fixture_paths: *std.Build.Module,
        thesis: *std.Build.Module,
        catalog_schema: *std.Build.Module,
        catalog: *std.Build.Module,
        basket: *std.Build.Module,
        portfolio: *std.Build.Module,
        fixture_portfolio: *std.Build.Module,
    },
    tm: struct {
        fixture_audit_gen: *std.Build.Module,
    },
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    // Tile-based cov tests (topology, tile, c_abi, util, etc.)
    const cov_test_specs: []const struct { name: []const u8, path: []const u8, needs_codec: bool, needs_fd: bool, extra_imports: ?[*]const struct { name: []const u8, module: *std.Build.Module } } = &.{
        .{ .name = "test-topology", .path = "src/tickoni/runtime/topology.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-tile", .path = "src/tickoni/runtime/tile.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-queue", .path = "src/tickoni/c_abi/queue.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-sandbox", .path = "src/tickoni/c_abi/sandbox.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-dcache", .path = "src/tickoni/c_abi/dcache.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-fseq", .path = "src/tickoni/c_abi/fseq.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-fctl", .path = "src/tickoni/c_abi/fctl.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-cnc", .path = "src/tickoni/c_abi/cnc.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-tempo", .path = "src/tickoni/c_abi/tempo.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-wksp", .path = "src/tickoni/c_abi/wksp.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-cpu", .path = "src/tickoni/util/cpu.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-cpu-placement", .path = "src/tickoni/runtime/cpu_placement.zig", .needs_codec = false, .needs_fd = false, .extra_imports = &.{.{ .name = "util", .module = shared.util }}, .extra_imports_len = 1 },
        .{ .name = "test-process", .path = "src/tickoni/util/process.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-sandbox-config", .path = "src/tickoni/runtime/sandbox.zig", .needs_codec = false, .needs_fd = false, .extra_imports = &.{.{ .name = "util", .module = shared.util }}, .extra_imports_len = 1 },
        .{ .name = "test-cnc-counters", .path = "src/tickoni/runtime/cnc_counters.zig", .needs_codec = false, .needs_fd = false, .extra_imports = &.{.{ .name = "c_abi", .module = shared.c_abi }}, .extra_imports_len = 1 },
        .{ .name = "test-audit", .path = "src/tickoni/tiles/audit/mod.zig", .needs_codec = true, .needs_fd = true, .extra_imports = &.{ .{ .name = "audit_codec", .module = shared.audit_codec }, .{ .name = "audit_schema", .module = shared.audit_schema }, .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen }}, .extra_imports_len = 3 },
        .{ .name = "test-payment-pipeline", .path = "src/tickoni/tiles/payment_pipeline/mod.zig", .needs_codec = true, .needs_fd = true, .extra_imports = &.{ .{ .name = "audit_tile", .module = tm.fixture_audit_gen }, .{ .name = "runtime", .module = shared.runtime }, .{ .name = "c_abi", .module = shared.c_abi }, .{ .name = "logger", .module = shared.logger }}, .extra_imports_len = 4 },
        .{ .name = "test-case", .path = "src/tickoni/tiles/case/mod.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
        .{ .name = "test-disp", .path = "src/tickoni/tiles/disp/mod.zig", .needs_codec = false, .needs_fd = false, .extra_imports = null },
    };

    inline for (cov_test_specs) |spec| {
        var imports: [8]struct { name: []const u8, module: *std.Build.Module } = undefined;
        var imports_len: usize = 0;

        if (spec.extra_imports) |extra| {
            var i: usize = 0;
            while (i < spec.extra_imports_len) : {
                imports[imports_len] = extra[i];
                imports_len += 1;
                i += 1;
            }
        }

        const t = b.addTest(.{
            .name = spec.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(spec.path),
                .target = target,
                .optimize = optimize,
                .imports = imports[0..imports_len],
            }),
        });

        if (spec.needs_codec) {
            codec.linkTickoniCodec(b, t, fd_lib_dir);
            if (spec.needs_fd) {
                firedancer.linkTickoniFiredancer(b, t, fd_lib_dir);
            }
        }

        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    // Schema-based cov tests (thesis, catalog, basket, portfolio, etc.)
    const schema_test_specs: []const struct { name: []const u8, path: []const u8, imports: []const struct { name: []const u8, module: *std.Build.Module } } = &.{
        .{ .name = "test-thesis", .path = "src/tickoni/schema/consumer_money/thesis.zig", .imports = &.{
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        } },
        .{ .name = "test-catalog", .path = "src/tickoni/schema/consumer_money/catalog.zig", .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "catalog_schema", .module = shared.catalog_schema },
        } },
        .{ .name = "test-catalog-schema", .path = "src/tickoni/schema/consumer_money/catalog_schema.zig", .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
        } },
        .{ .name = "test-portfolio", .path = "src/tickoni/schema/portfolio/portfolio.zig", .imports = &.{
            .{ .name = "basket", .module = shared.basket },
        } },
        .{ .name = "test-portfolio-fixtures", .path = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig", .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        } },
        .{ .name = "test-trade-ticket", .path = "src/tickoni/schema/consumer_money/trade_ticket.zig", .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = shared.fixture_portfolio },
            .{ .name = "thesis", .module = shared.thesis },
        } },
        .{ .name = "test-impact", .path = "src/tickoni/schema/consumer_money/impact.zig", .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        } },
        .{ .name = "test-basket", .path = "src/tickoni/schema/consumer_money/basket.zig", .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "catalog", .module = shared.catalog },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        } },
    };

    inline for (schema_test_specs) |spec| {
        const t = b.addTest(.{
            .name = spec.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(spec.path),
                .target = target,
                .optimize = optimize,
                .imports = spec.imports,
            }),
        });
        codec.linkTickoniCodec(b, t, fd_lib_dir);
        cov_step.dependOn(&b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    // Supervisor and topologies cov tests
    const sup_cov_test = b.addTest(.{
        .name = "test-supervisor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = shared.runtime },
                .{ .name = "tiles", .module = shared.runtime }, // tiles module
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "util", .module = shared.util },
                .{ .name = "topologies", .module = shared.util }, // topologies
                .{ .name = "logger", .module = shared.logger },
            },
        }),
    });
    codec.linkTickoniCodec(b, sup_cov_test, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, sup_cov_test, fd_lib_dir);
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
                .{ .name = "runtime", .module = shared.runtime },
            },
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(topologies_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}
