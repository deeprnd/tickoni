const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");

/// Link Firedancer disco/ballet/waltz libraries and add the topo_run shim C sources.
pub fn linkTickoniTopoRun(b: *std.Build, step: *std.Build.Step.Compile, fd_lib_dir: []const u8) void {
    addTickoniTopoRunShims(b, step);
    codec.addTickoniSystemLibraries(b, step, fd_lib_dir, &.{ "fd_disco", "fd_ballet", "fd_waltz" });
    // libfd_waltz.a contains HTTP objects that reference ZSTD.  The FD build
    // provides the implementation as libfd_zstd.a; link that concrete archive
    // instead of asking Windows Zig to probe for a system zstd/pkg-config.
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_zstd.a", .{fd_lib_dir}) });
}

/// Add topo_run shim C sources (topo_run.c, platform-specific file, topob.c,
/// tk_metric_tile.c) plus the Firedancer metric tile implementation
/// (fd_metric_tile.c, fd_prometheus.c) that tk_metric_tile.c now references
/// through proper header declarations instead of fragile .c inclusion.
fn addTickoniTopoRunShims(b: *std.Build, step: *std.Build.Step.Compile) void {
    step.root_module.link_libc = true;
    step.root_module.addIncludePath(b.path("src"));
    const target_info = step.root_module.resolved_target.?.result;

    const topo_run_platform_file = switch (target_info.os.tag) {
        .macos => "src/tickoni/c_abi/shim/topo_run_platform_macos.c",
        .windows => "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        else => "src/tickoni/c_abi/shim/topo_run_platform_linux.c",
    };

    // tk_audit_stem.c is NOT in topo_run — it belongs in the supervisor
    // shim library (codec.zig) so it can share other shims.  tk_audit_stem.c
    // is compiled in its own static library (see codec.zig) because it
    // includes fd_stem.c with STEM_CALLBACK_CONTEXT_TYPE = tk_audit_ctx_t,
    // which would collide with tk_metric_tile.c's stem_run (fd_metric_ctx_t).
    step.root_module.addCSourceFiles(.{
        .files = &.{
            "src/tickoni/c_abi/shim/topo_run.c",
            topo_run_platform_file,
            "src/tickoni/c_abi/shim/topob.c",
            "src/tickoni/c_abi/shim/tk_metric_tile.c",
        },
        .flags = shims.shimCFlagsFor(target_info),
    });
}
