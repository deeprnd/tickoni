const std = @import("std");

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
