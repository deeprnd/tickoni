/// Topo run helpers for the Tickoni Firedancer adapter layer.
///
/// Contains: linkTickoniTopoRun(), addTickoniTopoRunShims().

const std = @import("std");
const shims = @import("shims.zig");

/// Links shim/topo_run.c (the fd_topo_run_tile adapter, v2.14.S8.T3) and
/// shim/topob.c (the fd_topob topology builder, v2.14.S8.T12) — the two
/// halves of Tickoni's Firedancer topology adapter, same link surface.
/// Callers must also call linkTickoniFiredancer (tango/util) — this only
/// adds the additional disco/ballet/waltz link surface these files and
/// their callees (fd_metrics, fd_event_report, both compiled into
/// fd_disco) need, following the same link set as
/// src/disco/topo/Local.mk's own test_topob unit test.
pub fn linkTickoniTopoRun(b: *std.Build, step: *std.Build.Step.Compile, lib_dir: []const u8) void {
    addTickoniTopoRunShims(b, step);
    shims.linkTickoniSystemLibraries(b, step, lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
}

/// Compiles topo_run.c, topob.c, and the platform-specific topo_run shim file.
pub fn addTickoniTopoRunShims(b: *std.Build, step: *std.Build.Step.Compile) void {
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
