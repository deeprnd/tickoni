/// Helper functions for test execution in the Tickoni build system.
///
/// Uses the module loader to build domains from config and link
/// their archives into test binaries.

const std = @import("std");
const builder = @import("../domain/builder.zig");
const domain = @import("../domain/domain.zig");

/// Builder state for test execution. Uses the generic module loader.
pub const TestBuilder = struct {
    b: *std.Build,
    allocator: std.mem.Allocator,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_dir: []const u8,
    loader: builder.Loader,

    pub fn init(
        b: *std.Build,
        allocator: std.mem.Allocator,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) TestBuilder {
        var loader = builder.Loader.init(allocator, b, target, optimize, lib_dir);
        loader.loadAll() catch @panic("Failed to load domains from config");
        return .{
            .b = b,
            .allocator = allocator,
            .target = target,
            .optimize = optimize,
            .lib_dir = lib_dir,
            .loader = loader,
        };
    }

    pub fn deinit(self: *TestBuilder) void {
        self.loader.deinit();
    }

    /// Link a domain's archive into a test executable.
    pub fn linkDomain(self: *TestBuilder, test_exe: *std.Build.Step.Compile, name: []const u8) !void {
        if (self.loader.get(name)) |result| {
            if (result.archive) |a| {
                test_exe.root_module.addObjectFile(.{
                    .generated = .{
                        .index = a.getEmittedBin().generated.index,
                    },
                });
            }
        }
    }

    /// Link all required domain archives into a test executable.
    pub fn linkAll(self: *TestBuilder, test_exe: *std.Build.Step.Compile) !void {
        test_exe.root_module.link_libc = true;
        
        // Link domain archives from config
        for (generated.domain_configs) |dc| {
            if (std.mem.eql(u8, dc.strategy, "c_builder")) {
                try self.linkDomain(test_exe, dc.name);
            }
        }

        // Link Firedancer system libraries
        test_exe.root_module.addLibraryPath(self.b.path(self.lib_dir));
        test_exe.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_ballet.a", .{self.lib_dir}) });
        test_exe.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_util.a", .{self.lib_dir}) });
        test_exe.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_tango.a", .{self.lib_dir}) });
        test_exe.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_disco.a", .{self.lib_dir}) });

        if (test_exe.root_module.resolved_target.?.result.os.tag == .windows) {
            test_exe.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libuuid.a", .{self.lib_dir}) });
            test_exe.root_module.link_libcpp = true;
        }
    }
};

const generated = @import("../generated/config.zig");

pub fn addPlainTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    lib_dir: []const u8,
) *std.Build.Step.Run {
    var tb = TestBuilder.init(
        b,
        b.allocator,
        test_exe.root_module.resolved_target.?,
        test_exe.root_module.optimize orelse .Debug,
        lib_dir,
    );
    defer tb.deinit();
    tb.linkAll(test_exe) catch @panic("Failed to link domains");
    const run = b.addRunArtifact(test_exe);
    step.dependOn(&run.step);
    return run;
}

pub fn runTestsCmd(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    env: ?std.Build.EnvMap,
    lib_dir: []const u8,
) *std.Build.Step.Run {
    const run = addPlainTestRun(b, step, test_exe, lib_dir);
    if (env) |e| run.step.addEnvMap(e);
    return run;
}
