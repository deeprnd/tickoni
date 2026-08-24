/// CBuilderStrategy: compiles C source files into a static archive, links object deps.
///
/// Reads from config: c_sources, platform_sources, object_deps, c_flags, lib_dir.
/// All paths in object_deps are relative to lib_dir.
///
/// This is a generic C code builder — it just compiles C files into an archive.

const std = @import("std");
const base = @import("base.zig");

/// Config entry for a C builder domain.
pub const Config = struct {
    archive_name: []const u8,
    c_sources: []const []const u8,
    platform_sources: std.StringArrayHashMapUnmanaged([]const []const u8),
    object_deps: []const ObjectDep,
    c_flags: []const []const u8,
    lib_dir: []const u8,
};

/// Object file dependency descriptor.
pub const ObjectDep = struct {
    path: []const u8,
};

/// Build a C domain: compile C sources into archive, link object deps.
pub fn build(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, config: Config) base.DomainResult {
    const platform_sources = getPlatformSources(config.platform_sources, target.result.os.tag);

    var all_c_sources = b.allocator.alloc([]const u8, config.c_sources.len + platform_sources.len) catch
        @panic("OOM allocating C sources");
    var idx: usize = 0;
    for (config.c_sources) |s| {
        all_c_sources[idx] = s;
        idx += 1;
    }
    for (platform_sources) |s| {
        all_c_sources[idx] = s;
        idx += 1;
    }

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

    const archive = b.addLibrary(.{
        .name = config.archive_name,
        .root_module = mod,
    });

    // Link object file dependencies (pre-built .a archives)
    // NOTE: addObjectFile on a Library step doesn't resolve symbols.
    // We store the paths here and link them at the exe level instead.
    // The domain archives are self-contained; exe resolves Firedancer symbols.
    _ = config.lib_dir;
    _ = config.object_deps;

    b.allocator.free(all_c_sources);

    return .{
        .archive = archive,
        .module = mod,
    };
}

fn getPlatformSources(
    sources_map: std.StringArrayHashMapUnmanaged([]const []const u8),
    os_tag: std.Target.Os.Tag,
) []const []const u8 {
    const key = switch (os_tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => "",
    };

    if (key.len == 0) return &.{};
    return sources_map.get(key) orelse &.{};
}
