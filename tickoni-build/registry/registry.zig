/// BuildRegistry — Singleton + Factory + Composite pattern.
///
/// This is the central interface for the domain-driven build system.
///
/// Responsibilities:
///   - `init()`: Build all domains from config via strategy dispatch
///   - `get(name)`: Return Domain by name
///   - `dependentDomains(name)`: Transitive dependency graph
///
/// The registry owns the allocator for domain names. Users must call
/// `deinit()` when done.

const std = @import("std");
const base = @import("strategy/base.zig");
const c_builder = @import("strategy/c_builder.zig");
const zig_mod = @import("strategy/zig_module.zig");
const composite = @import("strategy/composite.zig");
const config = @import("../generated/config.zig");
const Domain = @import("domain.zig").Domain;

/// The BuildRegistry — a single source of truth for all domains.
pub const BuildRegistry = struct {
    allocator: std.mem.Allocator,
    domains: std.StringHashMap(Domain),
    /// Dependency graph: domain name → list of dependency domain names
    deps: std.StringHashMap([][]const u8),
    /// Track which domains have been built
    built: std.StringHashMap(void),

    /// Initialize the registry: build all domains from config.zig.
    /// Dependencies are resolved recursively.
    pub fn init(
        allocator: std.mem.Allocator,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) BuildRegistry {
        var registry = BuildRegistry{
            .allocator = allocator,
            .domains = std.StringHashMap(Domain).init(allocator),
            .deps = std.StringHashMap([][]const u8).init(allocator),
            .built = std.StringHashMap(void).init(allocator),
        };

        // Register dependency graph first
        for (config.domain_configs) |dc| {
            const deps = allocator.alloc([]const u8, dc.dependencies.len) catch
                @panic("OOM");
            for (dc.dependencies, 0..) |dep, i| {
                deps[i] = allocator.dupe(u8, dep) catch @panic("OOM");
            }
            registry.deps.put(dc.name, deps) catch @panic("OOM");
        }

        // Build all domains in dependency order
        for (config.domain_configs) |dc| {
            registry.buildDomain(dc, b, target, optimize, lib_dir) catch
                @panic("Failed to build domain: " ++ dc.name);
        }

        return registry;
    }

    pub fn deinit(self: *BuildRegistry) void {
        var it = self.deps.iterator();
        while (it.next()) |entry| {
            const deps = entry.value_ptr.*;
            for (deps) |d| {
                self.allocator.free(d);
            }
            self.allocator.free(deps);
        }
        self.deps.deinit();

        var it2 = self.domains.iterator();
        while (it2.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.domains.deinit();
        self.built.deinit();
    }

    /// Get a domain by name.
    pub fn get(self: *const BuildRegistry, name: []const u8) ?Domain {
        return self.domains.get(name);
    }

    /// Check if a domain exists.
    pub fn contains(self: *const BuildRegistry, name: []const u8) bool {
        return self.domains.contains(name);
    }

    /// Get transitive dependencies for a domain (including itself).
    pub fn dependentDomains(
        self: *const BuildRegistry,
        name: []const u8,
        seen: *std.StringHashMap(void),
        result: *std.ArrayList([]const u8),
    ) !void {
        if (seen.get(name)) |_| return; // already visited
        seen.putAssumeCapacity(name, {});

        // Add this domain
        result.append(self.allocator.dupe(u8, name) catch @panic("OOM")) catch
            @panic("OOM");

        // Get direct deps
        if (self.deps.get(name)) |direct_deps| {
            for (direct_deps) |dep| {
                try self.dependentDomains(dep, seen, result);
            }
        }
    }

    fn buildDomain(
        self: *BuildRegistry,
        dc: config.DomainConfig,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) !void {
        // Already built (leaf node)
        if (self.built.get(dc.name)) |_| return;

        // Build dependencies first
        for (dc.dependencies) |dep_name| {
            const dep = config.getDomainByName(dep_name) orelse {
                std.debug.panic(
                    "Domain '{s}' depends on unknown domain '{s}'",
                    .{ dc.name, dep_name },
                );
            };
            try self.buildDomain(dep, b, target, optimize, lib_dir);
        }

        const result = self.doBuildDomain(dc, b, target, optimize, lib_dir);

        const name = self.allocator.dupe(u8, dc.name) catch @panic("OOM");
        self.domains.put(name, result) catch @panic("OOM");
        self.built.put(dc.name, {}) catch @panic("OOM");
    }

    fn doBuildDomain(
        self: *BuildRegistry,
        dc: config.DomainConfig,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) Domain {
        return switch (std.meta.stringToEnum(base.Strategy, dc.strategy) orelse {
            std.debug.panic("Unknown strategy: {s}", .{dc.strategy});
        }) {
            .c_builder => self.buildCBuilder(dc, b, lib_dir),
            .zig_module => self.buildZigModule(dc, b, target, optimize),
            .composite => self.buildComposite(dc, b, target, optimize),
        };
    }

    fn buildCBuilder(
        self: *BuildRegistry,
        dc: config.DomainConfig,
        b: *std.Build,
        lib_dir: []const u8,
    ) Domain {
        const mod = b.createModule(.{
            .target = b.standardTargetOptions(.{}).result,
            .optimize = b.standardOptimizeOption(.{}),
            .link_libc = true,
        });
        mod.addIncludePath(b.path("src"));
        mod.addCSourceFiles(.{
            .files = dc.c_sources,
            .flags = dc.c_flags,
        });

        const archive = b.addLibrary(.{
            .name = dc.archive_name orelse dc.name,
            .root_module = mod,
        });

        archive.root_module.addLibraryPath(b.path(lib_dir));
        for (dc.object_deps) |od| {
            archive.root_module.addObjectFile(.{
                .cwd_relative = b.fmt("{s}/{s}", .{ lib_dir, od.path }),
            });
        }

        return .{
            .name = dc.name,
            .archive = archive,
            .module = mod,
            .strategy = .c_builder,
        };
    }

    fn buildZigModule(
        self: *BuildRegistry,
        dc: config.DomainConfig,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) Domain {
        var imports: [64]std.Build.Module.Import = undefined;
        var count: usize = 0;

        for (dc.dependencies) |dep_name| {
            if (self.get(dep_name)) |dep| {
                imports[count] = .{
                    .name = dep_name,
                    .module = dep.module,
                };
                count += 1;
            }
        }

        const mod = b.createModule(.{
            .root_source_file = b.path(dc.root_source.?),
            .target = target,
            .optimize = optimize,
            .imports = imports[0..count],
        });

        return .{
            .name = dc.name,
            .archive = null,
            .module = mod,
            .strategy = .zig_module,
        };
    }

    fn buildComposite(
        self: *BuildRegistry,
        dc: config.DomainConfig,
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) Domain {
        var imports: [64]std.Build.Module.Import = undefined;
        var count: usize = 0;

        for (dc.dependencies) |dep_name| {
            if (self.get(dep_name)) |dep| {
                imports[count] = .{
                    .name = dep_name,
                    .module = dep.module,
                };
                count += 1;
            }
        }

        const mod = b.createModule(.{
            .root_source_file = b.path(dc.root_source.?),
            .target = target,
            .optimize = optimize,
            .imports = imports[0..count],
        });

        return .{
            .name = dc.name,
            .archive = null,
            .module = mod,
            .strategy = .composite,
        };
    }
};
