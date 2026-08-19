/// Module loader — reads config and builds domains.
///
/// No hardcoded domain names. Reads from build_config.json and builds
/// whatever domains are defined, resolving dependencies recursively.

const std = @import("std");
const base = @import("../strategy/base.zig");
const c_builder = @import("../strategy/c_builder.zig");
const zig_mod = @import("../strategy/zig_module.zig");
const composite = @import("../strategy/composite.zig");
const domain = @import("domain.zig");
const generated = @import("../generated/config.zig");

/// Loader state — builds all domains from config.
pub const Loader = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_dir: []const u8,
    map: domain.DomainMap,
    loading: std.StringHashMap(bool),

    pub fn init(
        allocator: std.mem.Allocator,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) Loader {
        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .lib_dir = lib_dir,
            .map = domain.initDomainMap(allocator) catch @panic("OOM"),
            .loading = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *Loader) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            const result = entry.value_ptr.*;
            if (result.archive) |a| {
                a.root_module.deinit();
                // Don't free the archive — it's owned by b
            }
        }
        self.map.deinit();
        self.loading.deinit();
    }

    /// Build all domains from config. Dependencies are resolved recursively.
    pub fn loadAll(self: *Loader) !void {
        for (generated.domain_configs) |dc| {
            try self.loadDomain(dc);
        }
    }

    fn loadDomain(self: *Loader, dc: generated.DomainConfig) !void {
        // Check for cycles
        if (self.loading.get(dc.name)) |_| {
            std.debug.panic("Circular dependency detected: {s}", .{dc.name});
        }
        try self.loading.put(dc.name, true);
        defer self.loading.remove(dc.name);

        // Check if already built
        if (self.map.contains(dc.name)) return;

        // Resolve dependencies first
        for (dc.dependencies) |dep_name| {
            const dep = generated.getDomainByName(dep_name) orelse {
                std.debug.panic("Domain '{s}' depends on unknown domain '{s}'", .{ dc.name, dep_name });
            };
            try self.loadDomain(dep);
        }

        // Build this domain
        const result = try self.buildDomain(dc);
        try self.map.put(dc.name, result);
    }

    fn buildDomain(self: *Loader, dc: generated.DomainConfig) !base.DomainResult {
        return switch (std.meta.stringToEnum(base.Strategy, dc.strategy) orelse {
            std.debug.panic("Unknown strategy: {s}", .{dc.strategy});
        }) {
            .c_builder => self.buildCBuilder(dc),
            .zig_module => self.buildZigModule(dc),
            .composite => self.buildComposite(dc),
        };
    }

    fn buildCBuilder(self: *Loader, dc: generated.DomainConfig) base.DomainResult {
        // Find dependencies that produced archives
        var archive_imports: [16]std.Build.Module.Import = undefined;
        var count: usize = 0;
        for (dc.dependencies) |dep_name| {
            if (self.map.get(dep_name)) |dep_result| {
                if (dep_result.archive) |a| {
                    archive_imports[count] = .{
                        .name = dep_name,
                        .module = a.root_module,
                    };
                    count += 1;
                }
            }
        }

        const config = c_builder.Config{
            .archive_name = dc.archive_name orelse dc.name,
            .c_sources = dc.c_sources,
            .platform_sources = std.StringArrayHashMapUnmanaged([]const []const u8){},
            .object_deps = dc.object_deps,
            .c_flags = dc.c_flags,
            .lib_dir = self.lib_dir,
        };

        const result = c_builder.build(self.b, self.target, self.optimize, config);
        return .{
            .archive = result.archive,
            .module = result.module,
        };
    }

    fn buildZigModule(self: *Loader, dc: generated.DomainConfig) base.DomainResult {
        // Build dependency modules first
        var imports: [16]std.Build.Module.Import = undefined;
        var count: usize = 0;
        for (dc.dependencies) |dep_name| {
            if (self.map.get(dep_name)) |dep_result| {
                imports[count] = .{
                    .name = dep_name,
                    .module = dep_result.module,
                };
                count += 1;
            }
        }

        const mod = self.b.createModule(.{
            .root_source_file = self.b.path(dc.root_source.?),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (count > 0) &imports[0..count].* else &[_]std.Build.Module.Import{},
        });

        return .{
            .archive = null,
            .module = mod,
        };
    }

    fn buildComposite(self: *Loader, dc: generated.DomainConfig) base.DomainResult {
        // Build dependency modules first
        var imports: [16]std.Build.Module.Import = undefined;
        var count: usize = 0;
        for (dc.dependencies) |dep_name| {
            if (self.map.get(dep_name)) |dep_result| {
                imports[count] = .{
                    .name = dep_name,
                    .module = dep_result.module,
                };
                count += 1;
            }
        }

        const mod = self.b.createModule(.{
            .root_source_file = self.b.path(dc.root_source.?),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (count > 0) &imports[0..count].* else &[_]std.Build.Module.Import{},
        });

        return .{
            .archive = null,
            .module = mod,
        };
    }

    pub fn get(self: *Loader, name: []const u8) ?domain.DomainResult {
        return self.map.get(name);
    }
};
