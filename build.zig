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
const helpers = @import("build-lib/lib/helpers.zig");
const test_lanes = @import("build-lib/build_test_lanes.zig");

/// Validate a build-time path option: reject empty strings, path traversal,
/// and paths exceeding a reasonable length to prevent linking arbitrary archives.
fn validateBuildPath(path: []const u8) ![]const u8 {
    if (path.len == 0) return error.InvalidBuildPath;
    if (path.len > 1024) return error.PathTooLong;
    if (std.mem.indexOf(u8, path, "..") != null) return error.PathTraversal;
    return path;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = validateBuildPath(b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/fd-tickoni-fd/lib)") orelse "build/fd-tickoni-fd/lib") catch {
        std.debug.print("error: Invalid --fd-lib-dir: must be a non-empty, non-absolute path under 1024 chars without '..' components\n", .{});
        return;
    };
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;

    const shared = @import("build-lib/mod/modules.zig").modules(b, target, optimize);
    const tm = @import("build-lib/mod/test_modules.zig").testModules(b, target, optimize, shared);

    // Supervisor executable
    const exe = helpers.createSupervisorExe(b, shared, target, optimize, fd_lib_dir);
    const exe_install = b.addInstallArtifact(exe, .{});

    const run_exe = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |argv| run_exe.addArgs(argv);
    }
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // Check + fixture verification
    const check_step = helpers.createCheckStep(b, target);
    helpers.createVerifyFixtureStep(b, check_step);

    if (build_tests) {
        // CLI executable — needs the investment demo module with its
        // full import graph. Create the tile modules that the demo
        // depends on here (same modules that factory.zig creates for
        // integration tests).
        const adapter_messages_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/adapter/messages.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
            },
        });
        const model_messages_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/messages.zig"),
            .target = target,
            .optimize = optimize,
        });
        const mock_model_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/mocks/mock_model.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = model_messages_mod },
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
                .{ .name = "adapter_messages", .module = adapter_messages_mod },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        });
        const model_int_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/model/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "model_messages", .module = model_messages_mod },
                .{ .name = "mock_model", .module = mock_model_mod },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "fixture_paths", .module = shared.fixture_paths },
            },
        });
        const tkpoly_int_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/tiles/policy/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
                .{ .name = "c_abi", .module = shared.c_abi },
                .{ .name = "audit_codec", .module = shared.audit_codec },
                .{ .name = "audit_schema", .module = shared.audit_schema },
                .{ .name = "runtime", .module = shared.runtime },
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
        const investment_support_mod = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/demo/investment/support.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "basket", .module = shared.basket },
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
            },
        });
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
                .{ .name = "investment_support", .module = investment_support_mod },
                .{ .name = "model", .module = model_int_mod },
                .{ .name = "portfolio", .module = shared.portfolio },
                .{ .name = "replay", .module = replay_int_mod },
                .{ .name = "thesis", .module = shared.thesis },
                .{ .name = "tkpoly", .module = tkpoly_int_mod },
                .{ .name = "tool", .module = tool_int_mod },
                .{ .name = "trade_ticket", .module = tm.trade_ticket },
            },
        });
        const cli_exe = helpers.createCliExe(b, investment_demo_mod, shared, target, optimize, fd_lib_dir);
        b.installArtifact(cli_exe);
        const run_cli_step = b.step("run-cli", "Run tickoni demo CLI");
        run_cli_step.dependOn(&b.addRunArtifact(cli_exe).step);

        // Unit + integration + system lanes
        test_lanes.registerTestLanes(b, check_step, shared, tm, target, optimize, fd_lib_dir, exe, exe_install);
    }

    // Coverage lane (always available)
    const cov_step = b.step("cov", "Install Zig test binaries to zig-out/cov/ for kcov coverage");
    test_lanes.registerCovLane(b, cov_step, shared, tm, target, optimize, fd_lib_dir);
}
