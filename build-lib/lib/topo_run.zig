const std = @import("std");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries. C shim compilation is handled by
/// addTickoniSupervisorShimLibrary (codec.zig) which owns all C source files.
pub fn linkTickoniTopoRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
    // libfd_waltz.a contains HTTP objects that reference ZSTD.  The FD build
    // provides the implementation as libfd_zstd.a; link that concrete archive
    // instead of asking Windows Zig to probe for a system zstd/pkg-config.
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_zstd.a", .{fd_lib_dir}) });
}
