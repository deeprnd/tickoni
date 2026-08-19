/// C shim compilation helpers for the Firedancer/Tickoni shim layer.
///
/// Contains: shimCFlagsFor(), shim_c_files array, arch/os/abi/triple helpers.

const std = @import("std");

/// C source files that are compile-checked by the check-c-compile step.
pub const shim_c_files: []const []const u8 = &.{
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

/// Returns platform-specific C compiler flags for shim files.
pub fn shimCFlagsFor(target: std.Target) []const []const u8 {
    return switch (target.os.tag) {
        .linux => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_LINUX=1",
        },
        .macos => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1", "-DFD_HAS_MACOS=1",
        },
        .windows => switch (target.cpu.arch) {
            .aarch64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1",
                "-DFD_HAS_ATOMIC=1", "-DFD_HAS_ARM64=1",
                "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1",
                "-DFD_HAS_ALLOCA=1", "-Wno-format",
                "-Wno-format-extra-args",
            },
            .x86_64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1",
                "-DFD_HAS_ATOMIC=1", "-DFD_HAS_X86=1",
                "-DFD_HAS_SSE=1", "-DFD_HAS_AVX=1",
                "-DFD_HAS_AVX2=1", "-DFD_HAS_AESNI=1",
                "-DFD_IS_X86_64=1", "-DFD_HAS_INT128=0",
                "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1",
                "-Wno-format", "-Wno-format-extra-args",
            },
            else => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1",
                "-DFD_HAS_ATOMIC=1",
                "-Wno-format", "-Wno-format-extra-args",
            },
        },
        else => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1",
        },
    };
}
