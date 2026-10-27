const std = @import("std");
const codec = @import("codec.zig");

/// Link Firedancer tango/util libraries. C shim compilation is handled by
/// addTickoniSupervisorShimLibrary (codec.zig) which owns all C source files.
pub fn linkTickoniFiredancer(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(codec.buildPath(b, fd_lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{fd_lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{fd_lib_dir}) });
        codec.linkTickoniWindowsUuid(b, step, fd_lib_dir);
        step.root_module.link_libcpp = true;
        return;
    }
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_tango", "fd_util" });
}
