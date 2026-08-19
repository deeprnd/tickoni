/// Entry point for @import("build/mod.zig").
/// Exports modules and test_modules for build.zig.

pub const modules = @import("mod/modules.zig");
pub const test_modules = @import("mod/test_modules.zig");
pub const Modules = modules.Modules;
pub const TestModules = test_modules.TestModules;
