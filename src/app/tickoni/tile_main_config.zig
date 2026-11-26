/// Fail-closed config handoff for stem tiles.
///
/// The supervisor writes `payment_pipeline.config` (tkpoly's signed policy
/// limit) and `tkmodl.config` (tkmodl's limits, allowlist and fixture table)
/// beside each child's topology.spec. tile_main.zig's `stemRun` calls these
/// loaders before the C harness starts, because neither privileged_init nor a
/// fragment callback may read a file. A missing, malformed, mismatched or
/// live-enabled file installs nothing and the child exits nonzero.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const tiles = @import("tiles");
const model_instances = @import("model_instances.zig");
const agent_prompts = @import("agent_prompts.zig");

/// Reads the supervisor-written payment_pipeline.config beside this child's
/// topology.spec and pushes its signed `policy_limit_cents` into
/// tk_policy_stem.c through the C setter.
///
/// Requires the file and requires its pipeline event count to agree with the
/// TopologySpec the same child rebuilt its topology from: a disagreement means
/// the two halves of the handoff describe different runs, and the policy gate
/// and the pipeline's event budget would diverge. There is no default-limit
/// fallback — a financial limit this child could not read is a startup
/// failure, not a value to guess.
///
/// `dir` defaults to std.Io.Dir.cwd() — tests can pass a temp-dir handle
/// instead, since the unit-test std library is minimal and lacks cwd().
pub fn loadPolicyLimit(
    io: std.Io,
    spec: *const rt.launch_spec.LaunchSpec,
    topology_event_count: u64,
    dir: ?std.Io.Dir,
) !void {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = if (spec.shmemPath().len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()})
    else
        try std.fmt.bufPrint(&path_buf, "payment_pipeline.config", .{});
    // readProcessConfig owns the size/magic/version checks; this entrypoint
    // does not re-decode the file.
    const cfg = try tiles.process.readProcessConfig(io, dir orelse std.Io.Dir.cwd(), path);
    if (cfg.pipeline.event_count != topology_event_count) {
        return error.PolicyConfigEventCountMismatch;
    }
    c_abi.tkpoly.setPolicyLimitCents(cfg.pipeline.policy_limit_cents);
    std.debug.print(
        "[tile-main] stemRun: tkpoly policy_limit_cents={d} event_count={d}\n",
        .{ cfg.pipeline.policy_limit_cents, cfg.pipeline.event_count },
    );
}

/// Reads this child's own `tkmodl.<kind_id>.config` beside its topology.spec,
/// checks that it is bound to the `(tkmodl, kind_id)` this process was launched
/// as and to this run's configured instance count, and installs it in the C
/// tile. Returns the semantic tier the supervisor assigned to this instance.
/// `dir` defaults to cwd (tests pass a temp dir).
///
/// Fail closed: a missing, short, long, swapped, stale, mis-versioned or
/// live-enabled file installs nothing.
pub fn loadModelConfig(
    io: std.Io,
    spec: *const rt.launch_spec.LaunchSpec,
    instance_cnt: usize,
    dir: ?std.Io.Dir,
    allocator: std.mem.Allocator,
) !rt.model_tier.TkAgntModelTier {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = try model_instances.path(&path_buf, spec.shmemPath(), spec.tile_kind_id);
    var inst = try model_instances.read(io, dir orelse std.Io.Dir.cwd(), path, spec.tile_kind_id, instance_cnt, allocator);
    defer inst.deinit(allocator);
    try c_abi.tkmodl.configure(&inst.config);
    // The captured responses are checked against each fixture's response_hash
    // as they are installed; a capture that does not match installs nothing and
    // the child exits before it can serve a request.
    for (inst.contents) |content| try c_abi.tkmodl.setFixtureContent(content.key, content.bytes);
    std.debug.print(
        "[tile-main] stemRun: tkmodl#{d} tier={s} config loaded from {s} ({d} captures)\n",
        .{ spec.tile_kind_id, inst.tier.name(), path, inst.contents.len },
    );
    return inst.tier;
}

/// Prepares this tkrepl child before the C harness runs: registers the
/// Zig-owned replay verdict (tiles/replay/decision.zig). The tile never decides
/// a divergence itself and refuses to replay a capsule without it.
pub fn loadReplaySetup() !void {
    try c_abi.tkrepl.setHooks(&tiles.replay_decision.hooks);
}

