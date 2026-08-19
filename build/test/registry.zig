/// Generic test registry for the Tickoni build system.
///
/// Handles all test lanes (unit, integration, system, cov) through a single
/// registry function that accepts a spec array and an action enum.

const std = @import("std");
const shims = @import("../lib/shims.zig");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const tile_run = @import("../lib/tile_run.zig");

/// Action to take for each test spec.
pub const Action = enum {
    check,
    run,
    cov,
};

/// Linkage requirements for a test binary.
pub const Linkage = struct {
    needs_libc: bool = false,
    needs_firedancer: bool = false,
    needs_codec: bool = false,
    needs_topo_run: bool = false,
    needs_tile_run: bool = false,
    fd_lib_dir: []const u8 = "",
};

/// A single test specification.
pub const TestSpec = struct {
    name: []const u8,
    source_file: []const u8,
    imports: []const std.Build.Module.Import,
    linkage: Linkage,
    action: Action,
};

/// Register a single test lane using the given spec.
pub fn registerTestLane(
    b: *std.Build,
    step: *std.Build.Step,
    spec: TestSpec,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    const test_bin = b.addTest(.{
        .name = spec.name,
        .root_source_file = b.path(spec.source_file),
        .target = target,
        .optimize = optimize,
        .imports = spec.imports,
    });

    // Apply linkage requirements
    test_bin.root_module.link_libc = spec.linkage.needs_libc;

    if (spec.action == .cov) {
        // Install to zig-out/cov/ for kcov
        const install = b.addInstallArtifact(test_bin, .{});
        install.dest_dir = .{ .override = .prefix, .custom = "cov" };
        step.dependOn(&install.step);
    } else if (spec.action == .run or spec.action == .cov) {
        // Run the test
        const run = b.addRunArtifact(test_bin);
        step.dependOn(&run.step);
    }
}

/// Register unit test lanes from a spec array.
pub fn registerUnitLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    modules: @import("../mod.zig").Modules,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = modules; // For now, specs include all needed imports
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register integration test lanes from a spec array.
pub fn registerIntegrationLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    modules: @import("../mod.zig").Modules,
    test_modules: @import("../mod.zig").TestModules,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = modules;
    _ = test_modules;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register system test lanes from a spec array.
pub fn registerSystemLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    modules: @import("../mod.zig").Modules,
    test_modules: @import("../mod.zig").TestModules,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = modules;
    _ = test_modules;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register coverage test lanes from a spec array.
pub fn registerCovLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    modules: @import("../mod.zig").Modules,
    test_modules: @import("../mod.zig").TestModules,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = modules;
    _ = test_modules;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}
