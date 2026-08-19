/// ZigModuleStrategy: creates a Zig module from a root source file.
///
/// Reads from config: root_source, (optional) imports.
/// No hardcoded paths — everything comes from the JSON config.
const std = @import("std");
const base = @import("base.zig");

/// Config entry for a Zig module domain.
pub const Config = struct {
    root_source: []const u8,
};

/// Build a Zig module domain.
pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: Config,
) base.DomainResult {
    const mod = b.createModule(.{
        .root_source_file = b.path(config.root_source),
        .target = target,
        .optimize = optimize,
    });

    return .{
        .archive = null,
        .module = mod,
    };
}
