/// ZigModuleStrategy: creates a Zig module from a root source file.
///
/// Reads from config: root_source, (optional) import_modules.
/// No hardcoded paths — everything comes from the JSON config.
const std = @import("std");
const base = @import("base.zig");

/// Config entry for a Zig module domain.
pub const Config = struct {
    root_source: []const u8,
    /// Optional list of dependency domain names.
    /// The caller is responsible for resolving these to module imports
    /// and passing them via import_modules.
    dependencies: ?[]const []const u8 = null,
    /// Pre-resolved module imports (populated by the caller).
    /// Each entry maps a dependency name to its resolved Zig module.
    import_modules: []const *std.Build.Module = &.{},
};

/// Build a Zig module domain.
/// The caller (registry) resolves dependency names to modules and passes
/// them via import_modules.
pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: Config,
) base.DomainResult {
    var imports: [32]std.Build.Module.Import = undefined;
    var count: usize = 0;

    for (config.import_modules) |mod| {
        if (count < imports.len) {
            imports[count] = .{
                .name = std.mem.sliceTo(mod.name, 0),
                .module = mod,
            };
            count += 1;
        }
    }

    const mod = b.createModule(.{
        .root_source_file = b.path(config.root_source),
        .target = target,
        .optimize = optimize,
        .imports = if (count > 0) imports[0..count] else &.{},
    });

    return .{
        .archive = null,
        .module = mod,
    };
}
