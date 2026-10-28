/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run harness unit tests (separate from 'make run-unit-test'):
///   zig build test
///
/// Install Zig test binaries for kcov coverage and sanitizer checks (used by just compile-tk):
///   zig build compile-tk
///
/// The existing GNUmakefile (C/Firedancer build) is unchanged.

const std = @import("std");
const helpers = @import("build-lib/lib/helpers.zig");
const test_lanes = @import("build-lib/build_test_lanes.zig");
const perf_lane = @import("build-lib/lanes/perf.zig");

/// Validate a build-time path option: reject empty strings, path traversal,
/// and paths exceeding a reasonable length to prevent linking arbitrary archives.
fn validateBuildPath(path: []const u8) ![]const u8 {
    if (path.len == 0) return error.InvalidBuildPath;
    if (path.len > 1024) return error.PathTooLong;
    if (std.mem.indexOf(u8, path, "..") != null) return error.PathTraversal;
    return path;
}

/// Wire translate-c to import audit_schema.h directly into Zig at build time.
/// Returns the generated module so parity tests can compare C and Zig layouts
/// without manual matching. Uses Zig 0.18's built-in `b.addTranslateC()`.
fn addAuditSchemaTranslation(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const tc = b.addTranslateC(.{
        .root_source_file = b.path("src/tickoni/c_abi/shim/audit_schema.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    return tc.createModule();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fd_lib_dir = validateBuildPath(b.option([]const u8, "fd-lib-dir", "Firedancer lib dir (default: build/fd-tickoni-fd/lib)") orelse "build/fd-tickoni-fd/lib") catch {
        std.debug.print("error: Invalid --fd-lib-dir: must be a non-empty, non-absolute path under 1024 chars without '..' components\n", .{});
        return;
    };
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;
    const build_perf = b.option(bool, "perf", "Compile and run Tickoni performance test binaries") orelse false;

    const shared = @import("build-lib/mod/modules.zig").modules(b, target, optimize);
    const tm = @import("build-lib/mod/test_modules.zig").testModules(b, target, optimize, shared);

    // Supervisor executable
    const exe = helpers.createSupervisorExe(b, shared, target, optimize, fd_lib_dir);
    const exe_install = b.addInstallArtifact(exe, .{});
    b.default_step.dependOn(&exe_install.step);

    const run_exe = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |argv| run_exe.addArgs(argv);
    }
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // CLI executable — standalone, no firedancer/tile linkage.
    const cli_exe = helpers.createCliExe(b, shared, target, optimize, fd_lib_dir);
    const cli_exe_install = b.addInstallArtifact(cli_exe, .{});
    b.default_step.dependOn(&cli_exe_install.step);
    const run_cli_step = b.step("run-cli", "Run tickoni CLI");
    run_cli_step.dependOn(&b.addRunArtifact(cli_exe).step);

    // Lint check + fixture verification
    const lint_check_step = helpers.createCheckStep(b, target);
    helpers.createVerifyFixtureStep(b, lint_check_step);

    // Unit + integration + system lanes
    if (build_tests) {
        test_lanes.registerTestLanes(b, shared, tm, target, optimize, fd_lib_dir, exe, exe_install, cli_exe_install);
    }

    // Performance lane — always wired (not gated by -Dtest), so perf tests
    // can run independently without pulling in the full test suite.
    if (build_perf) {
        const perf_step = b.step("perf-test", "Run Tickoni performance tests (Linux-only)");
        perf_step.dependOn(&exe_install.step);
        perf_lane.strategy(b, .{
            .shared = shared,
            .fd_lib_dir = fd_lib_dir,
        }, target, optimize, perf_step);
    }

    // Coverage lane (always available)
    const cov_step = b.step("compile-tk", "Install Zig test binaries for kcov coverage and sanitizer checks");
    test_lanes.registerCovLane(b, cov_step, shared, tm, target, optimize, fd_lib_dir);
}
