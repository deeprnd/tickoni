/// Common lane helpers and data-driven test registration types.
///
/// TestSpec, TestLinkage, TestAction, TestBuilder: spec-driven registration.
/// TestBuilder.registerRunTest returns a compile step for later sequential
/// execution via shims.addPlainTestRunSeries; registerCov installs coverage
/// artifacts; registerSystemTest wires system-test lanes.

const std = @import("std");
const shims = @import("lib/shims.zig");
const codec = @import("lib/codec.zig");
const firedancer = @import("lib/firedancer.zig");
const topo_run = @import("lib/topo_run.zig");
const tile_run = @import("lib/tile_run.zig");

/// Build-time linkage flags for a test.
pub const TestLinkage = packed struct(u8) {
    needs_codec: bool = false,
    needs_firedancer: bool = false,
    needs_topo_run: bool = false,
    needs_tile_run: bool = false,
    needs_libc: bool = false,
    needs_audit: bool = false,
    needs_audit_disco: bool = false,
    needs_cabi_shim: bool = false,
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
        if (spec.linkage.needs_topo_run) topo_run.linkTickoniTopoRun(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_libc) t.root_module.link_libc = true;
        if (spec.linkage.needs_tile_run) tile_run.linkTickoniTileRun(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_cabi_shim) {
            const cabi_shim_lib = codec.addTickoniCabShimLibrary(self.b, self.target, self.optimize);
            t.root_module.linkLibrary(cabi_shim_lib);
            // C ABI shim needs libfd_tango.a and libfd_util.a from Firedancer.
            firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);
        }
        if (spec.linkage.needs_audit) {
            const shim_lib = codec.addTickoniAuditShimLibrary(self.b, self.target, self.optimize, self.fd_lib_dir);
            t.root_module.linkLibrary(shim_lib);
            // Audit shim requires libfd_disco.a for fd_topo_obj_laddr and
            // fd_metrics_* symbols.  Must be a direct link on the test step;
            // embedding it inside the static archive does not work (Zig does
            // not resolve symbols through nested static archives).
            t.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_disco.a", .{self.fd_lib_dir}) });
        }

        cov_step.dependOn(&self.b.addInstallArtifact(t, .{
            .dest_dir = .{ .override = .{ .custom = "cov" } },
        }).step);
    }

    /// Register a test compile step for later sequential execution.
    /// The caller collects all returned compile steps and passes them to
    /// `shims.addPlainTestRunSeries` to avoid Zig 0.17's protocol-mode
    /// `--listen=-` which blocks on stdin.
    pub fn registerRunTest(
        self: *const TestBuilder,
        spec: TestSpec,
    ) *std.Build.Step.Compile {
        const t_mod = self.b.createModule(.{
            .root_source_file = self.b.path(spec.source_file),
            .target = self.target,
            .optimize = self.optimize,
            .imports = if (spec.imports.len > 0) spec.imports else &.{},
        });
        const t = self.b.addTest(.{ .name = spec.name, .root_module = t_mod });

        if (spec.linkage.needs_codec) codec.linkTickoniCodec(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_firedancer) firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_topo_run) topo_run.linkTickoniTopoRun(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_libc) t.root_module.link_libc = true;
        if (spec.linkage.needs_tile_run) tile_run.linkTickoniTileRun(self.b, t, self.fd_lib_dir);
        if (spec.linkage.needs_cabi_shim) {
            const cabi_shim_lib = codec.addTickoniCabShimLibrary(self.b, self.target, self.optimize);
            t.root_module.linkLibrary(cabi_shim_lib);
            // C ABI shim needs libfd_tango.a and libfd_util.a from Firedancer.
            firedancer.linkTickoniFiredancer(self.b, t, self.fd_lib_dir);
        }
        if (spec.linkage.needs_audit) {
            const shim_lib = codec.addTickoniAuditShimLibrary(self.b, self.target, self.optimize, self.fd_lib_dir);
            t.root_module.linkLibrary(shim_lib);
            // Audit shim requires libfd_disco.a for fd_topo_obj_laddr and
            // fd_metrics_* symbols.  Must be a direct link on the test step;
            // embedding it inside the static archive does not work (Zig does
            // not resolve symbols through nested static archives).
            t.root_module.addObjectFile(.{ .cwd_relative = self.b.fmt("{s}/libfd_disco.a", .{self.fd_lib_dir}) });
        }

        return t;
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
