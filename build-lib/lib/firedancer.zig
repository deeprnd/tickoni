const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Link Firedancer tango/util libraries and add the Firedancer shim C sources.
pub fn linkTickoniFiredancer(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniFiredancerShims(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, step, fd_lib_dir);
        step.root_module.link_libcpp = true;
        return;
    }
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_tango", "fd_util" });
}

/// Add Firedancer shim C sources (tango, util, wksp, sandbox, os) to the given compile step.
fn addTickoniFiredancerShims(b: *std.Build, step: *std.Build.Step.Compile) void {
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
