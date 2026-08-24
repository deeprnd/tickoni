/// Main module declarations entry point for the Tickoni build system.
///
/// Re-exports from build/mod/modules.zig and build/mod/test_modules.zig.

const std = @import("std");

pub const modules = @import("mod/modules.zig");
pub const test_modules = @import("mod/test_modules.zig");

/// Public re-export of Modules struct for registry and specs.
pub const Modules = modules.Modules;
pub const TestModules = test_modules.TestModules;

/// Create all modules and test modules in one call.
pub fn allModules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, lib_dir: []const u8) struct {
    modules: Modules,
    test_modules: test_modules.TestModules,
    lib_dir: []const u8,
} {
    const m = modules.modules(b, target, optimize);
    return .{
        .modules = m,
        .test_modules = test_modules.create(b, target, optimize, m),
        .lib_dir = lib_dir,
    };
}
