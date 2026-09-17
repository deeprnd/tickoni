/// Build helpers for supervisor executable, CLI executable, check step,
/// and fixture path verification. Extracted from build.zig.

const std = @import("std");
const shims = @import("shims.zig");
const codec = @import("codec.zig");
const firedancer = @import("firedancer.zig");
const topo_run = @import("topo_run.zig");
const tile_run = @import("tile_run.zig");

// Re-export the canonical Shared from modules.zig so helpers can use it.
pub const Shared = @import("../mod/modules.zig").Shared;

/// Link the common Firedancer + Tickoni shim libraries for a supervisor
/// executable. Both x86_64 and aarch64 use the same 5 linkage calls;
/// aarch64 additionally links libc's `atomic` library.
fn linkSupervisorTarget(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, fd_lib_dir: []const u8) void {
    codec.linkTickoniCodec(b, exe, fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, exe, fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, exe, fd_lib_dir);
    tile_run.linkTickoniTileRun(b, exe, fd_lib_dir);
    codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    if (target.result.cpu.arch == .aarch64) {
        exe.root_module.linkSystemLibrary("atomic", .{});
    }
}

/// Create the supervisor executable.
pub fn createSupervisorExe(
    b: *std.Build,
    shared: Shared,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) *std.Build.Step.Compile {
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = shared.version },
            .{ .name = "runtime", .module = shared.runtime },
            .{ .name = "tiles", .module = shared.tiles },
            .{ .name = "c_abi", .module = shared.c_abi },
            .{ .name = "util", .module = shared.util },
            .{ .name = "topologies", .module = shared.topologies },
            .{ .name = "doctor_checks", .module = shared.doctor_checks },
            .{ .name = "doctor_output", .module = shared.doctor_output },
            .{ .name = "demo_preflight", .module = shared.demo_preflight },
            .{ .name = "demo_cli", .module = shared.demo_cli },
            .{ .name = "demo_conformance", .module = shared.demo_conformance },
            .{ .name = "demo_comparator", .module = shared.demo_comparator },
            .{ .name = "demo_runner", .module = shared.demo_runner },
            .{ .name = "demo_substitution", .module = shared.demo_substitution },
            .{ .name = "logger", .module = shared.logger },
        },
    });
    const exe = b.addExecutable(.{
        .name = "tickoni-supervisor",
        .root_module = main_mod,
    });
    if (target.result.os.tag == .windows) {
        exe.root_module.linkLibrary(codec.addTickoniSupervisorShimLibrary(b, target, optimize));
        codec.addWindowsFdManifestFixups(b, exe, b.fmt("{s}/fd_windows_zig_supervisor_link.txt", .{fd_lib_dir}));
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    } else if (target.result.cpu.arch == .aarch64) {
        codec.linkTickoniCodec(b, exe, fd_lib_dir);
        firedancer.linkTickoniFiredancer(b, exe, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, exe, fd_lib_dir);
        tile_run.linkTickoniTileRun(b, exe, fd_lib_dir);
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
        exe.root_module.linkSystemLibrary("atomic", .{});
    } else {
        codec.linkTickoniCodec(b, exe, fd_lib_dir);
        firedancer.linkTickoniFiredancer(b, exe, fd_lib_dir);
        topo_run.linkTickoniTopoRun(b, exe, fd_lib_dir);
        tile_run.linkTickoniTileRun(b, exe, fd_lib_dir);
        codec.addTickoniSystemLibraries(b, exe, fd_lib_dir, &.{ "fd_disco", "fd_waltz", "fd_tango", "fd_ballet", "fd_util" });
    }
    return exe;
}

