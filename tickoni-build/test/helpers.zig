/// Helper functions for building and linking Tickoni test binaries.
///
/// Contains: compileTickoniTest(), linkTestDeps(), addPlainTestRun().
/// Archive names come from config.zig, not hardcoded in Zig code.

const std = @import("std");
const config = @import("../generated/config.zig");
const shims = @import("../lib/shims.zig");

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
        linkTestDeps(test_bin, b, optimize);
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
pub fn linkTestDeps(step: *std.Build.Step.Compile, b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const target = step.root_module.resolved_target orelse
        @panic("test step must have a resolved target");

    // Create a shared module for ballet.c
    const codec_mod = @import("../lib/codec.zig").createTickoniCodecModule(b, target, optimize);
    step.root_module.addImport("codec", codec_mod);
    step.root_module.link_libcpp = true;
}

/// Link a system library group (from config) to a test step.
pub fn linkTestSystemLibs(step: *std.Build.Step.Compile, grp: config.SystemLib) void {
    // We need the lib_dir to link, so we look it up from the step's build options
    // For now, use the config-provided archive names directly
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
/// Returns the run step for dependency chaining.
pub fn addPlainTestRun(
    b: *std.Build,
    parent_step: *std.Build.Step,
    test_bin: *std.Build.Step.Compile,
    _lib_dir: []const u8,
) *std.Build.Step.Run {
    _ = _lib_dir;
    const run = b.addRunArtifact(test_bin);
    parent_step.dependOn(&run.step);
    return run;
}
