/// Firedancer shim helpers for the Tickoni build system.
///
/// Contains: addTickoniShimLibrary(), addTickoniSupervisorShimLibrary(),
/// addTickoniFiredancerShims(), linkTickoniFiredancer(),
/// addWindowsFdManifestFixups().
/// Archive names come from config.zig, not hardcoded in Zig code.

const std = @import("std");
const shims = @import("shims.zig");
const config = @import("../generated/config.zig");

// Re-export manifest fixups from shims.zig
pub const addWindowsFdManifestFixups = shims.addWindowsFdManifestFixups;

/// Compile shim/tango.c + shim/wksp.c + shim/os.c + shim/sandbox.c
/// into a static archive (Windows-only; Linux links these via linkTickoniFiredancer).
pub fn addTickoniShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
        },
        .flags = shims.shimCFlagsFor(target.result),
    });
    return b.addLibrary(.{
        .name = "tickoni_shim",
        .linkage = .static,
        .root_module = mod,
    });
}

/// Compile shim/tango.c + shim/wksp.c + shim/os.c + shim/sandbox.c +
/// shim/util.c + shim/topo_run.c + shim/topob.c + shim/tile_run.c into a
/// static archive (Windows-only; Linux links these via linkTickoniFiredancer).
pub fn addTickoniSupervisorShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
            "src/tickoni/c_abi/shim/util.c",
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
        },
        .flags = shims.shimCFlagsFor(target.result),
    });
    return b.addLibrary(.{
        .name = "tickoni_supervisor_shim",
        .linkage = .static,
        .root_module = mod,
    });
}

/// Add all Firedancer shim C files for a compile step (Linux path).
pub fn addTickoniFiredancerShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;

    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
            "src/tickoni/c_abi/shim/util.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}

/// Link Firedancer substrate libraries against a compile step.
///
/// On Linux: shim files are added separately via addTickoniFiredancerShims()
/// (called by build.zig) to avoid double-compilation. This function
/// only links FD archive objects.
/// On Windows: shim library is linked via addTickoniSupervisorShimLibrary().
pub fn linkTickoniFiredancer(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    lib_dir: []const u8,
) void {
    step.root_module.addLibraryPath(b.path(lib_dir));

    // Archive names come from config (fd_tango system_lib group)
    const fd_tango_lib = config.getSystemLibByName("fd_tango") orelse @panic("fd_tango system_lib not found in config");
    for (fd_tango_lib.object_deps) |dep| {
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, dep.path }) });
    }

    // On Windows, link ballet/util explicitly (the shim library doesn't include them).
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        const codec_lib = config.getSystemLibByName("codec") orelse @panic("codec system_lib not found in config");
        for (codec_lib.object_deps) |dep| {
            step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, dep.path }) });
        }
        step.root_module.link_libcpp = true;
    }
}
