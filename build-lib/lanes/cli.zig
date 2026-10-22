/// CLI test lane strategy — registers unit tests
/// (`test-unit-cli-doctor-checks`, `test-unit-cli-doctor-output`,
/// `test-unit-cli-parser`) and integration tests
/// (`test-integration-cli-main`) for the CLI binary.
///
/// The CLI test modules are standalone (no firedancer/codec linkage).
/// Integration tests spawn the compiled `tickoni` binary, which is
/// already installed by `build-tk` (part of `build-all`).
///
/// Doctor tests run against the actual host environment (fixture files,
/// OS checks) rather than the sandboxed unit-test context.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const lane = @import("../lane.zig");

/// Register CLI test binaries. Called from build_test_lanes.zig.
pub fn strategy(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    shared: anytype,
    cli_exe_install: ?*std.Build.Step.InstallArtifact,
) void {
    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // =========================================================================
    // Unit tests — compile and run sequentially via test-unit-cli.
    // =========================================================================
    var unit_sequence: [3]*std.Build.Step.Compile = undefined;
    var unit_count: usize = 0;

    // test-unit-cli-doctor-checks — doctor platform/OS/environment checks.
    unit_sequence[unit_count] = tb.registerRunTest(.{
        .name = "test-unit-cli-doctor-checks",
        .source_file = "src/tickoni/doctor/checks.zig",
    });
    unit_count += 1;

    // test-unit-cli-doctor-output — doctor output formatting (plain/json).
    unit_sequence[unit_count] = tb.registerRunTest(.{
        .name = "test-unit-cli-doctor-output",
        .source_file = "src/tickoni/doctor/output.zig",
        .imports = &.{.{ .name = "doctor_checks", .module = shared.doctor_checks }},
    });
    unit_count += 1;

    // test-unit-cli-parser — CLI argument parsing (standalone, no linkage).
    unit_sequence[unit_count] = tb.registerRunTest(.{
        .name = "test-unit-cli-parser",
        .source_file = "src/app/tickoni_cli/cli.zig",
    });
    unit_count += 1;

    // test-unit-cli — run all CLI unit tests sequentially.
    const unit_step = b.step("test-unit-cli", "Run CLI unit tests (doctor checks/output, parser)");
    if (unit_count > 0) {
        const unit_run = shims.addPlainTestRunSeries(b, unit_sequence[0..unit_count]);
        unit_step.dependOn(&unit_run.step);
    }

    // =========================================================================
    // Integration tests — spawn the tickoni binary, assert on its output.
    // =========================================================================
    const cli_int_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni_cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });
    const cli_int_test = b.addTest(.{
        .name = "test-integration-cli-main",
        .root_module = cli_int_mod,
    });

    // test-integration-cli — run integration tests standalone.
    const cli_int_run = b.addRunArtifact(cli_int_test);
    cli_int_run.stdio = .inherit;
    const int_step = b.step("test-integration-cli", "Run CLI integration tests (spawn tickoni binary)");
    int_step.dependOn(&cli_int_run.step);
    if (cli_exe_install) |inst| int_step.dependOn(&inst.step);
}
