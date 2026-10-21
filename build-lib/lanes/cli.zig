/// CLI test lane strategy — registers `test-cli-parser` (unit) and
/// `test-cli-main` (integration) for the CLI binary.
///
/// The CLI test modules are standalone (no firedancer/codec linkage).
/// Integration tests spawn the compiled `tickoni` binary, so the lane
/// depends on `exe_install` to ensure the binary exists.

const std = @import("std");
const lane = @import("../lane.zig");

/// Register CLI test binaries. Called from build_test_lanes.zig.
pub fn strategy(
    b: *std.Build,
    test_step: *std.Build.Step,
    run_cmd: *std.Build.Step.Run,
    exe_install: *std.Build.Step.InstallArtifact,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    const tb = lane.TestBuilder{
        .b = b,
        .target = target,
        .optimize = optimize,
        .fd_lib_dir = fd_lib_dir,
    };

    // test-cli-parser — unit tests for cli.zig (standalone, no linkage).
    tb.registerRunTest(.{
        .name = "test-cli-parser",
        .source_file = "src/app/tickoni_cli/cli.zig",
    }, test_step, run_cmd);

    // Top-level step so `zig build test-cli-parser` works standalone.
    {
        const cli_parser_step = b.step(
            "test-cli-parser",
            "Run CLI parser unit tests (cli.zig)",
        );
        cli_parser_step.dependOn(test_step);
    }

    // test-cli-main — integration tests that spawn the compiled tickoni binary.
    // Depends on exe_install so the binary is available at test time.
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
        run_cmd.addArtifactArg(cli_main_test);
        run_cmd.step.dependOn(&exe_install.step);

        // Top-level step so `zig build test-cli-main` works standalone.
        const cli_main_step = b.step(
            "test-cli-main",
            "Run CLI integration tests (main.zig)",
        );
        cli_main_step.dependOn(test_step);
        cli_main_step.dependOn(&exe_install.step);
    }
}