/// Create the CLI executable.
pub fn createCliExe(
    b: *std.Build,
    investment_demo: *std.Build.Step.Compile,
    shared: Shared,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) *std.Build.Step.Compile {
    const cli_main_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tickoni_cli/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "investment_demo", .module = investment_demo.root_module },
            .{ .name = "tier", .module = shared.tier },
            .{ .name = "doctor_output", .module = shared.doctor_output },
            .{ .name = "demo_manifest", .module = shared.demo_manifest },
            .{ .name = "demo_preflight", .module = shared.demo_preflight },
            .{ .name = "version", .module = shared.version },
        },
    });
    const cli_exe = b.addExecutable(.{
        .name = "tickoni",
        .root_module = cli_main_mod,
    });
    cli_exe.root_module.addCSourceFiles(.{
        .files = &.{ "src/tickoni/util/compiler_version.c" },
    });
    if (target.result.os.tag == .windows) {
        cli_exe.root_module.linkLibrary(codec.addTickoniCodecShimLibrary(b, target, optimize, "tickoni-codec-shims"));
        codec.addWindowsFdManifestFixups(b, cli_exe, b.fmt("{s}/fd_windows_zig_codec_link.txt", .{fd_lib_dir}));
        codec.addTickoniSystemLibraries(b, cli_exe, fd_lib_dir, &.{ "fd_ballet", "fd_util" });
        cli_exe.root_module.linkSystemLibrary("crypt32", .{ .use_pkg_config = .no });
    } else {
        codec.linkTickoniCodec(b, cli_exe, fd_lib_dir);
    }
    return cli_exe;
}

/// Create the check step (compile-check Zig + C without full link deps).
pub fn createCheckStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) *std.Build.Step {
    const check_step = b.step("check", "Check Zig + C compilation without full link dependencies");
    const c_compile_check_step = b.step("check-c-compile", "Compile-check all C shim files and print errors to stdout");
    const cache_o_dir = "build/.zig-cache/o";
    {
        const ensure_dir = b.addSystemCommand(&.{ "mkdir", "-p", cache_o_dir });
        c_compile_check_step.dependOn(&ensure_dir.step);
    }
    inline for (shims.shim_c_files) |shim_file| {
        const c_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -std=c17 -UBMI2 -ULZCNT -DFD_HAS_HOSTED=1 {s} -o {s}/{s}.o {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                cache_o_dir,
                shim_file,
                b.fmt("src/tickoni/c_abi/shim/{s}", .{shim_file}),
            }),
        });
        c_compile_check_step.dependOn(&c_check.step);
    }
    {
        const getrandom_check = b.addSystemCommand(&.{
            "sh", "-c",
            b.fmt("zig cc -target {s} -c -I src -I src/util -I src/disco -I src/ballet -std=c17 -DFD_HAS_HOSTED=1 {s} -o {s}/test_fd_shmem_getrandom.o {s} 2>&1 || true", .{
                shims.buildTriple(b, target),
                shims.shimCFlagsFor(target.result)[0],
                cache_o_dir,
                "src/util/shmem/test_fd_shmem_getrandom.c",
            }),
        });
        c_compile_check_step.dependOn(&getrandom_check.step);
    }
    check_step.dependOn(c_compile_check_step);
    return check_step;
}

/// Fixture directories and proto files to verify.
const fixture_dirs = [_][]const u8{
    "src/tickoni/test/fixtures/investment/scenarios",
    "src/tickoni/test/fixtures/portfolio",
    "src/tickoni/schema/proto/classification/classification.proto",
    "src/tickoni/schema/proto/consumer_money/thesis.proto",
    "src/tickoni/schema/proto/consumer_money/basket.proto",
};

/// Create the fixture path verification step.
pub fn createVerifyFixtureStep(
    b: *std.Build,
    check_step: *std.Build.Step,
) void {
    const verify_fixture_step = b.step("verify-fixture-paths", "Verify all fixture paths exist");
    verify_fixture_step.dependOn(check_step);
    inline for (fixture_dirs) |path| {
        const exists = b.addSystemCommand(&.{ "test", "-e", path });
        exists.step.dependOn(check_step);
    }
}
