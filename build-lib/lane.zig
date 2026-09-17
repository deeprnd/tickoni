/// Common lane helpers and data-driven test registration types.
///
/// createRunTestsCmd: build-time test runner command.
/// TestSpec, TestLinkage, TestAction, TestBuilder: data-driven test registration.

const std = @import("std");
const shims = @import("lib/shims.zig");
const codec = @import("lib/codec.zig");
const firedancer = @import("lib/firedancer.zig");

/// Create the run-tests command that executes all test binaries
/// sequentially via a bash script (avoids Zig's --listen=- parallel
/// coordination which panics with EndOfStream when 48+ test binaries
/// communicate over the same pipe).
pub fn createRunTestsCmd(b: *std.Build) *std.Build.Step.Run {
    const run_tests_cmd = std.Build.Step.Run.create(b, "run-tests");
    const build_root_str = b.root.toString(b.allocator) catch unreachable;
    defer b.allocator.free(build_root_str);
    var script_buf: [4096]u8 = undefined;
    const full_script_path = std.fmt.bufPrint(
        &script_buf,
        "{s}/contrib/test/run_test_series.sh",
        .{build_root_str},
    ) catch unreachable;
    run_tests_cmd.addArgs(&[_][]const u8{
        "bash",
        full_script_path,
    });
    run_tests_cmd.setCwd(b.path("."));
    return run_tests_cmd;
}

/// Build-time linkage flags for a test.
pub const TestLinkage = packed struct(u8) {
    needs_codec: bool = false,
    needs_firedancer: bool = false,
    needs_topo_run: bool = false,
    needs_tile_run: bool = false,
    needs_libc: bool = false,
    _pad: u3 = 0,
};

/// Action to dispatch for a registered test.
pub const TestAction = enum { run, cov, system_run };

/// A single test specification — the data that drives test registration.
/// - name: binary name
/// - source_file: path to the .zig file to compile
/// - imports: module import graph (may be empty for standalone tests)
/// - linkage: which shim libraries to link
/// - action: what to do with the compiled test
pub const TestSpec = struct {
    name: []const u8,
    source_file: []const u8,
    imports: []const std.Build.Module.Import = &.{},
    linkage: TestLinkage = TestLinkage{},
    action: TestAction = .cov,
};

/// TestBuilder handles: addTest, linkage, dependOn, addArtifactArg, installArtifact.
pub const TestBuilder = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,

    /// Register tests from spec array. Handles linkage and step wiring.
    pub fn registerTestLanes(
        self: *const TestBuilder,
        specs: []const TestSpec,
        step: *std.Build.Step,
    ) void {
        for (specs) |spec| self.registerOne(spec, step);
    }

    /// Register a single test with installArtifact to zig-out/cov/.
    pub fn registerCov(
        self: *const TestBuilder,
        spec: TestSpec,
        cov_step: *std.Build.Step,
    ) void {
        const t_mod = self.b.createModule(.{
            .root_source_file = self.b.path(spec.source_file),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (spec.imports.len > 0) spec.imports else &.{},
        });
        const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

        if (spec.linkage.needs_codec) codec.linkTickoniCodec(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_firedancer) firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_libc) t.root_module.link_libc = true;

        cov_step.dependOn(&self.b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    /// Register a test for the run-tests lane.
    pub fn registerRunTest(
        self: *const TestBuilder,
        spec: TestSpec,
        test_step: *std.Build.Step,
        run_cmd: *std.Build.Step.Run,
    ) void {
        const t_mod = self.b.createModule(.{
            .root_source_file = self.b.path(spec.source_file),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (spec.imports.len > 0) spec.imports else &.{},
        });
        const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

        if (spec.linkage.needs_codec) codec.linkTickoniCodec(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_firedancer) firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);

        test_step.dependOn(&t.step);
        run_cmd.addArtifactArg(t);
    }

    /// Register a test for the system-test lane.
    pub fn registerSystemTest(
        self: *const TestBuilder,
        spec: TestSpec,
        system_step: *std.Build.Step,
    ) void {
        const t_mod = self.b.createModule(.{
            .root_source_file = self.b.path(spec.source_file),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (spec.imports.len > 0) spec.imports else &.{},
        });
        const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

        if (spec.linkage.needs_codec) codec.linkTickoniCodec(self.b, t, self.fd_lib_dir);

        const run_sys = shims.addPlainTestRun(self.b, t);
        system_step.dependOn(&run_sys.step);
    }
};
