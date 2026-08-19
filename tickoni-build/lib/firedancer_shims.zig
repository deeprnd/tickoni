/// Firedancer shim helpers for the Tickoni build system.
///
/// Contains: addTickoniShimLibrary(), addTickoniSupervisorShimLibrary(),
/// addTickoniFiredancerShims(), linkTickoniFiredancer().
///
/// These compile Tickoni shim C code that wraps Firedancer subsystems.
/// C source paths come from build_config.json domains.
/// Archive linking uses firedancer_deps or config-driven paths.

const std = @import("std");
const shims = @import("shims.zig");

/// Create a static library archive from C shim source files.
pub fn addTickoniShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    files: []const []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = files,
        .flags = shims.shimCFlagsFor(target.result),
    });
    if (target.result.os.tag == .windows) {
        mod.addCSourceFiles(.{
            .files = &.{"src/tickoni/c_abi/shim/windows_crt.c"},
            .flags = shims.shimCFlagsFor(target.result),
        });
    }
    return b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });
}

/// Create the supervisor shim library (used on Windows only).
pub fn addTickoniSupervisorShimLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return addTickoniShimLibrary(b, target, optimize, "tickoni-supervisor-shims", &.{
        "src/tickoni/c_abi/shim/ballet.c",
        "src/tickoni/c_abi/shim/tango.c",
        "src/tickoni/c_abi/shim/util.c",
        "src/tickoni/c_abi/shim/wksp.c",
        "src/tickoni/c_abi/shim/sandbox.c",
        "src/tickoni/c_abi/shim/os.c",
        "src/tickoni/c_abi/shim/topo_run.c",
        "src/tickoni/c_abi/shim/topo_run_platform_windows.c",
        "src/tickoni/c_abi/shim/topob.c",
        "src/tickoni/c_abi/shim/tile_run.c",
    });
}

/// Compiles the Firedancer substrate shim files (tango, util, wksp, sandbox, os)
/// and links them into the compile step.
pub fn addTickoniFiredancerShims(b: *std.Build, step: *std.Build.Step.Compile) void {
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

/// Links the Firedancer substrate used by Tickoni runtime wrappers.
pub fn linkTickoniFiredancer(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    lib_dir: []const u8,
) void {
    addTickoniFiredancerShims(b, step);
    if (step.root_module.resolved_target.?.result.os.tag == .windows) {
        step.root_module.addLibraryPath(b.path(lib_dir));
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_tango.a", .{lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_util.a", .{lib_dir}) });
        step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libuuid.a", .{lib_dir}) });
        step.root_module.link_libcpp = true;
        return;
    }
    shims.linkTickoniSystemLibraries(b, step, lib_dir, &.{ "fd_tango", "fd_util" });
}
