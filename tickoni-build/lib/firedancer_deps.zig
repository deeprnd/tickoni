/// Firedancer dependency helpers for the Tickoni build system.
///
/// Contains: linkFiredancerDeps() — links the Firedancer substrate
/// libraries (.a archives) that Tickoni shim code depends on.
///
/// Paths come from config, not hardcoded in Zig code.

const std = @import("std");

/// Link the Firedancer substrate dependencies for a compile step.
/// `lib_dir` is the directory containing Firedancer .a archives.
/// `deps` are the library names to link (e.g. "fd_ballet", "fd_util").
pub fn linkFiredancerDeps(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    lib_dir: []const u8,
    deps: []const []const u8,
) void {
    step.root_module.addLibraryPath(b.path(lib_dir));
    for (deps) |dep| {
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.a", .{ lib_dir, dep }) });
    }
}
