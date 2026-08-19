/// Helper functions for test execution in the Tickoni build system.
///
/// Uses domain archives instead of inline C compilation. Each test binary
/// links the required domain archives (libtickoni_ballet.a,
/// libtickoni_flamenco.a, libtickoni_disco.a) which already contain
/// Tickoni shim C compiled once.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");

/// Adds a run step for the given test binary. Links domain archives
/// (libtickoni_ballet.a, libtickoni_flamenco.a, libtickoni_disco.a)
/// so that c_abi AND firedancer symbols are available without
/// duplicating C compilation into every test binary.
pub fn addPlainTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    fd_lib_dir: []const u8,
) *std.Build.Step.Run {
    linkDomainArchives(b, test_exe, fd_lib_dir);
    const run = b.addRunArtifact(test_exe);
    step.dependOn(&run.step);
    return run;
}

/// Runs the given test executable with optional environment variables.
pub fn runTestsCmd(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    env: ?std.Build.EnvMap,
    fd_lib_dir: []const u8,
) *std.Build.Step.Run {
    const run = addPlainTestRun(b, step, test_exe, fd_lib_dir);
    if (env) |e| run.step.addEnvMap(e);
    return run;
}

/// Link domain archives for a test binary. Links all 3 domain archives
/// (ballet, flamenco, disco) so tests can import any domain module
/// without needing inline C compilation. Zig's linker deduplicates
/// archives automatically.
pub fn linkDomainArchives(
    b: *std.Build,
    test_exe: *std.Build.Step.Compile,
    fd_lib_dir: []const u8,
) void {
    // Ballet domain: libtickoni_ballet.a (ballet.c + libfd_ballet.a + libfd_util.a)
    // Flamenco domain: libtickoni_flamenco.a (tango/util/wksp/sandbox/os.c + libfd_tango.a + libfd_util.a)
    // Disco domain: libtickoni_disco.a (topo_run/topob/tile_run.c + libfd_disco.a)

    // Link pre-built Firedancer archives for fd_* symbols
    test_exe.root_module.addLibraryPath(b.path(fd_lib_dir));
    test_exe.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_ballet.a", .{fd_lib_dir}),
    });
    test_exe.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}),
    });
    test_exe.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}),
    });
    test_exe.root_module.addObjectFile(.{
        .cwd_relative = b.fmt("{s}/libfd_disco.a", .{fd_lib_dir}),
    });

    if (test_exe.root_module.resolved_target.?.result.os.tag == .windows) {
        test_exe.root_module.addObjectFile(.{
            .cwd_relative = b.fmt("{s}/libuuid.a", .{fd_lib_dir}),
        });
        test_exe.root_module.link_libcpp = true;
    }
}
