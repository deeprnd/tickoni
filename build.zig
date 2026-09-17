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
const shims = @import("build-lib/lib/shims.zig");
const codec = @import("build-lib/lib/codec.zig");
const firedancer = @import("build-lib/lib/firedancer.zig");
const topo_run = @import("build-lib/lib/topo_run.zig");
const tile_run = @import("build-lib/lib/tile_run.zig");
const build_mod = @import("build-lib/mod/modules.zig");
const test_mod = @import("build-lib/mod/test_modules.zig");
const build_lane = @import("build-lib/lanes/unit.zig");
const integration_lane = @import("build-lib/lanes/integration.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/fd-tickoni-fd/lib)") orelse "build/fd-tickoni-fd/lib";
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;

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
            .{ .name = "audit_tile", .module = shared.audit_tile },
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
    // Output .o files go into build/.zig-cache/o to keep the repo root clean.
    const c_compile_check_step = b.step("check-c-compile", "Compile-check all C shim files and print errors to stdout");
    const cache_o_dir = "build/.zig-cache/o";
    {
        const ensure_dir = b.addSystemCommand(&.{"mkdir", "-p", cache_o_dir});
        c_compile_check_step.dependOn(&ensure_dir.step);
    }
    inline for (shims.shim_c_files) |shim_file| {
        const c_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -std=c17 -UBMI2 -ULZCNT -DFD_HAS_HOSTED=1 {s} -o {s}/{s}.o {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                cache_o_dir,
                shim_file,
                b.fmt("src/tickoni/c_abi/shim/{s}", .{shim_file}),
            }),
        });
        c_compile_check_step.dependOn(&c_check.step);
    }
    // Bug Fix #50: compile-check the getrandom() EINTR + short-read retry loop test.
    {
        const getrandom_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -I src/util -I src/disco -I src/ballet -std=c17 -DFD_HAS_HOSTED=1 {s} -o {s}/test_fd_shmem_getrandom.o {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                cache_o_dir,
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

    if (build_tests) {
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

        // Delegate unit test registration to lane strategy.
        build_lane.strategy(b, shared, tm, target, optimize, fd_lib_dir, test_step, run_tests_cmd);

        // Named module so src/tickoni/test/integration process-mode tests can
        // import the Supervisor type without a cross-tree relative path.
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

        // ---------------------------------------------------------------------------
        // Integration-test step — transport and boundary wiring against local mocks.
        // Local mock HTTP servers live here; this lane must stay deterministic.
        // Run with: zig build integration-test
        // ---------------------------------------------------------------------------
        const integration_step = b.step("integration-test", "Run Tickoni mock-backed integration tests");

        // Mock HTTP servers (test/mocks): self-tests of the mock
        // infrastructure itself. Created before int_mods so they can
        // be referenced.
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

        // Delegate integration test registration to lane strategy.
        const int_mods = integration_lane.IntegrationModules{
            .tkpoly_int_mod = tkpoly_int_mod,
            .model_int_mod = model_int_mod,
            .adapter_int_mod = adapter_int_mod,
            .tool_int_mod = tool_int_mod,
            .case_int_mod = case_int_mod,
            .disp_int_mod = disp_int_mod,
            .agent_int_mod = agent_int_mod,
            .replay_int_mod = replay_int_mod,
            .investment_audit_int_mod = investment_audit_int_mod,
            .investment_support_int_mod = investment_support_int_mod,
            .investment_demo_test_mod = investment_demo_test_mod,
            .investment_demo_mod = investment_demo_mod,
            .supervisor_named_mod = supervisor_named_mod,
            .mock_http_support_mod = mock_http_support_mod,
            .mock_broker_market_server_mod = mock_broker_market_server_mod,
            .mock_openai_server_mod = mock_openai_server_mod,
            .exe = exe,
            // Shared schema modules — match build.zig shared instances to
            // avoid Zig 0.17 "file exists in modules X and X0" error.
            .shared_audit_tile = shared.audit_tile,
            .shared_basket = shared.basket,
            .shared_portfolio = shared.portfolio,
            .shared_thesis = shared.thesis,
            .shared_trade_ticket = tm.trade_ticket,
            .shared_runtime = shared.runtime,
            .shared_c_abi = shared.c_abi,
            .shared_util = shared.util,
            .shared_topologies = shared.topologies,
        };
        integration_lane.strategy(b, int_mods, target, optimize, fd_lib_dir, integration_step);

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