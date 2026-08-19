/// Test specifications for the Tickoni build system.
///
/// Consolidates all 4 spec files (unit, integration, coverage, system)
/// into a single source of truth. Each test registers via `b.addTest()`
/// and imports from domain modules provided by the builder.
///
/// NO INLINE C COMPILATION: C shims are compiled once into domain archives
/// by the domain builder. Tests only import Zig modules; the C symbols
/// come transitively through the domain module's C source files.

const std = @import("std");
const builder = @import("builder.zig");

/// Helper: add a test with its module and run it.
/// `test_fn` is called to create the module; it receives all domain modules.
fn addTestWithModule(
    b: *std.Build,
    step: *std.Build.Step,
    name: []const u8,
    root_source: []const u8,
    common: builder.CommonDomains,
    firedancer: struct {
        ballet: *std.Build.Module,
        flamenco: *std.Build.Module,
        disco: *std.Build.Module,
    },
    extra_imports: []const std.Build.Module.Import,
    lib_dir: []const u8,
) void {
    // Build a combined import list
    var all_imports = b.allocator.alloc(std.Build.Module.Import, extra_imports.len + 3) catch @panic("OOM");
    @memcpy(all_imports[0..extra_imports.len], extra_imports);
    all_imports[extra_imports.len] = .{ .name = "ballet", .module = firedancer.ballet };
    all_imports[extra_imports.len + 1] = .{ .name = "flamenco", .module = firedancer.flamenco };
    all_imports[extra_imports.len + 2] = .{ .name = "disco", .module = firedancer.disco };
    defer b.allocator.free(all_imports);

    const test_mod = b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .imports = all_imports,
    });
    const test = b.addTest(.{ .root_module = test_mod });
    test.step.dependOn(b.getInstallStep());
    if (b.single_threaded) test.step.addOption(bool, "single_threaded", true);
    const run_step = b.step(name, name);
    run_step.dependOn(&test.step);
}
