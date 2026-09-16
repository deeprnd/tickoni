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
const shims = @import("build/lib/shims.zig");
const codec = @import("build/lib/codec.zig");
const firedancer = @import("build/lib/firedancer.zig");
const topo_run = @import("build/lib/topo_run.zig");
const tile_run = @import("build/lib/tile_run.zig");
const build_mod = @import("build/mod/modules.zig");
const test_mod = @import("build/mod/test_modules.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/fd-tickoni-fd/lib)") orelse "build/fd-tickoni-fd/lib";
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;
    const clap_dep = b.dependency("clap", .{});
    const clap_mod = clap_dep.module("clap");

    // Shared modules — delegated to build/mod/modules.zig
    const shared = build_mod.modules(b, target, optimize);

    // Test-only modules — delegated to build/mod/test_modules.zig
    const tm = test_mod.testModules(b, target, optimize, shared);

    // ---------------------------------------------------------------------------
    // Integration modules — fresh instances so they don't inherit any
    // C source additions from the unit test lane. Defined inline because
    // they depend on each other in a cross-referencing graph.
    // ---------------------------------------------------------------------------
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
            .{ .name = "mock_adapter", .module = tm.mock_adapter },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "disp", .module = disp_int_mod },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "mock_model", .module = tm.mock_model },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "tkpoly", .module = tkpoly_int_mod },
            .{ .name = "tool", .module = tool_int_mod },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
            .{ .name = "capability", .module = shared.capability },
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

    const investment_audit_int_mod = b.createModule(.{
        .root_source_file = b.path("src/tickoni/test/demo/investment/audit_trace.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "audit_tile", .module = tm.audit_tile },
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "drift", .module = tm.drift },
            .{ .name = "model", .module = model_int_mod },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "replay", .module = replay_int_mod },
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "trade_ticket", .module = tm.trade_ticket },
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

    // Production demo module — same content, different instance so
    // system test binaries can share it without inheriting test-only
    // C source additions.
    const investment_demo_mod = b.createModule(.{
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

    // ---------------------------------------------------------------------------
    // Supervisor executable.
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = shared.version },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "doctor_checks", .module = shared.doctor_checks },
            .{ .name = "doctor_output", .module = shared.doctor_output },
            .{ .name = "demo_preflight", .module = shared.demo_preflight },
            .{ .name = "demo_cli", .module = shared.demo_cli },
            .{ .name = "demo_conformance", .module = shared.demo_conformance },
            .{ .name = "demo_comparator", .module = shared.demo_comparator },
            .{ .name = "demo_runner", .module = shared.demo_runner },
            .{ .name = "demo_substitution", .module = shared.demo_substitution },
            .{ .name = "logger", .module = shared.logger },
        },
    });
    const exe = b.addExecutable(.{
        .name = "tickoni-supervisor",
        .root_module = main_mod,
    });
    if (target.result.os.tag == .windows) {
        exe.root_module.linkLibrary(codec.addTickoniSupervisorShimLibrary(b, target, optimize));
        codec.addWindowsFdManifestFixups(b, exe, b.fmt("{s}/fd_windows_zig_supervisor_link.txt", .{fd_lib_dir}));
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    } else if (target.result.cpu.arch == .aarch64) {
        // ARM64 Linux: use explicit archive paths (like Windows) to preserve link order
        // with ld.lld, and link libatomic for ARM64 CAS intrinsics.
        codec.linkTickoniCodec(b, exe, fd_lib_dir);
        firedancer.linkTickoniFiredancer(b, exe, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, exe, fd_lib_dir);
        tile_run.linkTickoniTileRun(b, exe, fd_lib_dir);
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
        exe.root_module.linkSystemLibrary("atomic", .{});
    } else {
        codec.linkTickoniCodec(b, exe, fd_lib_dir);
        firedancer.linkTickoniFiredancer(b, exe, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, exe, fd_lib_dir);
        tile_run.linkTickoniTileRun(b, exe, fd_lib_dir);
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
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
    // Fixture path verification step — ensures all fixture directories and
    // proto files referenced by fixture_paths build_options actually exist on
    // disk at build time.  Catches missing fixtures before running tests.
    // ---------------------------------------------------------------------------
    const verify_fixture_step = b.step("verify-fixture-paths", "Verify all fixture paths exist");
    verify_fixture_step.dependOn(check_step);

    // Fixture directories and proto files to verify at build time.
    const fixture_dirs = comptime [_][]const u8{
        "src/tickoni/test/fixtures/investment/scenarios",
        "src/tickoni/test/fixtures/portfolio",
        "src/tickoni/schema/proto/classification/classification.proto",
        "src/tickoni/schema/proto/consumer_money/thesis.proto",
        "src/tickoni/schema/proto/consumer_money/basket.proto",
    };

    inline for (fixture_dirs) |path| {
        const exists = b.addSystemCommand(&.{ "test", "-e", path });
        exists.step.dependOn(check_step);
    }

    // Diagnostic C compile-check: compiles each shim file individually and
    // prints errors to stdout (not stderr) so CI can surface them.
    const c_compile_check_step = b.step("check-c-compile", "Compile-check all C shim files and print errors to stdout");
    inline for (shims.shim_c_files) |shim_file| {
        const c_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -std=c17 -UBMI2 -ULZCNT -DFD_HAS_HOSTED=1 {s} {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                b.fmt("src/tickoni/c_abi/shim/{s}", .{shim_file}),
            }),
        });
        c_compile_check_step.dependOn(&c_check.step);
    }
    // Bug Fix #50: compile-check the getrandom() EINTR + short-read retry loop test.
    {
        const getrandom_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -I src/util -I src/disco -I src/ballet -std=c17 -DFD_HAS_HOSTED=1 {s} {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                "src/util/shmem/test_fd_shmem_getrandom.c",
            }),
        });
        c_compile_check_step.dependOn(&getrandom_check.step);
    }
    check_step.dependOn(c_compile_check_step);

    // ---------------------------------------------------------------------------
    // Unit test registration — standalone test binaries + tests with module
    // cross-imports. Test modules that need codec/Firedancer linkage get it
    // via linkTickoniCodec / linkTickoniFiredancer calls below.
    // ---------------------------------------------------------------------------
    // Bug Fix #50: compile-check the getrandom() EINTR + short-read retry loop test.
    {
        const getrandom_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -I src/util -I src/disco -I src/ballet -std=c17 -DFD_HAS_HOSTED=1 {s} {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                "src/util/shmem/test_fd_shmem_getrandom.c",
            }),
        });
        c_compile_check_step.dependOn(&getrandom_check.step);
    }

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
        // Use absolute path so the script works regardless of zig's working directory.
        // In Zig 0.17, b.root is a Cache.Path; use toString() to get a string path.
        const build_root_str = b.root.toString(b.allocator) catch unreachable;
        defer b.allocator.free(build_root_str);
        var script_buf: [4096]u8 = undefined;
        const full_script_path = std.fmt.bufPrint(
            &script_buf,
            "{s}/contrib/test/run_test_series.sh",
            .{build_root_str},
        ) catch unreachable;
        run_tests_cmd.addArgs(&[_][]const u8{
            "bash",
            full_script_path,
        });
        run_tests_cmd.setCwd(b.path("."));

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
                    .{ .name = "doctor_checks", .module = shared.doctor_checks },
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
                    .{ .name = "logger", .module = shared.logger },
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
                    .{ .name = "demo_manifest", .module = shared.demo_manifest },
                    .{ .name = "demo_semver", .module = shared.demo_semver },
                    .{ .name = "diagnostic", .module = shared.demo_diagnostic },
                    .{ .name = "tier", .module = shared.tier },
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
                    .{ .name = "diagnostic", .module = shared.demo_diagnostic },
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
                    .{ .name = "conformance", .module = shared.demo_conformance },
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
                    .{ .name = "conformance", .module = shared.demo_conformance },
                    .{ .name = "diagnostic", .module = shared.demo_diagnostic },
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
                    .{ .name = "diagnostic", .module = shared.demo_diagnostic },
                    .{ .name = "runner", .module = shared.demo_runner },
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
                    .{ .name = "thesis", .module = shared.thesis },
                    .{ .name = "basket", .module = shared.basket },
                },
            }),
        });
        codec.linkTickoniCodec(b, thesis_codec_test, fd_lib_dir);
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
                    .{ .name = "classification", .module = shared.classification },
                    .{ .name = "c_abi", .module = shared.c_abi },
                    .{ .name = "fixture_paths", .module = shared.fixture_paths },
                },
            }),
        });
        codec.linkTickoniCodec(b, thesis_test, fd_lib_dir);
        test_step.dependOn(&thesis_test.step);
        run_tests_cmd.addArtifactArg(thesis_test);

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
        run_tests_cmd.addArtifactArg(catalog_test);

        // logger.zig: structured, env-driven Zig logger with module filtering,
        // colors, and flush — unit tests for level parsing, module filter,
        // KV output, colorize detection, and enter/exit tracing.
        const logger_test = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/logger.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = shared.util }},
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
                    .{ .name = "thesis", .module = shared.thesis },
                },
            }),
        });
        codec.linkTickoniCodec(b, catalog_schema_test, fd_lib_dir);
        test_step.dependOn(&catalog_schema_test.step);
        run_tests_cmd.addArtifactArg(catalog_schema_test);

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
        run_tests_cmd.addArtifactArg(basket_test);

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
        run_tests_cmd.addArtifactArg(portfolio_test);

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
        run_tests_cmd.addArtifactArg(fixture_portfolio_test);
        const model_messages_test = b.addTest(.{ .root_module = tm.model_messages });
        test_step.dependOn(&model_messages_test.step);
        run_tests_cmd.addArtifactArg(model_messages_test);
        const mock_model_test = b.addTest(.{ .root_module = tm.mock_model });
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
                    .{ .name = "c_abi", .module = shared.c_abi },
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
                    .{ .name = "c_abi", .module = shared.c_abi },
                },
            }),
        });
        firedancer.linkTickoniFiredancer(b, cnc_counters_test, fd_lib_dir);
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
                    .{ .name = "util", .module = shared.util },
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
                    .{ .name = "c_abi", .module = shared.c_abi },
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
                    .{ .name = "c_abi", .module = shared.c_abi },
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
            .flags = shims.shimCFlagsFor(_topo_test_target),
        });
        firedancer.linkTickoniFiredancer(b, topo_run_test, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, topo_run_test, fd_lib_dir);
        tile_run.linkTickoniTileRun(b, topo_run_test, fd_lib_dir);
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
        firedancer.linkTickoniFiredancer(b, topob_test, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, topob_test, fd_lib_dir);
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
                    .{ .name = "c_abi", .module = shared.c_abi },
                    .{ .name = "util", .module = shared.util },
                },
            }),
        });
        firedancer.linkTickoniFiredancer(b, topo_build_test, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, topo_build_test, fd_lib_dir);
        test_step.dependOn(&topo_build_test.step);
        run_tests_cmd.addArtifactArg(topo_build_test);

        // model tile: unit tests are mock/fixture-backed and must not start servers.
        const model_test_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = tm.model_messages },
                .{ .name = "mock_model", .module = tm.mock_model },
                .{ .name = "c_abi", .module = shared.c_abi },
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
                    .{ .name = "model_messages", .module = tm.model_messages },
                    .{ .name = "mock_model", .module = tm.mock_model },
                    .{ .name = "c_abi", .module = shared.c_abi },
                    .{ .name = "fixture_paths", .module = shared.fixture_paths },
                },
            }),
        });
        codec.linkTickoniCodec(b, model_test, fd_lib_dir);
        test_step.dependOn(&model_test.step);
        run_tests_cmd.addArtifactArg(model_test);

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
        const adapter_test = b.addTest(.{
            .root_module = adapter_test_mod,
        });
        test_step.dependOn(&adapter_test.step);
        run_tests_cmd.addArtifactArg(adapter_test);
        const mock_adapter_test = b.addTest(.{ .root_module = tm.mock_adapter });
        test_step.dependOn(&mock_adapter_test.step);
        run_tests_cmd.addArtifactArg(mock_adapter_test);

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
        run_tests_cmd.addArtifactArg(trade_ticket_test);

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
        run_tests_cmd.addArtifactArg(impact_test);

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
        run_tests_cmd.addArtifactArg(cards_test);

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
        run_tests_cmd.addArtifactArg(drift_test);

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
        run_tests_cmd.addArtifactArg(allowed_trade_fixture_test);

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
        run_tests_cmd.addArtifactArg(denied_trade_fixture_test);

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
                    .{ .name = "mock_adapter", .module = tm.mock_adapter },
                    .{ .name = "basket", .module = shared.basket },
                    .{ .name = "disp", .module = disp_unit_mod },
                    .{ .name = "model", .module = model_test_mod },
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
        run_tests_cmd.addArtifactArg(agent_test);

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
                    .{ .name = "model", .module = model_test_mod },
                    .{ .name = "portfolio", .module = shared.portfolio },
                    .{ .name = "tkpoly", .module = tkpoly_test_mod },
                    .{ .name = "trade_ticket", .module = tm.trade_ticket },
                    .{ .name = "fixture_paths", .module = shared.fixture_paths },
                },
            }),
        });
        codec.linkTickoniCodec(b, replay_test, fd_lib_dir);
        test_step.dependOn(&replay_test.step);
        run_tests_cmd.addArtifactArg(replay_test);

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
        // Named module (vs. sup_mod's anonymous instance above) so
        // src/tickoni/test/integration process-mode tests can import the
        // Supervisor type without a cross-tree relative path.
        const supervisor_named_mod = b.addModule("supervisor", .{
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
        run_tests_cmd.addArtifactArg(sup_test);

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
        run_tests_cmd.addArtifactArg(tile_registry_test);

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

        // Schema modules are shared (shared.thesis, shared.basket, shared.portfolio, etc.).
        // Integration tile modules are fresh instances so they don't inherit any
        // C source additions from the unit test lane.
        codec.linkTickoniCodec(b, investment_demo_test, fd_lib_dir);
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
                        .{ .name = "audit_tile", .module = tm.audit_tile },
                        .{ .name = "basket", .module = shared.basket },
                        .{ .name = "investment_audit", .module = investment_audit_int_mod },
                        .{ .name = "investment_support", .module = investment_support_int_mod },
                        .{ .name = "model", .module = model_int_mod },
                        .{ .name = "portfolio", .module = shared.portfolio },
                        .{ .name = "replay", .module = replay_int_mod },
                        .{ .name = "thesis", .module = shared.thesis },
                        .{ .name = "tkpoly", .module = tkpoly_int_mod },
                        .{ .name = "tool", .module = tool_int_mod },
                        .{ .name = "trade_ticket", .module = tm.trade_ticket },
                        .{ .name = "tkcase", .module = case_int_mod },
                        .{ .name = "tkdisp", .module = disp_int_mod },
                        .{ .name = "tkagnt", .module = agent_int_mod },
                    },
                }),
            });
            codec.linkTickoniCodec(b, integration_test, fd_lib_dir);
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
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_pipeline_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_pipeline_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_pipeline_test, fd_lib_dir);
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
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_cpu_placement_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_cpu_placement_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_cpu_placement_test, fd_lib_dir);
            const run_process_cpu_placement_test = addPlainTestRun(b, process_cpu_placement_test);
            run_process_cpu_placement_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_cpu_placement_test.step);

            const process_cpu_placement_linux_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_cpu_placement_linux.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_cpu_placement_linux_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_cpu_placement_linux_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_cpu_placement_linux_test, fd_lib_dir);
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
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_topology_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_topology_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_topology_test, fd_lib_dir);
            const run_process_topology_test = addPlainTestRun(b, process_topology_test);
            run_process_topology_test.step.dependOn(&process_mode_exe_install.step);
            integration_step.dependOn(&run_process_topology_test.step);

            const process_topology_linux_test = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/tickoni/test/integration/test_process_topology_linux.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_topology_linux_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_topology_linux_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_topology_linux_test, fd_lib_dir);
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
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                        .{ .name = "supervisor", .module = supervisor_named_mod },
                        .{ .name = "topologies", .module = shared.topologies },
                    },
                }),
            });
            codec.linkTickoniCodec(b, process_demo_parity_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, process_demo_parity_test, fd_lib_dir);
            topo_run.linkTickoniTopoRun(b, process_demo_parity_test, fd_lib_dir);
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
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "util", .module = shared.util },
                    },
                }),
            });
            codec.linkTickoniCodec(b, link_bounds_test, fd_lib_dir);
            firedancer.linkTickoniFiredancer(b, link_bounds_test, fd_lib_dir);
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
                    .{ .name = "audit_tile", .module = tm.audit_tile },
                    .{ .name = "basket", .module = shared.basket },
                    .{ .name = "investment_demo", .module = investment_demo_mod },
                    .{ .name = "investment_audit", .module = investment_audit_int_mod },
                    .{ .name = "investment_support", .module = investment_support_int_mod },
                    .{ .name = "model", .module = model_int_mod },
                    .{ .name = "portfolio", .module = shared.portfolio },
                    .{ .name = "replay", .module = replay_int_mod },
                    .{ .name = "thesis", .module = shared.thesis },
                    .{ .name = "tkpoly", .module = tkpoly_int_mod },
                    .{ .name = "tool", .module = tool_int_mod },
                    .{ .name = "trade_ticket", .module = tm.trade_ticket },
                    .{ .name = "tkcase", .module = case_int_mod },
                    .{ .name = "tkdisp", .module = disp_int_mod },
                    .{ .name = "tkagnt", .module = agent_int_mod },
                },
            }),
        });
        // Imported modules do not propagate their root-module link settings to
        // this test binary. Reuse the codec seam directly so Windows links the
        // concrete archives instead of invoking pkg-config for fd_ballet/fd_util.
        codec.linkTickoniCodec(b, replay_integration_test, fd_lib_dir);
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
        codec.linkTickoniCodec(b, decision_cards_integration_test, fd_lib_dir);
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
        codec.linkTickoniCodec(b, system_test, fd_lib_dir);
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
        codec.linkTickoniCodec(b, portfolio_cash_demo_test, fd_lib_dir);
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
            .{ .name = "tier", .module = shared.tier },
            .{ .name = "doctor_output", .module = shared.doctor_output },
            .{ .name = "demo_manifest", .module = shared.demo_manifest },
            .{ .name = "demo_preflight", .module = shared.demo_preflight },
            .{ .name = "version", .module = shared.version },
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
        cli_exe.root_module.linkLibrary(codec.addTickoniCodecShimLibrary(b, target, optimize, "tickoni-codec-shims"));
        codec.addWindowsFdManifestFixups(b, cli_exe, b.fmt("{s}/fd_windows_zig_codec_link.txt", .{fd_lib_dir}));
        codec.addTickoniSystemLibraries(b, cli_exe, fd_lib_dir, &.{ "fd_ballet", "fd_util" });
        // crypt32 is a Windows system library, not a pkg-config dependency.
        cli_exe.root_module.linkSystemLibrary("crypt32", .{ .use_pkg_config = .no });
    } else {
        codec.linkTickoniCodec(b, cli_exe, fd_lib_dir);
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
                        .{ .name = "audit_codec", .module = shared.audit_codec },
                        .{ .name = "audit_schema", .module = shared.audit_schema },
                        .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/tiles/payment_pipeline/mod.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "audit_tile", .module = tm.audit_tile },
                        .{ .name = "runtime", .module = shared.runtime },
                        .{ .name = "c_abi", .module = shared.c_abi },
                        .{ .name = "logger", .module = shared.logger },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/cnc_counters.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "c_abi", .module = shared.c_abi },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/cpu_placement.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "util", .module = shared.util },
                    },
                })
            else if (std.mem.eql(u8, entry[1], "src/tickoni/runtime/sandbox.zig"))
                b.createModule(.{
                    .root_source_file = b.path(entry[1]),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "util", .module = shared.util },
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
            codec.linkTickoniCodec(b, t, fd_lib_dir);
            // Logger imports util -> c_abi.os which needs shim/os.c
            firedancer.linkTickoniFiredancer(b, t, fd_lib_dir);
        }
        if (std.mem.eql(u8, entry[1], "src/tickoni/c_abi/queue.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/dcache.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/fseq.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/fctl.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/cnc.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/c_abi/tempo.zig") or
            std.mem.eql(u8, entry[1], "src/tickoni/runtime/cnc_counters.zig"))
        {
            firedancer.linkTickoniFiredancer(b, t, fd_lib_dir);
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
                .{ .name = "classification", .module = shared.classification },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, thesis_cov_test, fd_lib_dir);
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
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "classification", .module = shared.classification },
                .{ .name = "catalog_schema", .module = shared.catalog_schema },
            },
        }),
    });
    codec.linkTickoniCodec(b, catalog_cov_test, fd_lib_dir);
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
                .{ .name = "thesis", .module = shared.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, catalog_schema_cov_test, fd_lib_dir);
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
                .{ .name = "basket", .module = shared.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, portfolio_cov_test, fd_lib_dir);
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
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "basket", .module = shared.basket },
            },
        }),
    });
    codec.linkTickoniCodec(b, fixture_portfolio_cov_test, fd_lib_dir);
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
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
                .{ .name = "thesis", .module = shared.thesis },
            },
        }),
    });
    codec.linkTickoniCodec(b, trade_ticket_cov_test, fd_lib_dir);
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
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
            },
        }),
    });
    codec.linkTickoniCodec(b, impact_cov_test, fd_lib_dir);
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
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "catalog", .module = shared.catalog },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        }),
    });
    codec.linkTickoniCodec(b, basket_cov_test, fd_lib_dir);
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
                .{ .name = "runtime", .module = shared.runtime },
                .{ .name = "tiles", .module = shared.tiles },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "util", .module = shared.util },
                .{ .name = "topologies", .module = shared.topologies },
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
    run_step.setCwd(b.path("."));
    return run_step;
}