/// Prepares this tkagnt child before the C harness runs: registers the Zig-owned
/// decision hooks, installs the run's prompt table from `tkagnt.prompts`, and
/// declares which tkmodl instance serves which tier by reading each instance's
/// identity-bound config header. The tile binds its request and result links
/// from these declarations and the verified channel endpoints, and refuses to
/// start without hooks.
///
/// Fail closed: a missing or malformed prompt file, a prompt that does not
/// hash to its reference, an instance whose file is missing, swapped or stale,
/// a tier declared twice, or an unconfigured topology installs a partial table
/// no further; the child exits nonzero.
pub fn loadAgentSetup(
    io: std.Io,
    topo: rt.topology.Topology,
    shmem_path: []const u8,
    dir: ?std.Io.Dir,
    allocator: std.mem.Allocator,
) !void {
    try c_abi.tkagnt.setHooks(&tiles.agent_decision.hooks);
    var prompts_path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const prompts_path = try agent_prompts.path(&prompts_path_buf, shmem_path);
    const installed = try agent_prompts.install(io, dir orelse std.Io.Dir.cwd(), prompts_path, allocator);
    std.debug.print("[tile-main] stemRun: tkagnt prompt table: {d} prompt(s)\n", .{installed});
    const instance_cnt = model_instances.instanceCount(topo);
    if (instance_cnt == 0) return error.AgentWithoutModels;
    for (topo.tiles) |t| {
        if (!t.name.eql(rt.tile_ids.tkmodl)) continue;
        var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
        const path = try model_instances.path(&path_buf, shmem_path, t.kind_id);
        const tier = try model_instances.readTier(io, dir orelse std.Io.Dir.cwd(), path, t.kind_id, instance_cnt);
        try c_abi.tkagnt.setRoute(@backingInt(tier), t.kind_id);
        std.debug.print("[tile-main] stemRun: tkagnt route tier={s} -> tkmodl#{d}\n", .{ tier.name(), t.kind_id });
    }
}

/// Reads the dispatch template from the supervisor-written
/// payment_pipeline.config and installs it in tkdisp: the request tkdisp sends
/// for every payment event it receives (decision O2). Tier, scope and prompt
/// reference come from the run configuration; the event contributes only its
/// offset and trace id.
///
/// Fail closed: a missing file, a config without a template, a production build
/// (the synthetic source is the only template author today) or a template the C
/// tile refuses installs nothing and the child exits nonzero.
pub fn loadDispatchTemplate(
    io: std.Io,
    spec: *const rt.launch_spec.LaunchSpec,
    dir: ?std.Io.Dir,
    allocator: std.mem.Allocator,
) !void {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = if (spec.shmemPath().len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()})
    else
        try std.fmt.bufPrint(&path_buf, "payment_pipeline.config", .{});
    const cfg = try tiles.process.readProcessConfig(io, dir orelse std.Io.Dir.cwd(), path);
    if (!rt.test_build.enabled) return error.DispatchTemplateRequiresTestBuild;
    const source = cfg.pipeline.dispatch_template orelse return error.MissingDispatchTemplate;

    const src = tiles.model_request_source;
    const scratch = try allocator.alloc(u8, source.shape.prompt_bytes);
    defer allocator.free(scratch);
    const request = src.buildAgentRequest(source, 0, scratch);
    try c_abi.tkdisp.setTemplate(&request);
    std.debug.print(
        "[tile-main] stemRun: tkdisp dispatch template tier={d} prompt_bytes={d}\n",
        .{ source.tierAt(0), source.shape.prompt_bytes },
    );
}

// ---------------------------------------------------------------------------
// P4.3 — Fail closed on invalid configuration handoff.
// ---------------------------------------------------------------------------
//
// These tests use a simple string path (no temp-dir realpath) because the
// unit-test std library is minimal: no fs.cwd / realPath.  The shmem_path
// is only used for string concatenation in loadPolicyLimit, not for real
// filesystem access — the test writes the config file via tmp.dir which
// uses std.testing.tmpDir.

test "tile_main_config: loadPolicyLimit fails on missing config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // loadPolicyLimit must fail — no config file exists at shmem_path.
    try std.testing.expectError(error.FileNotFound, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on truncated config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // Write a truncated config (only 4 bytes of a ~56-byte struct).
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 0x54, 0x4b, 0x50, 0x43 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.ProcessConfigTruncated, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on bad magic in config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file_struct = tiles.process.ProcessConfigFile{};
    file_struct.magic_field = 0xdeadbeef;
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    try std.testing.expectError(error.ProcessConfigBadMagic, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on unsupported version in config file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file_struct = tiles.process.ProcessConfigFile{};
    file_struct.version_field = 0;
    var file = try tmp.dir.createFile(std.testing.io, "payment_pipeline.config", .{});
    try file.writePositionalAll(std.testing.io, std.mem.asBytes(&file_struct), 0);
    file.close(std.testing.io);

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    try std.testing.expectError(error.ProcessConfigUnsupportedVersion, loadPolicyLimit(
        std.testing.io,
        &spec,
        4,
        tmp.dir,
    ));
}

test "tile_main_config: loadPolicyLimit fails on mismatched event count" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });

    // Config says 4 events — mismatched with topology's 100.
    const cfg = tiles.process.ProcessRuntimeConfig{
        .pipeline = .{ .event_count = 4, .policy_limit_cents = 1_000 },
    };
    try tiles.process.writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    try std.testing.expectError(error.PolicyConfigEventCountMismatch, loadPolicyLimit(
        std.testing.io,
        &spec,
        100, // topology says 100 events, config says 4
        tmp.dir,
    ));
}

