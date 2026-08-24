/// Generic test registry for the Tickoni build system.
///
/// Handles all test lanes (unit, integration, system, cov) through a single
/// registry function that accepts a spec array and an action enum.
///
/// Uses BuildRegistry for domain-based linking instead of deleted lib/ files.

const std = @import("std");
const Registry = @import("../registry/registry.zig");
const Mod = @import("../mod.zig");

/// Action to take for each test spec.
pub const Action = enum {
    check,
    run,
    cov,
};

/// A single test specification.
pub const TestSpec = struct {
    name: []const u8,
    source_file: []const u8,
    imports: []const std.Build.Module.Import,
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
    const root_mod = b.createModule(.{
        .root_source_file = b.path(spec.source_file),
        .target = target,
        .optimize = optimize,
        .imports = spec.imports,
    });
    const test_bin = b.addTest(.{
        .name = spec.name,
        .root_module = root_mod,
    });

    if (spec.action == .cov) {
        // Install to zig-out/cov/ for kcov
        const install = b.addInstallArtifact(test_bin, .{});
        install.dest_dir = .{ .custom = "cov" };
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
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register integration test lanes from a spec array.
pub fn registerIntegrationLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = Mod;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register system test lanes from a spec array.
pub fn registerSystemLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = Mod;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}

/// Register coverage test lanes from a spec array.
pub fn registerCovLanes(
    b: *std.Build,
    step: *std.Build.Step,
    specs: []const TestSpec,
    optimize: std.builtin.OptimizeMode,
    target: std.Build.ResolvedTarget,
) void {
    _ = Mod;
    for (specs) |spec| {
        registerTestLane(b, step, spec, optimize, target);
    }
}
