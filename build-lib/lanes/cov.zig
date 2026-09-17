/// Coverage test lane strategy.
///
/// Extracts inline coverage test registration from build.zig into a callable
/// function. Preserves identical compile flags, linkage, and install paths.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");

/// Cov lane shared-module parameters — must match build.zig's `shared`
/// (build-lib/mod/modules.zig) struct field names.
pub const CovShared = struct {
    audit_codec: *std.Build.Module,
    audit_schema: *std.Build.Module,
    runtime: *std.Build.Module,
    tiles: *std.Build.Module,
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
    topologies: *std.Build.Module,
};

/// Cov lane test-module parameters — must match build.zig's `tm`
/// (build-lib/mod/test_modules.zig) struct field names.
pub const CovTm = struct {
    fixture_audit_gen: *std.Build.Module,
    audit_tile: *std.Build.Module,
    fixture_portfolio: *std.Build.Module,
};

/// Register all coverage test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    cov_step: *std.Build.Step,
    s: CovShared,
    tm: CovTm,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    // Tile-based cov tests (topology, tile, c_abi, util, etc.)

    const t1 = b.addTest(.{
        .name = "test-topology",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/topology.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t1, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t2 = b.addTest(.{
        .name = "test-tile",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/tile.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t2, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t3 = b.addTest(.{
        .name = "test-queue",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/queue.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t3, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t3, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t4 = b.addTest(.{
        .name = "test-sandbox",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/sandbox.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t4, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t5 = b.addTest(.{
        .name = "test-dcache",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/dcache.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t5, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t5, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t6 = b.addTest(.{
        .name = "test-fseq",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/fseq.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t6, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t6, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t7 = b.addTest(.{
        .name = "test-fctl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/fctl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t7, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t7, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t8 = b.addTest(.{
        .name = "test-cnc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/cnc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t8, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t8, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t9 = b.addTest(.{
        .name = "test-tempo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/tempo.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    firedancer.linkTickoniFiredancer(b, t9, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t9, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t10 = b.addTest(.{
        .name = "test-wksp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/wksp.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t10, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t11 = b.addTest(.{
        .name = "test-cpu",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/cpu.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t11, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t12 = b.addTest(.{
        .name = "test-cpu-placement",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = s.util }},
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t12, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t13 = b.addTest(.{
        .name = "test-process",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/process.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t13, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t14 = b.addTest(.{
        .name = "test-sandbox-config",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/sandbox.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = s.util }},
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t14, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t15 = b.addTest(.{
        .name = "test-cnc-counters",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/cnc_counters.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "c_abi", .module = s.c_abi }},
        }),
    });
    firedancer.linkTickoniFiredancer(b, t15, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t15, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t16 = b.addTest(.{
        .name = "test-audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/audit/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "audit_codec", .module = s.audit_codec },
                .{ .name = "audit_schema", .module = s.audit_schema },
                .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
            },
        }),
    });
    codec.linkTickoniCodec(b, t16, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, t16, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t16, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t17 = b.addTest(.{
        .name = "test-payment-pipeline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/payment_pipeline/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "audit_tile", .module = tm.audit_tile },
                .{ .name = "runtime", .module = s.runtime },
                .{ .name = "c_abi", .module = s.c_abi },
                .{ .name = "logger", .module = s.logger },
            },
        }),
    });
    codec.linkTickoniCodec(b, t17, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, t17, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t17, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t18 = b.addTest(.{
        .name = "test-case",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/case/mod.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t18, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t19 = b.addTest(.{
        .name = "test-disp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/disp/mod.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(t19, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    // Schema-based cov tests (thesis, catalog, basket, portfolio, etc.)

    const t20 = b.addTest(.{
        .name = "test-thesis",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "classification", .module = s.classification },
                .{ .name = "c_abi", .module = s.c_abi },
                .{ .name = "fixture_paths", .module = s.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, t20, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t20, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t21 = b.addTest(.{
        .name = "test-catalog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = s.thesis },
                .{ .name = "classification", .module = s.classification },
                .{ .name = "catalog_schema", .module = s.catalog_schema },
            },
        }),
    });
    codec.linkTickoniCodec(b, t21, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t21, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t22 = b.addTest(.{
        .name = "test-catalog-schema",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = s.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, t22, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t22, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t23 = b.addTest(.{
        .name = "test-portfolio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = s.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, t23, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t23, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t24 = b.addTest(.{
        .name = "test-portfolio-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = s.portfolio },
                .{ .name = "basket", .module = s.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, t24, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t24, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t25 = b.addTest(.{
        .name = "test-trade-ticket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = s.basket },
                .{ .name = "portfolio", .module = s.portfolio },
                .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
                .{ .name = "thesis", .module = s.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, t25, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t25, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t26 = b.addTest(.{
        .name = "test-impact",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = s.basket },
                .{ .name = "portfolio", .module = s.portfolio },
            },
        }),
    });
    codec.linkTickoniCodec(b, t26, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t26, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    const t27 = b.addTest(.{
        .name = "test-basket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = s.thesis },
                .{ .name = "catalog", .module = s.catalog },
                .{ .name = "c_abi", .module = s.c_abi },
                .{ .name = "fixture_paths", .module = s.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, t27, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(t27, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    // Supervisor cov test
    const sup_cov_test = b.addTest(.{
        .name = "test-supervisor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = s.runtime },
                .{ .name = "tiles", .module = s.tiles },
                .{ .name = "c_abi", .module = s.c_abi },
                .{ .name = "util", .module = s.util },
                .{ .name = "topologies", .module = s.topologies },
                .{ .name = "logger", .module = s.logger },
            },
        }),
    });
    codec.linkTickoniCodec(b, sup_cov_test, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, sup_cov_test, fd_lib_dir);
    cov_step.dependOn(&b.addInstallArtifact(sup_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);

    // Topologies cov test
    const topologies_cov_test = b.addTest(.{
        .name = "test-topologies",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/topologies.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = s.runtime },
            },
        }),
    });
    cov_step.dependOn(&b.addInstallArtifact(topologies_cov_test, .{
        .dest_dir = .{ .override = .{ .custom = "cov" } },
    }).step);
}