// ---------------------------------------------------------------------------
// tkmodl per-instance config handoff — fail closed (same contract as the
// policy limit): a missing, short, long, swapped, stale, mis-magic'd,
// mis-versioned, or live-enabled file installs nothing and the child exits
// nonzero before the C harness runs. The file format and its identity checks
// are covered in model_instances.zig; these tests cover the loader that
// installs the config into the C tile.
// ---------------------------------------------------------------------------

fn modelSpec(kind_id: u8) !rt.launch_spec.LaunchSpec {
    return rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = kind_id,
        .tile_id = rt.tile_ids.tkmodl,
        .tile_kind_id = kind_id,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });
}

fn validModelConfig() c_abi.tkmodl.TkModlRuntimeConfig {
    var cfg = std.mem.zeroes(c_abi.tkmodl.TkModlRuntimeConfig);
    cfg.magic = c_abi.tkmodl.config_magic;
    cfg.version = c_abi.tkmodl.config_version;
    return cfg;
}

fn writeInstanceFile(tmp: anytype, kind_id: u8, tier: rt.model_tier.TkAgntModelTier, cfg: c_abi.tkmodl.TkModlRuntimeConfig, instance_cnt: u8) !void {
    const bytes = model_instances.encode(.{ .kind_id = kind_id, .tier = tier, .config = cfg }, instance_cnt);
    var name_buf: [64]u8 = undefined;
    var file = try tmp.dir.createFile(std.testing.io, try model_instances.path(&name_buf, "", kind_id), .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &bytes, 0);
}

test "tile_main_config: loadModelConfig installs this instance's config and returns its tier" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec(1);
    try writeInstanceFile(&tmp, 0, .classifier_fast, validModelConfig(), 2);
    try writeInstanceFile(&tmp, 1, .embedding, validModelConfig(), 2);
    const tier = try loadModelConfig(std.testing.io, &spec, 2, tmp.dir, std.testing.allocator);
    try std.testing.expectEqual(rt.model_tier.TkAgntModelTier.embedding, tier);
}

test "tile_main_config: loadModelConfig fails on a missing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec(0);
    try std.testing.expectError(error.FileNotFound, loadModelConfig(std.testing.io, &spec, 1, tmp.dir, std.testing.allocator));
}

test "tile_main_config: loadModelConfig reads only its own instance's file" {
    // Instance 1's file is present; instance 0 must not fall back to it.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try writeInstanceFile(&tmp, 1, .embedding, validModelConfig(), 2);
    const spec = try modelSpec(0);
    try std.testing.expectError(error.FileNotFound, loadModelConfig(std.testing.io, &spec, 2, tmp.dir, std.testing.allocator));
}

test "tile_main_config: loadModelConfig fails on a swapped or stale file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try modelSpec(0);

    // Bytes written for instance 1 saved under instance 0's name.
    const swapped = model_instances.encode(.{ .kind_id = 1, .tier = .embedding, .config = validModelConfig() }, 2);
    var file = try tmp.dir.createFile(std.testing.io, "tkmodl.0.config", .{});
    try file.writePositionalAll(std.testing.io, &swapped, 0);
    file.close(std.testing.io);
    try std.testing.expectError(error.ConfigKindIdMismatch, loadModelConfig(std.testing.io, &spec, 2, tmp.dir, std.testing.allocator));

    // Right instance, written for a run with three instances.
    try writeInstanceFile(&tmp, 0, .classifier_fast, validModelConfig(), 3);
    try std.testing.expectError(error.ConfigInstanceCountMismatch, loadModelConfig(std.testing.io, &spec, 2, tmp.dir, std.testing.allocator));
}

test "tile_main_config: loadModelConfig fails on bad magic, bad version, and a live provider" {
    const spec = try modelSpec(0);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var cfg = validModelConfig();
    cfg.magic = 0xdeadbeef;
    try writeInstanceFile(&tmp, 0, .low, cfg, 1);
    try std.testing.expectError(error.BadMagic, loadModelConfig(std.testing.io, &spec, 1, tmp.dir, std.testing.allocator));

    cfg = validModelConfig();
    cfg.version = c_abi.tkmodl.config_version + 1;
    try writeInstanceFile(&tmp, 0, .low, cfg, 1);
    try std.testing.expectError(error.BadVersion, loadModelConfig(std.testing.io, &spec, 1, tmp.dir, std.testing.allocator));

    cfg = validModelConfig();
    cfg.live_provider_enabled = 1;
    try writeInstanceFile(&tmp, 0, .low, cfg, 1);
    try std.testing.expectError(error.LiveProviderEnabled, loadModelConfig(std.testing.io, &spec, 1, tmp.dir, std.testing.allocator));
}

test {
    _ = model_instances;
    _ = agent_prompts;
}
