const std = @import("std");

/// The ballet.c shim source path used across codec.zig and shims.zig.
pub const ballet_c = "src/tickoni/c_abi/shim/ballet.c";

/// C shim source files for the Tickoni shim library.
pub const shim_c_files = &.{
    "tango.c",
    "util.c",
    "wksp.c",
    "sandbox.c",
    "os.c",
    "topo_run.c",
    "topob.c",
    "tile_run.c",
    "ballet.c",
};

/// Build the Zig target triple string for the given build target.
pub fn buildTriple(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const arch_name = switch (target.result.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .x86 => "x86",
        .arm => "arm",
        else => b.fmt("{s}", .{@tagName(target.result.cpu.arch)}),
    };
    const os_name = switch (target.result.os.tag) {
        .linux => "linux",
        .windows => "windows",
        .macos => "macos",
        else => b.fmt("{s}", .{@tagName(target.result.os.tag)}),
    };
    const abi_name = switch (target.result.abi) {
        .gnu => "gnu",
        .gnuabi64 => "gnu",
        .musl => "musl",
        .msvc => "msvc",
        else => "",
    };
    return if (abi_name.len > 0)
        b.fmt("{s}-{s}-{s}", .{ arch_name, os_name, abi_name })
    else
        b.fmt("{s}-{s}", .{ arch_name, os_name });
}

/// C compiler flags for shim compilation, varying by target OS/arch.
pub fn shimCFlagsFor(target: std.Target) []const []const u8 {
    return switch (target.os.tag) {
        .linux => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_LINUX=1",
            "-DFD_HAS_OPENSSL=1",
        },
        .macos => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_MACOS=1",
            "-DFD_HAS_OPENSSL=1",
        },
        .windows => switch (target.cpu.arch) {
            .aarch64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_ARM64=1", "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1", "-Wno-format",
                "-Wno-format-extra-args",
            },
            .x86_64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_X86=1", "-DFD_HAS_SSE=1", "-DFD_HAS_AVX=1", "-DFD_HAS_AVX2=1", "-DFD_HAS_AESNI=1",
                "-DFD_IS_X86_64=1", "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1", "-Wno-format",
                "-Wno-format-extra-args",
            },
            else => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-Wno-format", "-Wno-format-extra-args",
            },
        },
        else => &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1" },
    };
}

/// Wrap a test compile step with a sequential run command using
/// `contrib/test/run_test_series.sh`.  This avoids Zig's --listen=-
/// parallel coordination which panics with EndOfStream when 48+ test
/// binaries communicate over the same pipe.
pub fn addPlainTestRun(
    b: *std.Build,
    test_compile: *std.Build.Step.Compile,
) *std.Build.Step.Run {
    const run_step = std.Build.Step.Run.create(b, b.fmt("run {s} (plain)", .{test_compile.name}));
    run_step.producer = test_compile;
    run_step.addArtifactArg(test_compile);
    run_step.has_side_effects = true;
    // CWD = repo root so tile_exe_path "build/zig-out/bin/tickoni-supervisor"
    // resolves to the installed supervisor binary (wired as dependency in
    // build_test_lanes.zig).
    run_step.setCwd(b.path("."));
    return run_step;
}

/// Install a test binary under `zig-out/cov/` for kcov coverage.
pub fn addCovInstall(
    b: *std.Build,
    test_compile: *std.Build.Step.Compile,
) *std.Build.Step.InstallDir {
    const cov_install = b.addInstallDirectory(.{
        .source_dir = test_compile.getEmittedBin(),
        .install_dir = .prefix,
        .install_subdir = "cov",
    });
    return cov_install;
}
