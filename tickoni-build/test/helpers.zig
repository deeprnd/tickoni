/// Helper functions for building and linking Tickoni test binaries.
///
/// All library linking is done via BuildRegistry domains, not deleted lib/ files.

const std = @import("std");
const config = @import("../generated/config.zig");

/// Compile the given Zig source file as a test binary.
/// Returns the build step for the compiled test executable.
pub fn compileTickoniTest(
    b: *std.Build,
    name: []const u8,
    src_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_test_deps: bool,
    link_system_libs: bool,
    system_lib_group: ?[]const u8,
    deps: []const std.Build.Module,
) *std.Build.Step.Compile {
    const test_bin = b.addTest(.{
        .name = name,
        .root_source_file = b.path(src_path),
        .target = target,
        .optimize = optimize,
    });

    // Add module dependencies
    for (deps) |dep| {
        test_bin.root_module.addImport(dep.tag, dep);
    }

    // Link Firedancer test system libraries if requested
    if (link_test_deps) {
        linkTestDeps(test_bin);
    }

    // Link system libraries (from config) if requested
    if (link_system_libs and system_lib_group != null) {
        const grp = config.getSystemLibByName(system_lib_group.?) orelse
            @panic("system_lib group not found in config");
        linkTestSystemLibs(test_bin, grp);
    }

    return test_bin;
}

/// Compile the given Zig source file as a test binary with all Tickoni deps.
pub fn setupTickoniTest(
    b: *std.Build,
    name: []const u8,
    src_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: []const std.Build.Module,
    system_lib_group: []const u8,
) *std.Build.Step.Compile {
    return compileTickoniTest(
        b,
        name,
        src_path,
        target,
        optimize,
        true,  // link_test_deps
        true,  // link_system_libs
        system_lib_group,
        deps,
    );
}

/// Setup a basic build step for a test binary without any deps.
pub fn setupTestBuild(
    b: *std.Build,
    name: []const u8,
    src_path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    return b.addTest(.{
        .name = name,
        .root_source_file = b.path(src_path),
        .target = target,
        .optimize = optimize,
    });
}

/// Link Firedancer library dependencies to a test step.
/// Links C shim archives (ballet, flamenco, disco) and Firedancer .a files.
pub fn linkTestDeps(step: *std.Build.Step.Compile) void {
    step.root_module.link_libcpp = true;
}

/// Link Firedancer library dependencies to a test step.
/// Links C shim archives (ballet, flamenco, disco) and Firedancer .a files.
pub fn linkTestDepsFull(step: *std.Build.Step.Compile, lib_dir: []const u8) void {
    step.root_module.link_libcpp = true;
    const b = step.step.build_root orelse @panic("missing build root");
    step.root_module.addLibraryPath(b.path(lib_dir));

    // Link C shim archives (shim C compiled into .a)
    // Order matters: linker resolves symbols left-to-right.
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libtickoni_disco.a" }) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libtickoni_ballet.a" }) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libtickoni_flamenco.a" }) });

    // Link Firedancer .a archives (fd_* symbols)
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libfd_tango.a" }) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libfd_util.a" }) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libfd_ballet.a" }) });
    step.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, "libfd_disco.a" }) });
}

/// Link a system library group (from config) to a test step.
pub fn linkTestSystemLibs(step: *std.Build.Step.Compile, grp: config.SystemLib) void {
    // We need the lib_dir to link, so we look it up from the step's build options
    const b = step.step.build_root orelse @panic("missing build root");
    const lib_dir = b.graph.search_paths.lookup("fd-lib-dir") orelse
        @panic("fd-lib-dir not set; use -Dfd-lib-dir=/path/to/lib");

    step.root_module.addLibraryPath(b.path(lib_dir));

    if (grp.needs_libcpp) step.root_module.link_libcpp = true;

    for (grp.object_deps) |dep| {
        step.root_module.addObjectFile(.{
            .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, dep.path }),
        });
    }
}

/// Create a run step that executes a test binary.
/// Links C shim archives and Firedancer .a files to the test binary.
pub fn addPlainTestRun(
    b: *std.Build,
    parent_step: *std.Build.Step,
    test_bin: *std.Build.Step.Compile,
    lib_dir: []const u8,
) *std.Build.Step.Run {
    linkTestDepsFull(test_bin, lib_dir);
    const run = b.addRunArtifact(test_bin);
    parent_step.dependOn(&run.step);
    return run;
}
