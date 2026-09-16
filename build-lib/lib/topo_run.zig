const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries and add the topo_run shim C sources.
pub fn linkTickoniTopoRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniTopoRunShims(b, step);
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

/// Add topo_run shim C sources (topo_run.c, platform-specific file, topob.c) to the given compile step.
fn addTickoniTopoRunShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;

    const topo_run_platform_file = switch (target_info.os.tag) {
        .macos => "src/tickoni/c_abi/shim/topo_run_platform_macos.c",
        .windows => "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        else => "src/tickoni/c_abi/shim/topo_run_platform_linux.c",
    };

    step.root_module.addCSourceFiles(.{
        .files = &.{ "src/tickoni/c_abi/shim/topo_run.c", topo_run_platform_file, "src/tickoni/c_abi/shim/topob.c" },
        .flags = shims.shimCFlagsFor(target_info),
    });
}
