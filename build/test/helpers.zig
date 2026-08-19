/// Helper functions for test execution in the Tickoni build system.
///
/// Contains: runTestsCmd(), addPlainTestRun(), linkCodec().

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");

/// Adds a run step for the given test binary. Applies codec linkage (ballet.c
/// + libfd_ballet.a / libfd_util.a) to every test so that c_abi symbols are
/// available. The fd_lib_dir is required on non-Windows for Firedancer libs.
pub fn addPlainTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    fd_lib_dir: []const u8,
) *std.Build.Step.Run {
    linkCodec(b, test_exe, fd_lib_dir);
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

/// Apply codec shim linkage to a test binary (compiles ballet.c and links
/// libfd_ballet.a / libfd_util.a). Call this for any test that imports c_abi
/// or any schema/consumer_money source.
pub fn linkCodec(b: *std.Build, test_exe: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    codec.linkTickoniCodec(b, test_exe, fd_lib_dir);
}

/// Apply firedancer substrate linkage to a test binary (compiles tango/util/wksp/sandbox/os
/// shims and links libfd_tango.a / libfd_util.a). Call this for c_abi/queue, c_abi/dcache, etc.
pub fn linkFiredancer(b: *std.Build, test_exe: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    firedancer.linkTickoniFiredancer(b, test_exe, fd_lib_dir);
}
