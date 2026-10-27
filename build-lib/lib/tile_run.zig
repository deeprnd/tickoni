const std = @import("std");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries. C shim compilation is handled by
/// addTickoniSupervisorShimLibrary (codec.zig) which owns all C source files.
pub fn linkTickoniTileRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}
