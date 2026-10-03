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
/// FD_UNALIGNED_ACCESS_STYLE=0 forces FD_STORE/FD_LOAD to use memcpy
/// instead of direct pointer casts.  This is required because Firedancer's
/// pod/wksp/topo code writes to uchar* buffers with FD_POD_ALIGN(1),
/// producing addresses that may not be aligned to uint/ulong boundaries.
/// x86 hardware handles it fine, but Zig's debug runtime flags the
/// misaligned stores as crashes.
pub fn shimCFlagsFor(target: std.Target) []const []const u8 {
    const unaligned_style = "-DFD_UNALIGNED_ACCESS_STYLE=0";
    return switch (target.os.tag) {
        .linux => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_LINUX=1",
            "-DFD_HAS_OPENSSL=1", unaligned_style,
        },
        .macos => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_MACOS=1",
            "-DFD_HAS_OPENSSL=1", unaligned_style,
        },
        .windows => switch (target.cpu.arch) {
            .aarch64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_ARM64=1", "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1", "-Wno-format",
                "-Wno-format-extra-args", unaligned_style,
            },
            .x86_64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_X86=1", "-DFD_HAS_SSE=1", "-DFD_HAS_AVX=1", "-DFD_HAS_AVX2=1", "-DFD_HAS_AESNI=1",
                "-DFD_IS_X86_64=1", "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1", "-Wno-format",
                "-Wno-format-extra-args", unaligned_style,
            },
            else => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1", "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-Wno-format", "-Wno-format-extra-args", unaligned_style,
            },
        },
        else => &.{ "-std=c17", "-U__BMI2__", "-U__LZCNT__", "-DFD_HAS_HOSTED=1", unaligned_style },
    };
}

/// Wrap a test compile step with a sequential run using
/// `contrib/test/run_test_series.sh`.  This avoids Zig's --listen=-
/// parallel coordination which panics with EndOfStream when 48+ test
/// binaries communicate over the same pipe, and correctly propagates
/// non-zero exit codes when test binaries crash (the coordinator in
/// --listen=- mode exits 0 even when children SIGABRT).
pub fn addPlainTestRun(
    b: *std.Build,
    test_compile: *std.Build.Step.Compile,
) *std.Build.Step.Run {
    return addPlainTestRunSeries(b, &.{test_compile});
}

/// Run multiple compiled test binaries sequentially in one runner process.
pub fn addPlainTestRunSeries(
    b: *std.Build,
    test_compiles: []const *std.Build.Step.Compile,
) *std.Build.Step.Run {
    // CWD = repo root so tile_exe_path "build/zig-out/bin/tickoni-supervisor"
    // resolves to the installed supervisor binary (wired as dependency in
    // build_test_lanes.zig).
    const run_step = b.addSystemCommand(&.{
        "bash",
        "contrib/test/run_test_series.sh",
    });
    run_step.setCwd(b.path("."));
    for (test_compiles) |test_compile| run_step.addArtifactArg(test_compile);
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
