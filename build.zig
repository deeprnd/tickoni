/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run harness unit tests:
///   zig build test
///
/// Install Zig test binaries for kcov coverage:
///   zig build cov
///
/// Reuses: build/lib/ (C shim helpers), build/mod/ (module declarations),
///         build/test/ (unit/integration/system/cov specs).
const std = @import("std");
const lib = @import("tickoni-build/lib.zig");
const mod = @import("tickoni-build/mod.zig");
const unit_specs = @import("tickoni-build/test/unit_specs.zig");
const integration_specs = @import("tickoni-build/test/integration_specs.zig");
const system_specs = @import("tickoni-build/test/system_specs.zig");
const cov_specs = @import("tickoni-build/test/cov_specs.zig");
const registry = @import("tickoni-build/test/registry.zig");

/// Create a module with imports, used by test spec helpers.
fn makeModule(b: *std.Build, root: []const u8, imports: []const std.Build.Module.Import, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const m = b.createModule(.{ .root_source_file = b.path(root), .target = target, .optimize = optimize });
    if (imports.len > 0) m.addImports(imports);
    return m;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_dir: []const u8 = blk: {
        if (b.option([]const u8, "fd-lib-dir", "Firedancer library dir (required — see justfile build-tk)")) |val| break :blk val;
        std.debug.panic("fd-lib-dir is required. Run via 'just build-tk' or 'zig build -Dfd-lib-dir=<path>'.", .{});
    };
    // Get all modules in one call
    const all = mod.allModules(b, target, optimize, lib_dir);
    const m = all.modules;
    const tm = all.test_modules;

    // Supervisor executable
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = m.version },
            .{ .name = "runtime", .module = m.runtime },
            .{ .name = "tiles", .module = m.tiles },
            .{ .name = "c_abi", .module = m.c_abi },
            .{ .name = "util", .module = m.util },
            .{ .name = "topologies", .module = m.topologies_named },
            .{ .name = "doctor_checks", .module = m.doctor_checks },
            .{ .name = "doctor_output", .module = m.doctor_output },
            .{ .name = "demo_preflight", .module = m.demo_preflight },
            .{ .name = "demo_cli", .module = m.demo_cli },
            .{ .name = "demo_conformance", .module = m.demo_conformance },
            .{ .name = "demo_comparator", .module = m.demo_comparator },
            .{ .name = "demo_runner", .module = m.demo_runner },
            .{ .name = "demo_substitution", .module = m.demo_substitution },
            .{ .name = "logger", .module = m.logger },
        },
    });

    const exe = b.addExecutable(.{ .name = "tickoni-supervisor", .root_module = main_mod });
    if (target.result.os.tag == .windows) {
        exe.root_module.linkLibrary(lib.firedancer_shims.addTickoniSupervisorShimLibrary(b, target, optimize));
        lib.firedancer_shims.addWindowsFdManifestFixups(b, exe, b.fmt("{s}/fd_windows_zig_supervisor_link.txt", .{lib_dir}));
    } else {
        lib.codec.addTickoniCodecShim(b, exe);
        lib.firedancer_shims.addTickoniFiredancerShims(b, exe);
        lib.topo_run.addTickoniTopoRunShims(b, exe);
        lib.tile_run.addTickoniTileRunShim(b, exe);
    }
    lib.firedancer_shims.linkTickoniFiredancer(b, exe, lib_dir);
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    if (@hasField(std.Build, "args")) {
        if (b.args) |argv| run_exe.addArgs(argv);
    }
    const run_step = b.step("run", "Run tickoni-supervisor");
    run_step.dependOn(&run_exe.step);

    // Check step
    _ = b.step("check", "Check Zig + C compilation without full link dependencies");

    // Test step (gated behind -Dtest=true)
    const build_tests = b.option(bool, "test", "Compile and run Tickoni test binaries") orelse false;
    if (build_tests) {
        const test_step = b.step("test", "Run all Tickoni tests");

        // Unit tests
        unit_specs.registerUnitSpecs(b, m, target, optimize, test_step, lib_dir);

        // Integration tests
        integration_specs.registerIntegrationSpecs(b, m, tm, target, optimize, test_step, lib_dir);

        // System tests
        system_specs.registerSystemSpecs(b, m, tm, target, optimize, test_step, lib_dir);

        // Coverage tests
        const cov_step = b.step("cov", "Install test binaries for kcov coverage");
        const specs = cov_specs.covSpecs(b, m, tm, null, target);
        for (specs) |spec| {
            registry.registerTestLane(b, cov_step, spec, optimize, target);
        }
    }
}
