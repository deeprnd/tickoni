/// Process integration contracts for the tkmodl child's configuration handoff.
///
/// Each tkmodl instance reads its governance limits, allowlist and fixture table
/// from its own `tkmodl.<kind_id>.config`, written by the supervisor. Both ways
/// that handoff can be wrong must fail closed, with no model output:
///   * an instance with no configuration is refused before any child exists;
///   * a configuration enabling a live provider is rejected by the child, and
///     nothing is audited or answered.
///
/// Request-to-result-to-audit behavior of tkmodl, including denial reasons and
/// C-vs-Zig audit hash parity, is proved through the agent path in
/// test_tile_tkagnt.zig; the single minimal topology smoke test lives in
/// test_minimal_setup.zig.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;
const model_instances = supervisor_mod.model_instances;
const Tier = rt.model_tier.TkAgntModelTier;

const tiles = @import("tiles");
const mrs = tiles.model_request_source;

const max_polls: u32 = 600;
const poll_ns: u64 = 5 * std.time.ns_per_ms;

const shape = mrs.Shape{};
const instance_tier = Tier.low;
const instance_kind_id: u8 = 0;
const config_file_name = "tkmodl.0.config";

fn tileScratch(sup: *Supervisor, name: []const u8) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), 0);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

/// The one valid instance configuration both tests start from.
fn validInstanceConfig() model_instances.InstanceConfig {
    var scratch: [mrs.scratchBytes(shape)]u8 = undefined;
    return .{
        .kind_id = instance_kind_id,
        .tier = instance_tier,
        .config = mrs.fixtureConfig(mrs.classOf(@backingInt(instance_tier)), shape, &scratch),
    };
}

fn requestSource() mrs.ModelRequestSource {
    var source = mrs.ModelRequestSource{ .shape = shape };
    source.pattern[0] = .valid_replay;
    source.tiers[0] = @backingInt(instance_tier);
    return source;
}

fn pipelineConfig(run_dir: []const u8, event_count: u64, ws_buf: []u8, configs: []const model_instances.InstanceConfig) supervisor_mod.ProcessPipelineConfig {
    return .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(ws_buf),
        .metric_port = util.nextMetricPort(),
        .model_requests = requestSource(),
        .model_configs = configs,
    };
}

test "tkmodl_tile: an instance with no configuration refuses the run before any child exists" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.agentProcess(1));
    defer sup.deinit();
    var ws_buf: [16]u8 = undefined;
    try std.testing.expectError(
        error.ModelConfigMissing,
        sup.startPaymentPipelineProcess(std.testing.io, pipelineConfig(run_dir, 4, &ws_buf, &.{})),
    );

    // Refused up front: no process state, no children, and no config file left
    // for a later run to pick up.
    try std.testing.expect(sup.getTopo() == null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, config_file_name, .{}));
}

test "tkmodl_tile: a live-provider configuration is rejected by the child and nothing is served" {
    const event_count: u64 = 4;
    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var instance = validInstanceConfig();
    instance.config.live_provider_enabled = 1;
    const configs = [_]model_instances.InstanceConfig{instance};

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.agentProcess(1));
    defer {
        sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
        sup.deinit();
    }
    var ws_buf: [16]u8 = undefined;
    try sup.startPaymentPipelineProcess(std.testing.io, pipelineConfig(run_dir, event_count, &ws_buf, &configs));

    // The supervisor accepts the file (it does not judge the provider flag); the
    // child's own configure step rejects it, so tkmodl exits nonzero in setup.
    const model_idx = blk: {
        for (sup.topo.tiles, 0..) |t, i| if (t.name.eql(rt.tile_ids.tkmodl)) break :blk i;
        unreachable;
    };
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.reapExitedChildrenNoHang();
        if (sup.monitor()[model_idx].state != .running) break;
        util.process.sleepNanos(poll_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.crashed, sup.monitor()[model_idx].state);

    // Nothing was audited and no terminal result reached the dispatcher.
    const audit = try tileScratch(&sup, "tkaudt");
    const disp = try tileScratch(&sup, "tkdisp");
    try std.testing.expectEqual(@as(usize, 0), c_abi.tkaudit.recordCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkdisp.resultCount(disp));
}
