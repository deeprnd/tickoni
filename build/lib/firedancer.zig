/// Firedancer linkage helpers for the Tickoni runtime.
///
/// Contains: linkTickoniFiredancer(), addTickoniFiredancerShims().

const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Links the Firedancer substrate used by Tickoni runtime wrappers. Tickoni
/// code crosses Firedancer only through src/tickoni/c_abi/shim/**, so this
/// compiles the required Tickoni-owned shim files alongside upstream libs.
pub fn linkTickoniFiredancer(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniFiredancerShims(b, step);
    codec.linkTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_tango", "fd_util" });
}

pub fn addTickoniFiredancerShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tango.c",
            "src/tickoni/c_abi/shim/util.c",
            "src/tickoni/c_abi/shim/wksp.c",
            "src/tickoni/c_abi/shim/sandbox.c",
            "src/tickoni/c_abi/shim/os.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}
