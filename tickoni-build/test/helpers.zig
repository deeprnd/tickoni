/// Helper functions for test execution in the Tickoni build system.
///
/// Uses domain archives instead of inline C compilation. Each test binary
/// links the required domain archives (libtickoni_ballet.a,
/// libtickoni_flamenco.a, libtickoni_disco.a) which already contain
/// Tickoni shim C compiled once.

const std = @import("std");
const domain = @import("../domain/domain.zig");
const builder = @import("../domain/builder.zig");

/// Builder state for domain archives. Stores the built archives
/// so they can be linked into multiple test binaries without
/// rebuilding.
pub const DomainBuilder = struct {
    /// The build system reference (shared across all tests)
    b: *std.Build,
    /// Resolved target (shared across all tests)
    target: std.Build.ResolvedTarget,
    /// Optimize mode (shared across all tests)
    optimize: std.builtin.OptimizeMode,
    /// Library directory for Firedancer archives
    lib_dir: []const u8,
    /// Built domain map keyed by FiredancerShimDomainId enum
    domains: builder.DomainMap,

    /// Create a new DomainBuilder. Call this once from build.zig
    /// and pass it to addPlainTestRun().
    pub fn init(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        lib_dir: []const u8,
    ) DomainBuilder {
        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
            .lib_dir = lib_dir,
            .domains = builder.buildFiredancerShimDomains(b, target, optimize, lib_dir),
        };
    }

    /// Link all domain archives into the test binary as OBJECT FILES.
    /// Domain archives are built as .a files by the domain builders;
    /// we link them via the compile step's object file list.
    /// This does NOT create module imports (no --dep flags), so it
    /// works for any compile step, not just tests.
    pub fn link(self: *const DomainBuilder, test_exe: *std.Build.Step.Compile) void {
        // Enable libc linking for test binaries (domain archives compile C code)
        test_exe.root_module.link_libc = true;
        // Link domain archives as .a files (not as module imports)
        for (domain.FiredancerShimDomainId.all) |id| {
            const d = self.domains.get(id) orelse unreachable;
            test_exe.root_module.addObjectFile(.{
                .generated = .{
                    .index = d.archive.getEmittedBin().generated.index,
                },
            });
        }

        // Link pre-built Firedancer archives for fd_* symbols not wrapped by Tickoni shims
        test_exe.root_module.addLibraryPath(self.b.path(self.lib_dir));
        test_exe.root_module.addObjectFile(.{
            .cwd_relative = self.b.fmt("{s}/libfd_ballet.a", .{self.lib_dir}),
        });
        test_exe.root_module.addObjectFile(.{
            .cwd_relative = self.b.fmt("{s}/libfd_util.a", .{self.lib_dir}),
        });
        test_exe.root_module.addObjectFile(.{
            .cwd_relative = self.b.fmt("{s}/libfd_tango.a", .{self.lib_dir}),
        });
        test_exe.root_module.addObjectFile(.{
            .cwd_relative = self.b.fmt("{s}/libfd_disco.a", .{self.lib_dir}),
        });

        if (test_exe.root_module.resolved_target.?.result.os.tag == .windows) {
            test_exe.root_module.addObjectFile(.{
                .cwd_relative = self.b.fmt("{s}/libuuid.a", .{self.lib_dir}),
            });
            test_exe.root_module.link_libcpp = true;
        }
    }
};

/// Adds a run step for the given test binary. Links domain archives
/// (libtickoni_ballet.a, libtickoni_flamenco.a, libtickoni_disco.a)
/// so that c_abi AND firedancer symbols are available without
/// duplicating C compilation into every test binary.
pub fn addPlainTestRun(
    b: *std.Build,
    step: *std.Build.Step,
    test_exe: *std.Build.Step.Compile,
    lib_dir: []const u8,
) *std.Build.Step.Run {
    const domains = DomainBuilder.init(b, test_exe.root_module.resolved_target.?, test_exe.root_module.optimize orelse .Debug, lib_dir);
    domains.link(test_exe);
    const run = b.addRunArtifact(test_exe);
    step.dependOn(&run.step);
    return run;
}

/// Runs the given test executable with optional environment variables.
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
