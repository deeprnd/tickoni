/// CompositeStrategy: creates a Zig module from a root source file,
/// and imports dependencies from other domains.
///
/// Reads from config: root_source, dependencies (array of domain names).
/// Dependencies are resolved by the registry at init time; here we
/// receive the already-resolved import list.
///
/// No hardcoded paths — everything comes from the JSON config.
const std = @import("std");
const base = @import("base.zig");

/// Config entry for a composite domain.
pub const Config = struct {
    root_source: []const u8,
    /// Domain names this domain depends on (resolved by registry into imports)
    deps_imports: []std.Build.Module.Import,
};

/// Build a composite domain: create module from root_source, wire up imports.
pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    config: Config,
) base.DomainResult {
    var imports: [64]std.Build.Module.Import = undefined;
    var count: usize = 0;

    // Add dependency imports
    for (config.deps_imports) |dep_import| {
        imports[count] = dep_import;
        count += 1;
    }

    const mod = b.createModule(.{
        .root_source_file = b.path(config.root_source),
        .target = target,
        .optimize = optimize,
        .imports = if (count > 0) &imports[0..count].* else &[_]std.Build.Module.Import{},
    });

    return .{
        .archive = null,
        .module = mod,
    };
}
