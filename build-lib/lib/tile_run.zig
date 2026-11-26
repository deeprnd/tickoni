const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries and add the tile_run shim C source.
///
/// Callers must also call linkTickoniFiredancer and linkTickoniTopoRun.
pub fn linkTickoniTileRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniTileRunShim(b, step);
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

/// Add tile_run shim C source to the given compile step.
fn addTickoniTileRunShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/tile_run.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}
