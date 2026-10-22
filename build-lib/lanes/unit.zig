/// Unit test lane strategy — spec-driven.
///
/// Collects compile steps in a `run_sequence` array, then chains them all
/// sequentially via `shims.addPlainTestRunSeries`. This avoids Zig 0.17's
/// protocol-mode `--listen=-` which blocks on stdin.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const factory = @import("../factory.zig");
const lane = @import("../lane.zig");
const firedancer = @import("../lib/firedancer.zig");
const shared_mod = @import("../mod/modules.zig");
const test_mod = @import("../mod/test_modules.zig");

/// Register all unit test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    shared: shared_mod.Shared,
    tm: test_mod.TestModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    test_step: *std.Build.Step,
) void {
    const int_mods = factory.ModuleFactory.init(b, shared, tm, target, optimize).createIntModules(null);

    // Collect all compile steps for sequential run.
    var run_sequence: [38]*std.Build.Step.Compile = undefined;
    var run_count: usize = 0;

    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // === Tile-based unit tests ===

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-topology",
        .source_file = "src/tickoni/runtime/topology.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-tile",
        .source_file = "src/tickoni/runtime/tile.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cpu",
        .source_file = "src/tickoni/util/cpu.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-process",
        .source_file = "src/tickoni/util/process.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-supervisor-lifecycle",
        .source_file = "src/app/tickoni/supervisor.zig",
        .imports = &.{
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "logger", .module = shared.logger },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true, .needs_topo_run = true },
    });
    run_count += 1;

    // test-process-api — needs c_abi module, util module, and os.c shim (libc).
    {
        const pa_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/test_process_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "util", .module = shared.util },
            },
        });
        pa_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/c_abi/shim/os.c"} });
        pa_mod.addCMacro("TK_PROCESS_TEST", "1");
        switch (target.result.os.tag) {
            .linux    => pa_mod.addCMacro("FD_HAS_LINUX",    "1"),
            .macos    => pa_mod.addCMacro("FD_HAS_MACOS",    "1"),
            .windows  => pa_mod.addCMacro("FD_HAS_WINDOWS",  "1"),
            else      => {},
        }
        if (target.result.os.tag == .windows) {
            pa_mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
        }
        pa_mod.link_libc = true;
        const pa_test = b.addTest(.{ .name = "test-process-api", .root_module = pa_mod });
        test_step.dependOn(&pa_test.step);
        run_sequence[run_count] = pa_test;
        run_count += 1;
    }

    // test-os-shim — tests for os.c cross-platform shim functions.
    {
        const os_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/c_abi/os.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        });
        os_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/c_abi/shim/os.c"} });
        os_mod.addCMacro("TK_PROCESS_TEST", "1");
        switch (target.result.os.tag) {
            .linux    => os_mod.addCMacro("FD_HAS_LINUX",    "1"),
            .macos    => os_mod.addCMacro("FD_HAS_MACOS",    "1"),
            .windows  => os_mod.addCMacro("FD_HAS_WINDOWS",  "1"),
            else      => {},
        }
        if (target.result.os.tag == .windows) {
            os_mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
        }
        os_mod.link_libc = true;
        const os_test = b.addTest(.{ .name = "test-os-shim", .root_module = os_mod });
        test_step.dependOn(&os_test.step);
        run_sequence[run_count] = os_test;
        run_count += 1;

        // Top-level step so `zig build test-os-shim` works standalone.
        const os_shim_step = b.step("test-os-shim", "Run os.c cross-platform shim unit tests");
        os_shim_step.dependOn(&os_test.step);
    }

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sandbox-defaults",
        .source_file = "src/tickoni/util/sandbox_defaults.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-linux-ids",
        .source_file = "src/tickoni/util/linux_ids.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sizes",
        .source_file = "src/tickoni/util/sizes.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cabi-boot",
        .source_file = "src/tickoni/c_abi/boot.zig",
    });
    run_count += 1;

    // tier.zig — needs C source (compiler_version.c) and libc.
    {
        const tier_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/util/tier.zig"),
            .target = target,
            .optimize = optimize,
        });
        tier_mod.addCSourceFiles(.{ .files = &.{"src/tickoni/util/compiler_version.c"} });
        tier_mod.link_libc = true;
        const tier_test = b.addTest(.{ .name = "test-tier", .root_module = tier_mod });
        test_step.dependOn(&tier_test.step);
        run_sequence[run_count] = tier_test;
        run_count += 1;
    }

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
        run_sequence[run_count] = tb.registerRunTest(.{
            .name = t.name,
            .source_file = t.path,
            .linkage = .{ .needs_firedancer = true },
        });
        run_count += 1;

        // Top-level step so `zig build <name>` works standalone.
        if (std.mem.eql(u8, t.name, "test-wksp")) {
            const wksp_mod = b.createModule(.{
                .root_source_file = b.path(t.path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "c_abi", .module = shared.c_abi }},
            });
            const wksp_test = b.addTest(.{ .name = t.name, .root_module = wksp_mod });
            firedancer.linkTickoniFiredancer(b, wksp_test, fd_lib_dir);
            const wksp_step = b.step("test-wksp", "Run workspace C shim unit tests");
            wksp_step.dependOn(&wksp_test.step);
        }
    }

    // ballet.zig — needs codec linkage (siphash/pb/json in shim/ballet.c).
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cabi-ballet",
        .source_file = "src/tickoni/c_abi/ballet.zig",
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // sandbox.zig — needs util import.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-sandbox",
        .source_file = "src/tickoni/runtime/sandbox.zig",
        .imports = &.{.{ .name = "util", .module = shared.util }},
    });
    run_count += 1;

    // === Tile tests with special linkage ===

    // audit/mod.zig — needs audit_codec, audit_schema, fixture_audit_gen.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-audit",
        .source_file = "src/tickoni/tiles/audit/mod.zig",
        .imports = &.{
            .{ .name = "audit_codec", .module = shared.audit_codec },
            .{ .name = "audit_schema", .module = shared.audit_schema },
            .{ .name = "fixture_audit_gen", .module = tm.fixture_audit_gen },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    });
    run_count += 1;

    // payment_pipeline/mod.zig — needs audit_tile, runtime, c_abi, logger, util.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-payment-pipeline",
        .source_file = "src/tickoni/tiles/payment_pipeline/mod.zig",
        .imports = &.{
            .{ .name = "audit_tile", .module = tm.audit_tile },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "logger", .module = shared.logger },
            .{ .name = "util", .module = shared.util },
        },
        .linkage = .{ .needs_codec = true, .needs_firedancer = true },
    });
    run_count += 1;

    // case/mod.zig — standalone.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-case",
        .source_file = "src/tickoni/tiles/case/mod.zig",
    });
    run_count += 1;

    // disp/mod.zig — standalone.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-disp",
        .source_file = "src/tickoni/tiles/disp/mod.zig",
    });
    run_count += 1;

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
        run_sequence[run_count] = v_test;
        run_count += 1;
    }

    // === Schema tests (all need codec linkage) ===

    // codec/thesis.zig — thesis, basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-codec-thesis",
        .source_file = "src/tickoni/codec/thesis.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/thesis.zig — classification, c_abi, fixture_paths.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-thesis",
        .source_file = "src/tickoni/schema/consumer_money/thesis.zig",
        .imports = &.{
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/catalog.zig — thesis, classification, catalog_schema.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-catalog",
        .source_file = "src/tickoni/schema/consumer_money/catalog.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "classification", .module = shared.classification },
            .{ .name = "catalog_schema", .module = shared.catalog_schema },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/catalog_schema.zig — thesis.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-catalog-schema",
        .source_file = "src/tickoni/schema/consumer_money/catalog_schema.zig",
        .imports = &.{.{ .name = "thesis", .module = shared.thesis }},
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/portfolio.zig — basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-portfolio",
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .imports = &.{.{ .name = "basket", .module = shared.basket }},
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // test/fixtures/portfolio/fixture_portfolio.zig — portfolio, basket.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-fixture-portfolio",
        .source_file = "src/tickoni/test/fixtures/portfolio/fixture_portfolio.zig",
        .imports = &.{
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "basket", .module = shared.basket },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/trade_ticket.zig — basket, portfolio, fixture_portfolio, thesis.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-trade-ticket",
        .source_file = "src/tickoni/schema/consumer_money/trade_ticket.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
            .{ .name = "fixture_portfolio", .module = tm.fixture_portfolio },
            .{ .name = "thesis", .module = shared.thesis },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/impact.zig — basket, portfolio.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-impact",
        .source_file = "src/tickoni/schema/consumer_money/impact.zig",
        .imports = &.{
            .{ .name = "basket", .module = shared.basket },
            .{ .name = "portfolio", .module = shared.portfolio },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // schema/basket.zig — thesis, catalog, c_abi, fixture_paths.
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-basket",
        .source_file = "src/tickoni/schema/consumer_money/basket.zig",
        .imports = &.{
            .{ .name = "thesis", .module = shared.thesis },
            .{ .name = "catalog", .module = shared.catalog },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "fixture_paths", .module = shared.fixture_paths },
        },
        .linkage = .{ .needs_codec = true },
    });
    run_count += 1;

    // === Logger test (needs os.c shim) ===
    {
        const logger_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/logger.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "util", .module = shared.util }},
        });
        logger_mod.addCSourceFiles(.{
            .files = &.{ "src/tickoni/c_abi/shim/os.c" },
            .flags = &.{ "-std=c17" },
        });
        switch (target.result.os.tag) {
            .linux    => logger_mod.addCMacro("FD_HAS_LINUX",    "1"),
            .macos    => logger_mod.addCMacro("FD_HAS_MACOS",    "1"),
            .windows  => logger_mod.addCMacro("FD_HAS_WINDOWS",  "1"),
            else      => {},
        }
        if (target.result.os.tag == .windows) {
            logger_mod.linkSystemLibrary("ws2_32", .{ .use_pkg_config = .no });
        }
        logger_mod.linkSystemLibrary("c", .{});
        const logger_test = b.addTest(.{ .name = "test-logger", .root_module = logger_mod });
        test_step.dependOn(&logger_test.step);
        run_sequence[run_count] = logger_test;
        run_count += 1;
    }

    // === Investment fixture test (needs codec linkage) ===

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-investment-fixture",
        .source_file = "src/tickoni/test/fixtures/investment/mod.zig",
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
    });
    run_count += 1;

    // Top-level step: compile and run all TK unit tests sequentially.
    // Uses shims.addPlainTestRunSeries which avoids Zig 0.17 protocol-mode.
    const test_unit_tk_run = shims.addPlainTestRunSeries(b, run_sequence[0..run_count]);
    const test_unit_tk_step = b.step("test-unit-tk", "Compile and run all TK unit tests sequentially");
    test_unit_tk_step.dependOn(&test_unit_tk_run.step);
}
