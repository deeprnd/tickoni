/// Ballet domain: compiles Tickoni shim ballet.c into libtickoni_ballet.a
/// and links against pre-built Firedancer libfd_ballet.a and libfd_util.a.
///
/// This is Tickoni shim code, NOT Firedancer C. Firedancer C is built by
/// Firedancer's CMake/make into .a archives.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const domain = @import("domain.zig");

/// Build the ballet domain.
pub fn buildDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) domain.BalletDomains {
    // Determine which files to compile based on target OS
    const shim_files = getShimFiles(b, target.result);
    const fd_libs = getFdLibs();

    // Create the module with Tickoni shim C
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

    // Create the static archive
    const archive = b.addLibrary(.{
        .name = "libtickoni_ballet",
        .root_module = mod,
    });

    // Link pre-built Firedancer archives for fd_* symbols
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

/// Get the shim C files for the ballet domain.
fn getShimFiles(b: *std.Build, target: std.Target) []const []const u8 {
    // ballet.c always included
    var files = b.allocator.alloc([]const u8, 2) catch @panic("OOM");
    files[0] = "src/tickoni/c_abi/shim/ballet.c";
    // libuuid_stub.c is only needed on Windows
    if (target.os.tag == .windows) {
        files[1] = "src/tickoni/c_abi/shim/libuuid_stub.c";
    } else {
        // For non-Windows, use a placeholder — we'll just use the 2-element
        // array but only compile ballet.c (libuuid_stub.c is Windows-only)
        files[1] = "";
    }
    return files;
}

/// Get the Firedancer libraries to link for the ballet domain.
fn getFdLibs() []const []const u8 {
    return &.{ "ballet", "util" };
}
