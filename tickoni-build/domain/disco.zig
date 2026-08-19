/// Disco domain: compiles Tickoni shim C files into libtickoni_disco.a
/// and links against pre-built Firedancer libfd_disco.a.
///
/// Shim files: topo_run.c, topo_run_platform_*.c, topob.c, tile_run.c
/// These provide tk_* wrappers for Firedancer's topology/run subsystem.
/// Platform-specific files are selected based on target OS.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const domain = @import("domain.zig");

/// Build the disco domain.
pub fn buildDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) domain.DiscoDomains {
    const shim_files = getShimFiles(target.result);
    const fd_libs = &.{ "disco" };

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = shim_files,
        .flags = shims.shimCFlagsFor(target.result),
    });

    const archive = b.addLibrary(.{
        .name = "libtickoni_disco",
        .root_module = mod,
    });

    archive.root_module.addLibraryPath(b.path(fd_lib_dir));
    for (fd_libs) |lib| {
        archive.root_module.addObjectFile(.{
            .cwd_relative = b.fmt("{s}/libfd_{s}.a", .{ fd_lib_dir, lib }),
        });
    }

    return .{
        .archive = archive,
        .module = mod,
    };
}

/// Get the shim C files for the disco domain, selecting platform-specific files.
fn getShimFiles(target: std.Target) []const []const u8 {
    return switch (target.os.tag) {
        .linux => &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topo_run_platform_linux.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
        },
        .macos => &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topo_run_platform_macos.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
        },
        .windows => &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
            "src/tickoni/c_abi/shim/windows_crt.c",
        },
        else => &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tile_run.c",
        },
    };
}
