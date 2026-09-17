/// Common lane helpers used across unit, integration, system, and cov lanes.

const std = @import("std");

/// Create the run-tests command that executes all test binaries
/// sequentially via a bash script (avoids Zig's --listen=- parallel
/// coordination which panics with EndOfStream when 48+ test binaries
/// communicate over the same pipe).
pub fn createRunTestsCmd(b: *std.Build) *std.Build.Step.Run {
    const run_tests_cmd = std.Build.Step.Run.create(b, "run-tests");
    const build_root_str = b.root.toString(b.allocator) catch unreachable;
    defer b.allocator.free(build_root_str);
    var script_buf: [4096]u8 = undefined;
    const full_script_path = std.fmt.bufPrint(
        &script_buf,
        "{s}/contrib/test/run_test_series.sh",
        .{build_root_str},
    ) catch unreachable;
    run_tests_cmd.addArgs(&[_][]const u8{
        "bash",
        full_script_path,
    });
    run_tests_cmd.setCwd(b.path("."));
    return run_tests_cmd;
}
