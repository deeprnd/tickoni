/// Unit test lane strategy.
///
/// Extracts inline test registration from build.zig into a callable function.
/// Preserves identical compile flags, linkage, and module structure.
/// Strategy: iterate over specs, create modules, add tests, apply linkage.

const std = @import("std");
const shared_mod = @import("../mod/modules.zig");
const test_mod = @import("../mod/test_modules.zig");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const tile_run = @import("../lib/tile_run.zig");
const shims = @import("../lib/shims.zig");

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
    const tkpoly_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const model_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "model_messages", .module = tm.model_messages },
            .{ .name = "mock_model", .module = tm.mock_model },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const adapter_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "adapter_messages", .module = tm.adapter_messages },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const tool_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const replay_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const investment_support_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    // Dedicated test instance of investment_demo_mod so that
    // linkTickoniCodec adds ballet.c only to the test binary's root module
    // — not to the shared investment_demo_mod which is also imported by
    // system test binaries (portfolio_cash_demo_test,
    // test_investment_demo_live_test, etc.).
    const investment_demo_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_int_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "cards", .module = tm.cards },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "impact", .module = tm.impact },
            .{ .name = "investment_support", .module = investment_support_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const investment_demo_test = b.addTest(.{ .root_module = investment_demo_test_mod });
    codec.linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
    test_step.dependOn(&investment_demo_test.step);
    run_cmd.addArtifactArg(investment_demo_test);

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
                    .{ .name = "audit_codec", .module = shared.audit_codec },
                    .{ .name = "audit_schema", .module = shared.audit_schema },
                    .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
                },
            })
        else if (std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig"))
            b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "audit_tile", .module = tm.audit_tile },
                    .{ .name = "runtime", .module = shared.runtime },
                    .{ .name = "c_abi", .module = shared.c_abi },
                    .{ .name = "logger", .module = shared.logger },
                },
            })
        else if (std.mem.eql(u8, path, "src/tickoni/runtime/sandbox.zig"))
            b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "util", .module = shared.util },
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
            codec.linkTickoniCodec(b, t, fd_lib_dir);
        }
        if (std.mem.eql(u8, path, "src/tickoni/tiles/payment_pipeline/mod.zig")) {
            codec.linkTickoniCodec(b, t, fd_lib_dir);
            // Logger module imports util -> c_abi.os which needs shim/os.c
            firedancer.linkTickoniFiredancer(b, t, fd_lib_dir);
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
            firedancer.linkTickoniFiredancer(b, t, fd_lib_dir);
        }
        if (std.mem.eql(u8, path, "src/tickoni/c_abi/ballet.zig")) {
            // siphash/pb/json primitives live in shim/ballet.c, linked via
            // linkTickoniCodec.
            codec.linkTickoniCodec(b, t, fd_lib_dir);
        }
        test_step.dependOn(&t.step);
        run_cmd.addArtifactArg(t);
    }

    // V2.21.S3 modules — version, doctor, demo manifest, preflight (T2 scaffolding).
    // Each has its own test binary with its own import graph.

    // version.zig imports: tier, audit_schema, build_options
    const version_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/version.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tier", .module = shared.tier },
                .{ .name = "audit_schema", .module = shared.audit_schema },
                .{ .name = "build_options", .module = shared.version_opts.createModule() },
            },
        }),
    });
    version_test.root_module.addCSourceFiles(.{
        .files = &.{"src/tickoni/util/compiler_version.c"},
    });
    version_test.root_module.link_libc = true;
    test_step.dependOn(&version_test.step);
    run_cmd.addArtifactArg(version_test);

    // doctor/checks.zig — standalone (no imports beyond std)
    const doctor_checks_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/doctor/checks.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&doctor_checks_test.step);
    run_cmd.addArtifactArg(doctor_checks_test);

    // doctor/output.zig imports: doctor_checks
    const doctor_output_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/doctor/output.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "doctor_checks", .module = shared.doctor_checks },
            },
        }),
    });
    test_step.dependOn(&doctor_output_test.step);
    run_cmd.addArtifactArg(doctor_output_test);

    // demo/manifest.zig — standalone (no cross-module imports)
    const demo_manifest_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/manifest.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "logger", .module = shared.logger },
            },
        }),
    });
    test_step.dependOn(&demo_manifest_test.step);
    run_cmd.addArtifactArg(demo_manifest_test);

    // demo/preflight.zig imports: demo_manifest, demo_semver, tier
    const demo_preflight_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/preflight.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "demo_manifest", .module = shared.demo_manifest },
                .{ .name = "demo_semver", .module = shared.demo_semver },
                .{ .name = "diagnostic", .module = shared.demo_diagnostic },
                .{ .name = "tier", .module = shared.tier },
            },
        }),
    });
    test_step.dependOn(&demo_preflight_test.step);
    run_cmd.addArtifactArg(demo_preflight_test);

    const demo_diagnostic_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/diagnostic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&demo_diagnostic_test.step);
    run_cmd.addArtifactArg(demo_diagnostic_test);

    const demo_conformance_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/conformance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diagnostic", .module = shared.demo_diagnostic },
            },
        }),
    });
    test_step.dependOn(&demo_conformance_test.step);
    run_cmd.addArtifactArg(demo_conformance_test);

    const demo_comparator_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/comparator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "conformance", .module = shared.demo_conformance },
            },
        }),
    });
    test_step.dependOn(&demo_comparator_test.step);
    run_cmd.addArtifactArg(demo_comparator_test);

    const demo_runner_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "conformance", .module = shared.demo_conformance },
                .{ .name = "diagnostic", .module = shared.demo_diagnostic },
            },
        }),
    });
    test_step.dependOn(&demo_runner_test.step);
    run_cmd.addArtifactArg(demo_runner_test);

    const demo_substitution_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/demo/substitution.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diagnostic", .module = shared.demo_diagnostic },
                .{ .name = "runner", .module = shared.demo_runner },
            },
        }),
    });
    test_step.dependOn(&demo_substitution_test.step);
    run_cmd.addArtifactArg(demo_substitution_test);

    // src/tickoni/codec/thesis.zig: dedicated wrapper tests over the canonical
    // consumer-money schema hash APIs.
    const thesis_codec_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/codec/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "basket", .module = shared.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, thesis_codec_test, fd_lib_dir);
    test_step.dependOn(&thesis_codec_test.step);
    run_cmd.addArtifactArg(thesis_codec_test);

    // thesis.zig: fresh root module so linkTickoniCodec adds C sources only to
    // this binary's root module.
    const thesis_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/thesis.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "classification", .module = shared.classification },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, thesis_test, fd_lib_dir);
    test_step.dependOn(&thesis_test.step);
    run_cmd.addArtifactArg(thesis_test);

    const catalog_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "classification", .module = shared.classification },
                .{ .name = "catalog_schema", .module = shared.catalog_schema },
            },
        }),
    });
    codec.linkTickoniCodec(b, catalog_test, fd_lib_dir);
    test_step.dependOn(&catalog_test.step);
    run_cmd.addArtifactArg(catalog_test);

    // logger.zig: structured, env-driven Zig logger with module filtering,
    // colors, and flush — unit tests for level parsing, module filter,
    // KV output, colorize detection, and enter/exit tracing.
    const logger_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tickoni/logger.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "util", .module = shared.util } },
    })});
    // Link the os.c shim for C runtime calls (monotonicNanos, fflush, write, isatty).
    logger_test.root_module.addCSourceFiles(.{
        .files = &.{"src/tickoni/c_abi/shim/os.c"},
        .flags = &.{"-std=c17"},
    });
    logger_test.root_module.linkSystemLibrary("c", .{});
    test_step.dependOn(&logger_test.step);
    run_cmd.addArtifactArg(logger_test);

    const catalog_schema_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/catalog_schema.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, catalog_schema_test, fd_lib_dir);
    test_step.dependOn(&catalog_schema_test.step);
    run_cmd.addArtifactArg(catalog_schema_test);

    const basket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/basket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "catalog", .module = shared.catalog },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, basket_test, fd_lib_dir);
    test_step.dependOn(&basket_test.step);
    run_cmd.addArtifactArg(basket_test);

    const portfolio_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/portfolio/portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, portfolio_test, fd_lib_dir);
    test_step.dependOn(&portfolio_test.step);
    run_cmd.addArtifactArg(portfolio_test);

    const fixture_portfolio_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "basket", .module = shared.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, fixture_portfolio_test, fd_lib_dir);
    test_step.dependOn(&fixture_portfolio_test.step);
    run_cmd.addArtifactArg(fixture_portfolio_test);

    const model_messages_test = b.addTest(.{ .root_module = tm.model_messages });
    test_step.dependOn(&model_messages_test.step);
    run_cmd.addArtifactArg(model_messages_test);

    const mock_model_test = b.addTest(.{ .root_module = tm.mock_model });
    test_step.dependOn(&mock_model_test.step);
    run_cmd.addArtifactArg(mock_model_test);

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
    run_cmd.addArtifactArg(link_handles_test);

    const link_types_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/link/types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&link_types_test.step);
    run_cmd.addArtifactArg(link_types_test);

    // boot.zig imports c_abi for the raw fd_boot bridge call.
    const boot_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/boot.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
            },
        }),
    });
    test_step.dependOn(&boot_test.step);
    run_cmd.addArtifactArg(boot_test);

    // cnc_counters.zig imports c_abi and calls the real tk_cnc_app_laddr
    // shim (via c_abi.cnc.appLaddr) in its round-trip test.
    const cnc_counters_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/cnc_counters.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
            },
        }),
    });
    firedancer.linkTickoniFiredancer(b, cnc_counters_test, fd_lib_dir);
    test_step.dependOn(&cnc_counters_test.step);
    run_cmd.addArtifactArg(cnc_counters_test);

    // cpu_placement.zig imports util (for the CpuSet primitive) alongside
    // its sibling topology.zig.
    const cpu_placement_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "util", .module = shared.util },
            },
        }),
    });
    test_step.dependOn(&cpu_placement_test.step);
    run_cmd.addArtifactArg(cpu_placement_test);

    // launch_spec.zig embeds link.LinkHandles, which imports c_abi.
    const launch_spec_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/launch_spec.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
            },
        }),
    });
    test_step.dependOn(&launch_spec_test.step);
    run_cmd.addArtifactArg(launch_spec_test);

    // topology_spec.zig (v2.14.S8.T4): small tiles+channels round-trip,
    // same import needs as launch_spec.zig.
    const topology_spec_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/runtime/topology_spec.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
            },
        }),
    });
    test_step.dependOn(&topology_spec_test.step);
    run_cmd.addArtifactArg(topology_spec_test);

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
        .flags = shims.shimCFlagsFor(_topo_test_target),
    });
    firedancer.linkTickoniFiredancer(b, topo_run_test, fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, topo_run_test, fd_lib_dir);
    tile_run.linkTickoniTileRun(b, topo_run_test, fd_lib_dir);
    test_step.dependOn(&topo_run_test.step);
    run_cmd.addArtifactArg(topo_run_test);

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
    firedancer.linkTickoniFiredancer(b, topob_test, fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, topob_test, fd_lib_dir);
    test_step.dependOn(&topob_test.step);
    run_cmd.addArtifactArg(topob_test);

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
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "util", .module = shared.util },
            },
        }),
    });
    firedancer.linkTickoniFiredancer(b, topo_build_test, fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, topo_build_test, fd_lib_dir);
    test_step.dependOn(&topo_build_test.step);
    run_cmd.addArtifactArg(topo_build_test);

    // model tile: unit tests are mock/fixture-backed and must not start servers.
    const model_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = tm.model_messages },
                .{ .name = "mock_model", .module = tm.mock_model },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, model_test, fd_lib_dir);
    test_step.dependOn(&model_test.step);
    run_cmd.addArtifactArg(model_test);

    const tkpoly_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const adapter_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/adapter/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "adapter_messages", .module = tm.adapter_messages },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
    });

    const adapter_test = b.addTest(.{ .root_module = adapter_test_mod });
    test_step.dependOn(&adapter_test.step);
    run_cmd.addArtifactArg(adapter_test);

    const mock_adapter_test = b.addTest(.{ .root_module = tm.mock_adapter });
    test_step.dependOn(&mock_adapter_test.step);
    run_cmd.addArtifactArg(mock_adapter_test);

    // trade_ticket.zig imports basket, portfolio, fixture_portfolio, and thesis.
    const trade_ticket_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/trade_ticket.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
                .{ .name = "thesis", .module = shared.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, trade_ticket_test, fd_lib_dir);
    test_step.dependOn(&trade_ticket_test.step);
    run_cmd.addArtifactArg(trade_ticket_test);

    // impact.zig: portfolio and cash impact model (V1.3.S1).
    const impact_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/impact.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
            },
        }),
    });
    codec.linkTickoniCodec(b, impact_test, fd_lib_dir);
    test_step.dependOn(&impact_test.step);
    run_cmd.addArtifactArg(impact_test);

    // cards.zig: thesis and money proposal card schemas (V1.3.S2).
    const cards_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/cards.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "impact", .module = tm.impact },
            },
        }),
    });
    codec.linkTickoniCodec(b, cards_test, fd_lib_dir);
    test_step.dependOn(&cards_test.step);
    run_cmd.addArtifactArg(cards_test);

    // drift.zig: drift conditions, assessment, and suggestion generation (V1.3.S3).
    const drift_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/schema/consumer_money/drift.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "cards", .module = tm.cards },
            },
        }),
    });
    codec.linkTickoniCodec(b, drift_test, fd_lib_dir);
    test_step.dependOn(&drift_test.step);
    run_cmd.addArtifactArg(drift_test);

    const allowed_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_allowed_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            },
        }),
    });
    codec.linkTickoniCodec(b, allowed_trade_fixture_test, fd_lib_dir);
    test_step.dependOn(&allowed_trade_fixture_test.step);
    run_cmd.addArtifactArg(allowed_trade_fixture_test);

    const denied_trade_fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/fixtures/investment/fixture_denied_trade.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, denied_trade_fixture_test, fd_lib_dir);
    test_step.dependOn(&denied_trade_fixture_test.step);
    run_cmd.addArtifactArg(denied_trade_fixture_test);

    const tool_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/tiles/tool/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "adapter", .module = adapter_test_mod },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
        },
    });

    const tool_test = b.addTest(.{ .root_module = tool_test_mod });
    test_step.dependOn(&tool_test.step);
    run_cmd.addArtifactArg(tool_test);

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
                .{ .name = "mock_adapter", .module = tm.mock_adapter },
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "disp", .module = disp_unit_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "mock_model", .module = tm.mock_model },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "tkpoly", .module = tkpoly_test_mod },
                .{ .name = "tool", .module = tool_test_mod },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
                .{ .name = "capability", .module = shared.capability },
            },
        }),
    });
    codec.linkTickoniCodec(b, agent_test, fd_lib_dir);
    test_step.dependOn(&agent_test.step);
    run_cmd.addArtifactArg(agent_test);

    const replay_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/replay/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "adapter", .module = adapter_test_mod },
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "drift", .module = tm.drift },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "tkpoly", .module = tkpoly_test_mod },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, replay_test, fd_lib_dir);
    test_step.dependOn(&replay_test.step);
    run_cmd.addArtifactArg(replay_test);

    // supervisor.zig imports runtime, tiles, and c_abi modules.
    const sup_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "logger", .module = shared.logger },
        },
    });
    const sup_test = b.addTest(.{ .root_module = sup_mod });
    codec.linkTickoniCodec(b, sup_test, fd_lib_dir);
    // supervisor.zig now calls into tile_registry.zig's `entries` array
    // (v2.14.S8.T1), which embeds every tile's process-mode function
    // pointer (including tiles.process/rt.link/c_abi callers) as static
    // data even for tests that only exercise thread mode — needs the same
    // Firedancer link set as the process-mode integration tests.
    firedancer.linkTickoniFiredancer(b, sup_test, fd_lib_dir);
    test_step.dependOn(&sup_test.step);
    run_cmd.addArtifactArg(sup_test);

    // tile_registry.zig (v2.14.S8.T1): single source of truth for tile id
    // -> behavior, imported by supervisor.zig and tile_main.zig. Same
    // import set as sup_mod since it needs the same tile-identity types.
    const tile_registry_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/tile_registry.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
        },
    });
    const tile_registry_test = b.addTest(.{ .root_module = tile_registry_mod });
    codec.linkTickoniCodec(b, tile_registry_test, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, tile_registry_test, fd_lib_dir);
    test_step.dependOn(&tile_registry_test.step);
    run_cmd.addArtifactArg(tile_registry_test);

    // topologies.zig: fresh root module (not the shared shared.topologies)
    // so it gets its own dedicated test run, since named-import module
    // boundaries do not propagate test discovery to importers.
    const topologies_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni/topologies.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = shared.runtime },
            },
        }),
    });
    test_step.dependOn(&topologies_test.step);
    run_cmd.addArtifactArg(topologies_test);

    // V2.22.S7 evidence module — standalone (only imports std).
    const evidence_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/evidence/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const evidence_test = b.addTest(.{
        .root_module = evidence_mod,
    });
    test_step.dependOn(&evidence_test.step);
    run_cmd.addArtifactArg(evidence_test);
}
