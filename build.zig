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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/fd-tickoni-fd/lib)") orelse "build/fd-tickoni-fd/lib";
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;

    const shared = @import("build-lib/mod/modules.zig").modules(b, target, optimize);
    const tm = @import("build-lib/mod/test_modules.zig").testModules(b, target, optimize, shared);

    // Supervisor executable
    const exe = helpers.createSupervisorExe(b, shared, target, optimize, fd_lib_dir);
    b.installArtifact(exe);

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
        // CLI executable (requires investment_demo_mod from integration lane)
        const cli_exe = helpers.createCliExe(b, exe, shared, target, optimize, fd_lib_dir);
        b.installArtifact(cli_exe);
        const run_cli_step = b.step("run-cli", "Run tickoni demo CLI");
        run_cli_step.dependOn(&b.addRunArtifact(cli_exe).step);

        // Unit + integration + system lanes
        test_lanes.registerTestLanes(b, check_step, shared, tm, target, optimize, fd_lib_dir, exe);
    }

    // Coverage lane (always available)
    const cov_step = b.step("cov", "Install Zig test binaries to zig-out/cov/ for kcov coverage");
    test_lanes.registerCovLane(b, cov_step, shared, tm, target, optimize, fd_lib_dir);
}
