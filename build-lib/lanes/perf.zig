/// Performance test lane strategy.
///
/// Runs process-mode performance measurements: shared-core vs floating CPU
/// placement timing envelopes. Linux-only because CPU pinning semantics vary
/// across platforms and the test validates real kernel behavior.
///
/// These are performance guards, not correctness checks. They are intentionally
/// separated from the integration lane so CI noise does not block correctness
/// gates.

const std = @import("std");
const codec = @import("../lib/codec.zig");
const firedancer = @import("../lib/firedancer.zig");
const topo_run = @import("../lib/topo_run.zig");
const shims = @import("../lib/shims.zig");
const modules = @import("../mod/modules.zig");

/// Performance modules passed in from build.zig.
pub const PerfModules = struct {
    shared: modules.Shared,
    fd_lib_dir: []const u8,
};

/// Register all performance test binaries. Called from build.zig.
pub fn strategy(
    b: *std.Build,
    perf_mods: PerfModules,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    perf_step: *std.Build.Step,
) void {
    // Only build on Linux — CPU pinning semantics are platform-dependent.
    if (target.result.os.tag != .linux) return;

    const perf_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tickoni/test/perf/test_process_cpu_placement.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "runtime", .module = perf_mods.shared.runtime },
                .{ .name = "supervisor", .module = b.createModule(.{
                    .root_source_file = b.path("src/app/tickoni/supervisor.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "runtime", .module = perf_mods.shared.runtime },
                        .{ .name = "tiles", .module = perf_mods.shared.tiles },
                        .{ .name = "c_abi", .module = perf_mods.shared.c_abi },
                        .{ .name = "util", .module = perf_mods.shared.util },
                        .{ .name = "topologies", .module = perf_mods.shared.topologies },
                        .{ .name = "logger", .module = perf_mods.shared.logger },
                    },
                })},
                .{ .name = "util", .module = perf_mods.shared.util },
                .{ .name = "topologies", .module = perf_mods.shared.topologies },
            },
        }),
    });
    codec.linkTickoniCodec(b, perf_test, perf_mods.fd_lib_dir);
    firedancer.linkTickoniFiredancer(b, perf_test, perf_mods.fd_lib_dir);
    topo_run.linkTickoniTopoRun(b, perf_test, perf_mods.fd_lib_dir);

    // libfd_waltz.a contains fd_http_server.o which references ZSTD;
    // link libfd_zstd.a to resolve those symbols.
    perf_test.root_module.addObjectFile(.{ .cwd_relative = b.fmt("{s}/libfd_zstd.a", .{perf_mods.fd_lib_dir}) });

    const run_perf_test = shims.addPlainTestRun(b, perf_test);
    perf_step.dependOn(&run_perf_test.step);
}
