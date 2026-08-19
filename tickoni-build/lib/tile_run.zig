/// Tile run helpers for the Tickoni Firedancer tile process layer.
///
/// Contains: linkTickoniTileRun(), addTickoniTileRunShim().

const std = @import("std");
const shims = @import("shims.zig");

/// Links shim/tile_run.c (v2.14.S8.T4's fd_topo_run_tile_t wiring).
/// Deliberately separate from linkTickoniTopoRun: this file's static
/// TK_TILE_RUN struct references tk_tile_privileged_init/tk_tile_run,
/// Zig `export fn`s defined only in runtime/tile_process.zig, so only
/// call this for targets that also link tile_process.zig (the exe and
/// the process-mode integration tests) — never for topo_run.c/topob.c's
/// own standalone adapter unit tests, which don't include
/// tile_process.zig and would fail to link if this were folded into
/// linkTickoniTopoRun instead. Callers must also call
/// linkTickoniFiredancer and linkTickoniTopoRun.
pub fn linkTickoniTileRun(b: *std.Build, step: *std.Build.Step.Compile, lib_dir: []const u8) void {
    addTickoniTileRunShim(b, step);
    shims.linkTickoniSystemLibraries(b, step, lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

/// Compiles tile_run.c shim file.
pub fn addTickoniTileRunShim(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;
    step.root_module.addCSourceFiles(.{
        .files = &.{ "src/tickoni/c_abi/shim/tile_run.c" },
        .flags = shims.shimCFlagsFor(target_info),
    });
}
