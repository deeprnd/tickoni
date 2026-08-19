/// CShimStrategy: compiles C source files into a static archive, links object deps.
///
/// Reads from config: c_sources, platform_shims, object_deps, c_flags.
/// No hardcoded paths — everything comes from the JSON config.

const std = @import("std");

/// Config entry for a C shim domain.
pub const Config = struct {
    archive_name: []const u8,
    c_sources: []const []const u8,
    platform_shims: std.StringArrayHashMapUnmanaged([]const []const u8),
    object_deps: []const ObjectDep,
    c_flags: []const []const u8,
    lib_dir: []const u8,
};

/// Object file dependency descriptor.
pub const ObjectDep = struct {
    dep_type: DepType,
    path: []const u8,
};

/// Object dependency type — maps to LazyPath variants.
pub const DepType = enum {
    cwd_relative,
};

/// Create a LazyPath from a config descriptor.
fn makeLazyPath(b: *std.Build, dep: ObjectDep) std.Build.LazyPath {
    return switch (dep.dep_type) {
        .cwd_relative => std.Build.LazyPath{ .cwd_relative = dep.path },
    };
}

/// Build a C shim domain: compile C sources into archive, link object deps.
pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, config: Config) struct {
    archive: *std.Build.Step.Compile,
    module: *std.Build.Module,
} {
    // Select platform-specific shims
    const platform_shims = getPlatformShims(config.platform_shims, target.result.os.tag);

    // Combine base C sources + platform shims
    var all_c_sources = b.allocator.alloc([]const u8, config.c_sources.len + platform_shims.len) catch
        @panic("OOM allocating C sources");
    var idx: usize = 0;
    for (config.c_sources) |s| {
        all_c_sources[idx] = s;
        idx += 1;
    }
    for (platform_shims) |s| {
        all_c_sources[idx] = s;
        idx += 1;
    }

    // Create module with C source files
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("src"));
    mod.addCSourceFiles(.{
        .files = all_c_sources,
        .flags = config.c_flags,
    });

    // Create static archive
    const archive = b.addLibrary(.{
        .name = config.archive_name,
        .root_module = mod,
    });

    // Link object file dependencies (pre-built .a archives)
    archive.root_module.addLibraryPath(b.path(config.lib_dir));
    for (config.object_deps) |dep| {
        archive.root_module.addObjectFile(.{
            .cwd_relative = dep.path,
        });
    }

    b.allocator.free(all_c_sources);

    return .{
        .archive = archive,
        .module = mod,
    };
}

/// Get platform-specific shim files for the target OS.
fn getPlatformShims(
    shims_map: std.StringArrayHashMapUnmanaged([]const []const u8),
    os_tag: std.Target.Os.Tag,
) []const []const u8 {
    const key = switch (os_tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => "",
    };

    if (key.len == 0) return &.{};

    return shims_map.get(key) orelse &.{};
}
