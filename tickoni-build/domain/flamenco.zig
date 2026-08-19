/// Flamenco domain: compiles Tickoni shim C files into libtickoni_flamenco.a
/// and links against pre-built Firedancer libfd_tango.a and libfd_util.a.
///
/// Shim files: tango.c, util.c, wksp.c, sandbox.c, os.c
/// These provide tk_* wrappers around Firedancer's fd_* symbols.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const domain = @import("domain.zig");

/// Build the flamenco domain.
pub fn buildDomains(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) domain.FlamencoDomains {
    const shim_files = &.{
        "src/tickoni/c_abi/shim/tango.c",
        "src/tickoni/c_abi/shim/util.c",
        "src/tickoni/c_abi/shim/wksp.c",
        "src/tickoni/c_abi/shim/sandbox.c",
        "src/tickoni/c_abi/shim/os.c",
    };
    const fd_libs = &.{ "tango", "util" };

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
        .name = "libtickoni_flamenco",
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
