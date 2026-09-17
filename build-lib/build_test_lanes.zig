/// Test-lane coordinator: wires unit, integration, system, and cov lanes
/// into build.zig so the coordinator stays under 60 lines.
///
/// This is a thin bridge — all logic lives in build-lib/lanes/*.

const std = @import("std");
const lane = @import("lane.zig");
const build_lane = @import("lanes/unit.zig");
const integration_lane = @import("lanes/integration.zig");
const system_lane = @import("lanes/system.zig");
const cov_lane = @import("lanes/cov.zig");

const Shared = @import("mod/modules.zig").Shared;
const Tm = @import("mod/test_modules.zig").TestModules;

/// Register unit and integration lanes (behind -Dtest).
pub fn registerTestLanes(
    b: *std.Build,
    check_step: *std.Build.Step,
    shared: Shared,
    tm: Tm,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
    exe: *std.Build.Step.Compile,
) void {
    const run_tests_cmd = lane.createRunTestsCmd(b);

    // Unit tests
    const test_step = b.step("test", "Compile offline Tickoni unit test binaries");
    const run_tests_step = b.step("run-tests", "Run offline Tickoni unit tests");
    run_tests_step.dependOn(check_step);
    build_lane.strategy(b, shared, tm, target, optimize, fd_lib_dir, test_step, run_tests_cmd);

    // Integration modules
    const int_mods = integration_lane.createIntModules(b, shared, tm, target, optimize, exe);

    const integration_step = b.step("integration-test", "Run Tickoni mock-backed integration tests");
    integration_lane.strategy(b, int_mods, target, optimize, fd_lib_dir, integration_step);

    const system_step = b.step("system-test", "Run all src/tickoni/test/system proofs");
    system_lane.strategy(b, .{
        .investment_demo_mod = int_mods.investment_demo_mod,
        .investment_support_int_mod = int_mods.investment_support_int_mod,
        .fd_lib_dir = fd_lib_dir,
    }, target, optimize, system_step);

    const live_model_step = b.step("integration-test-live-model", "Alias for the live V1.1 system/demo lane");
    live_model_step.dependOn(system_step);
}

/// Register the coverage lane (always available).
pub fn registerCovLane(
    b: *std.Build,
    cov_step: *std.Build.Step,
    shared: Shared,
    tm: Tm,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    fd_lib_dir: []const u8,
) void {
    cov_lane.strategy(b, cov_step, .{
        .audit_codec = shared.audit_codec,
        .audit_schema = shared.audit_schema,
        .runtime = shared.runtime,
        .tiles = shared.tiles,
        .c_abi = shared.c_abi,
        .util = shared.util,
        .logger = shared.logger,
        .classification = shared.classification,
        .fixture_paths = shared.fixture_paths,
        .thesis = shared.thesis,
        .catalog_schema = shared.catalog_schema,
        .catalog = shared.catalog,
        .basket = shared.basket,
        .portfolio = shared.portfolio,
        .topologies = shared.topologies,
    }, .{
        .fixture_audit_gen = tm.fixture_audit_gen,
        .audit_tile = tm.audit_tile,
        .fixture_portfolio = tm.fixture_portfolio,
    }, target, optimize, fd_lib_dir);
}
