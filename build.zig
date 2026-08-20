/// Zig build for the Tickoni supervisor and its unit tests.
///
/// Build the supervisor:
///   zig build
///
/// Run harness unit tests:
///   zig build test
///
/// Install coverage test binaries:
///   zig build cov
///
/// Compressed to ~30 lines via the BuildRegistry.
const std = @import("std");
const mod = @import("tickoni-build/mod.zig");
const unit_specs = @import("tickoni-build/test/unit_specs.zig");
const integration_specs = @import("tickoni-build/test/integration_specs.zig");
const system_specs = @import("tickoni-build/test/system_specs.zig");
const cov_specs = @import("tickoni-build/test/cov_specs.zig");
const reg = @import("tickoni-build/test/registry.zig");
const Registry = @import("tickoni-build/registry/registry.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib_dir: []const u8 = blk: {
        if (b.option([]const u8, "fd-lib-dir", "Firedancer library dir (required — see justfile build-tk)")) |val| break :blk val;
        std.debug.panic("fd-lib-dir is required. Run via 'just build-tk' or 'zig build -Dfd-lib-dir=<path>'.", .{});
    };

    // Build all domains from JSON config via BuildRegistry
    var registry = Registry.BuildRegistry.init(b.allocator, b, target, optimize, lib_dir);
    defer registry.deinit();

    // Get BuildRegistry domains for linking
    const ballet_domain = registry.get("ballet") orelse @panic("ballet domain not found");
    const flamenco_domain = registry.get("flamenco") orelse @panic("flamenco domain not found");
    const disco_domain = registry.get("disco") orelse @panic("disco domain not found");

    // Get all modules from mod.zig (legacy Zig module system)
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

    // Link domain archives via BuildRegistry
    exe.root_module.link_libc = true;
    exe.root_module.addLibraryPath(b.path(lib_dir));

    // On Linux: link shim C files and Firedancer archives
    if (target.result.os.tag == .windows) {
        // Windows: compile shim libraries and link
        const shim_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        shim_mod.addIncludePath(b.path("src"));
        shim_mod.addCSourceFiles(.{
            .files = &.{
                "src/tickoni/c_abi/shim/tango.c",
                "src/tickoni/c_abi/shim/wksp.c",
                "src/tickoni/c_abi/shim/sandbox.c",
                "src/tickoni/c_abi/shim/os.c",
                "src/tickoni/c_abi/shim/util.c",
                "src/tickoni/c_abi/shim/topo_run.c",
                "src/tickoni/c_abi/shim/topob.c",
                "src/tickoni/c_abi/shim/tile_run.c",
            },
            .flags = &.{
                "-std=c17",
                "-U__BMI2__",
                "-U__LZCNT__",
                "-DFD_HAS_HOSTED=1",
                "-DFD_HAS_WINDOWS=1",
                "-D_CRT_SECURE_NO_WARNINGS",
                "-DFD_IO_STYLE=1",
                "-DFD_LOG_STYLE=1",
                "-DFD_HAS_THREADS=1",
                "-DFD_HAS_ATOMIC=1",
                "-DFD_HAS_X86=1",
                "-DFD_HAS_SSE=1",
                "-DFD_HAS_AVX=1",
                "-DFD_HAS_AVX2=1",
                "-DFD_HAS_AESNI=1",
                "-DFD_IS_X86_64=1",
                "-DFD_HAS_INT128=0",
                "-DFD_HAS_DOUBLE=1",
                "-DFD_HAS_ALLOCA=1",
                "-Wno-format",
                "-Wno-format-extra-args",
            },
        });
        exe.root_module.linkLibrary(b.addLibrary(.{
            .name = "tickoni_supervisor_shim",
            .linkage = .static,
            .root_module = shim_mod,
        }));

        // Read Windows manifest fixups
        var io_threaded = std.Io.Threaded.init_single_threaded;
        const io = io_threaded.io();
        const manifest = std.Io.Dir.cwd().readFileAlloc(
            io,
            b.fmt("{s}/fd_windows_zig_supervisor_link.txt", .{lib_dir}),
            b.allocator,
            .limited(1024 * 1024),
        ) catch @panic("missing Windows FD Zig link manifest");
        defer b.allocator.free(manifest);
        var lines = std.mem.splitScalar(u8, manifest, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            exe.root_module.addObjectFile(.{ .cwd_relative = trimmed });
        }
    } else {
        // Linux: link shim C files and Firedancer archives via BuildRegistry domains
        // BuildRegistry domains (ballet, flamenco, disco) already compile and link
        // the shim C files + Firedancer archives. We only need to add the
        // platform-specific shim and link the archives.

        // Link Firedancer archives from BuildRegistry domains
        // Order matters: linker resolves symbols left-to-right.
        // disco needs ballet+flamenco symbols (fd_topo_*, fd_pod_query), so it goes first.
        if (disco_domain.archive) |arch| {
            exe.root_module.addObjectFile(arch.getEmittedBin());
        }
        // ballet -> libtickoni_ballet.a -> links libfd_ballet.a + libfd_util.a
        if (ballet_domain.archive) |arch| {
            exe.root_module.addObjectFile(arch.getEmittedBin());
        }
        // flamenco -> libtickoni_flamenco.a -> links libfd_tango.a + libfd_util.a
        if (flamenco_domain.archive) |arch| {
            exe.root_module.addObjectFile(arch.getEmittedBin());
        }
    }

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
            reg.registerTestLane(b, cov_step, spec, optimize, target);
        }
    }
}
