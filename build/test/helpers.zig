/// Helper functions for test execution in the Tickoni build system.
///
/// Contains: runTestsCmd(), addPlainTestRun().

const std = @import("std");

/// Adds a run step for the given test binary.
pub fn addPlainTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
) *std.Build.Step.Run {
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
) *std.Build.Step.Run {
    const run = addPlainTestRun(b, step, test_exe);
    if (env) |e| run.step.addEnvMap(e);
    return run;
}
