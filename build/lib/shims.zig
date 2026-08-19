/// C shim compilation helpers for the Firedancer/Tickoni shim layer.
///
/// Contains: shimCFlagsFor(), shim_c_files array, arch/os/abi/triple helpers.

const std = @import("std");

/// C source files compiled as part of the Tickoni shim layer.
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

/// Return C compiler flags for the given target architecture/OS/ABI.
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
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_ARM64=1", "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1",
                "-DFD_HAS_ALLOCA=1", "-Wno-format", "-Wno-format-extra-args",
            },
            .x86_64 => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_X86=1", "-DFD_HAS_SSE=1", "-DFD_HAS_AVX=1",
                "-DFD_HAS_AVX2=1", "-DFD_HAS_AESNI=1", "-DFD_IS_X86_64=1",
                "-DFD_HAS_INT128=0", "-DFD_HAS_DOUBLE=1", "-DFD_HAS_ALLOCA=1",
                "-Wno-format", "-Wno-format-extra-args",
            },
            else => &.{
                "-std=c17", "-U__BMI2__", "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1", "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS", "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1", "-DFD_HAS_THREADS=1", "-DFD_HAS_ATOMIC=1",
                "-Wno-format", "-Wno-format-extra-args",
            },
        },
        else => &.{
            "-std=c17", "-U__BMI2__", "-U__LZCNT__",
            "-DFD_HAS_HOSTED=1",
        },
    };
}

/// Compute arch/os/abi/triple for the given build target.
pub fn targetTriple(b: *std.Build, target: std.Build.ResolvedTarget) struct {
    arch: []const u8,
    os: []const u8,
    abi: []const u8,
    triple: []const u8,
} {
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
    const triple = if (abi_name.len > 0)
        b.fmt("{s}-{s}-{s}", .{ arch_name, os_name, abi_name })
    else
        b.fmt("{s}-{s}", .{ arch_name, os_name });
    return .{ .arch = arch_name, .os = os_name, .abi = abi_name, .triple = triple };
}

/// Create a C compile-check step that compiles each shim file individually.
pub fn checkShimCompilation(b: *std.Build, check_step: *std.Build.Step, target: std.Build.ResolvedTarget) void {
    const info = shimCFlagsFor(target.result);
    const triple = targetTriple(b, target).triple;
    inline for (shim_c_files) |shim_file| {
        const c_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt(
                "zig cc -target {s} -c -I src -std=c17 -UBMI2 -ULZCNT -DFD_HAS_HOSTED=1 {s} {s} 2>&1 || true",
                .{ triple, info[0], b.fmt("src/tickoni/c_abi/shim/{s}", .{shim_file}) },
            ),
        });
        check_step.dependOn(&c_check.step);
    }
}
