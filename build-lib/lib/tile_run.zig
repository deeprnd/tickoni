const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries and add the tile_run shim C source.
///
/// Deliberately separate from linkTickoniTopoRun: tile_run.c's static TK_TILE_RUN
/// struct references tk_tile_privileged_init/tk_tile_run, Zig `export fn`s defined
/// only in runtime/tile_process.zig, so only call this for targets that also link
/// tile_process.zig (the exe and the process-mode integration tests) — never for
/// topo_run.c/topob.c's own standalone adapter unit tests, which don't include
/// tile_process.zig and would fail to link if this were folded into
/// linkTickoniTopoRun instead. Callers must also call
/// linkTickoniFiredancer and linkTickoniTopoRun.
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
        .files = &.{"src/tickoni/c_abi/shim/tile_run.c"},
        .flags = shims.shimCFlagsFor(target_info),
    });
}
