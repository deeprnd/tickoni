/// Ballet domain: compiles Tickoni shim ballet.c into libtickoni_ballet.a
/// and links against pre-built Firedancer libfd_ballet.a and libfd_util.a.
///
/// This is Tickoni shim code, NOT Firedancer C. Firedancer C is built by
/// Firedancer's CMake/make into .a archives.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const domain = @import("domain.zig");

/// Build the ballet domain.
pub fn buildDomain(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_dir: []const u8,
) FiredancerShimDomain {
    // Determine which files to compile based on target OS
    const shim_files = getShimFiles(target.result);

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
    archive.root_module.addLibraryPath(b.path(lib_dir));
    archive.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{lib_dir}),
    });
    archive.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_util.a", .{lib_dir}),
    });

    return .{
        .archive = archive,
        .module = mod,
    };
}

/// Get the shim C files for the ballet domain.
fn getShimFiles(target: std.Target) []const []const u8 {
    // ballet.c always included
    if (target.os.tag == .windows) {
        return &.{
            "src/tickoni/c_abi/shim/ballet.c",
            "src/tickoni/c_abi/shim/libuuid_stub.c",
        };
    } else {
        return &.{"src/tickoni/c_abi/shim/ballet.c"};
    }
}
