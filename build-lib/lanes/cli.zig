/// CLI test lane strategy — registers `test-cli-parser` (unit),
/// `test-doctor-checks`, `test-doctor-output`, and `test-cli-main`
/// (integration) for the CLI binary.
///
/// The CLI test modules are standalone (no firedancer/codec linkage).
/// Integration tests spawn the compiled `tickoni` binary, which is
/// already installed by `build-tk` (part of `build-all`).
///
/// Doctor tests are here because they need to run against the actual
/// host environment (fixture files, OS checks), not the sandboxed
/// unit-test context.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const lane = @import("../lane.zig");

/// Register CLI test binaries. Called from build_test_lanes.zig.
pub fn strategy(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    shared: anytype,
) void {
    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // Collect all compile steps for sequential run.
    var run_sequence: [4]*std.Build.Step.Compile = undefined;
    var run_count: usize = 0;

    // === Doctor tests (host environment checks) ===

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-doctor-checks",
        .source_file = "src/tickoni/doctor/checks.zig",
    });
    run_count += 1;

    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-doctor-output",
        .source_file = "src/tickoni/doctor/output.zig",
        .imports = &.{.{ .name = "doctor_checks", .module = shared.doctor_checks }},
    });
    run_count += 1;

    // test-cli-parser — unit tests for cli.zig (standalone, no linkage).
    run_sequence[run_count] = tb.registerRunTest(.{
        .name = "test-cli-parser",
        .source_file = "src/app/tickoni_cli/cli.zig",
    });
    run_count += 1;

    // test-cli-main — integration tests that spawn the compiled tickoni binary.
    // The binary is expected in PATH (installed by build-tk, part of build-all).
    {
        const cli_main_mod = b.createModule(.{
            .root_source_file = b.path("src/app/tickoni_cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        });
        const cli_main_test = b.addTest(.{
            .name = "test-cli-main",
            .root_module = cli_main_mod,
        });

        test_step.dependOn(&cli_main_test.step);
        run_sequence[run_count] = cli_main_test;
        run_count += 1;
    }

    // Top-level step so `zig build test-unit-cli` compiles and runs CLI tests.
    const cli_test_step = b.step("test-unit-cli", "Compile and run CLI + doctor tests sequentially");
    if (run_count > 0) {
        const cli_run = shims.addPlainTestRunSeries(b, run_sequence[0..run_count]);
        cli_test_step.dependOn(&cli_run.step);
    }
}
