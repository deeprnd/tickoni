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

var ingest_config: tiles.PaymentPipelineConfig = .{};

/// The test-only request source's message buffer, handed to the C tile by
/// pointer: sized for the largest logical message in test builds and empty
/// otherwise, so a production binary carries no such buffer.
var request_buf: [if (rt.test_build.enabled) c_abi.multipart.max_message_bytes else 0]u8 = @splat(0);

fn generatePayment(offset: u64, out: *c_abi.tkings.PaymentMessage) callconv(.c) void {
    const raw = tiles.syntheticPayment(ingest_config, offset);
    out.* = .{
        .raw = .{
            .source_offset = raw.source_offset,
            .idempotency_key = raw.idempotency_key,
            .amount_cents = raw.amount_cents,
            .account_id = raw.account_id,
            .currency = raw.currency,
            .malformed = @intFromBool(raw.malformed),
        },
        .event_hash = 0,
        .pipeline_hops = 1,
        .duplicate = 0,
        .decision = 0,
        .decided_by = .{ 0, 0, 0, 0, 0, 0 },
    };
}

fn buildRequest(offset: u64, msg: *[*]const u8, run_id: *u64) callconv(.c) usize {
    const source = ingest_config.model_requests orelse return 0;
    const body = tiles.model_request_source.buildAgentRequest(source, offset, &request_buf);
    msg.* = body.ptr;
    run_id.* = tiles.model_request_source.runIdAt(offset);
    return body.len;
}

/// The deliberately faulty producer: at the configured offset, withholds or
/// corrupts one fragment of the request stream so the receiver's fail-closed
/// handling is exercised by a real faulty sender.
fn injectFault(offset: u64, frag_idx: u32, frag_cnt: u32, frag: [*]u8, sz: usize) callconv(.c) c_int {
    const source = ingest_config.model_requests orelse return 0;
    if (offset != source.fault_offset) return 0;
    switch (source.fault) {
        .none => {},
        .drop_middle => if (frag_idx == 1) return 1,
        .omit_last => if (frag_idx == frag_cnt - 1) return 1,
        .corrupt_payload => if (frag_idx == 1 and sz > c_abi.multipart.header_size + 1) {
            frag[c_abi.multipart.header_size + 1] ^= 0x5a;
        },
    }
    return 0;
}

/// Installs the already validated, Zig-owned source in the tkings child before
/// Firedancer calls its privileged init callback: the synthetic payment
/// generator, or, in test builds only, the agent-request source.
pub fn loadIngestConfig(io: std.Io, spec: *const rt.launch_spec.LaunchSpec, topology_event_count: u64, dir: ?std.Io.Dir) !void {
    var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
    const path = if (spec.shmemPath().len > 0)
        try std.fmt.bufPrint(&path_buf, "{s}/payment_pipeline.config", .{spec.shmemPath()})
    else
        try std.fmt.bufPrint(&path_buf, "payment_pipeline.config", .{});
    const cfg = try tiles.process.readProcessConfig(io, dir orelse std.Io.Dir.cwd(), path);
    if (cfg.pipeline.event_count != topology_event_count) return error.IngestConfigEventCountMismatch;
    if (cfg.pipeline.model_requests != null and !rt.test_build.enabled) return error.ModelRequestSourceRequiresTestBuild;
    if (rt.test_build.enabled) {
        if (cfg.stuck_tile) |hook| {
            if (hook.tile_idx == spec.tile_idx) c_abi.tkings.setStuckHook(hook.after_messages, hook.sleep_ns);
        }
    }
    ingest_config = cfg.pipeline;
    if (cfg.pipeline.model_requests) |source| {
        c_abi.tkings.setRequestSource(buildRequest, if (source.fault == .none) null else injectFault);
    } else {
        c_abi.tkings.setPaymentGenerator(generatePayment);
    }
}

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

/// Prepares this tkagnt child before the C harness runs: registers the Zig-owned
/// decision hooks, and declares which tkmodl instance serves which tier by
/// reading each instance's identity-bound config header. The tile binds its
/// request and result links from these declarations and the verified channel
/// endpoints, and refuses to start without hooks.
///
/// Fail closed: an instance whose file is missing, swapped or stale, a tier
/// declared twice, or an unconfigured topology installs a partial route table
/// no further; the child exits nonzero.
pub fn loadAgentSetup(
    io: std.Io,
    topo: rt.topology.Topology,
    shmem_path: []const u8,
    dir: ?std.Io.Dir,
) !void {
    try c_abi.tkagnt.setHooks(&tiles.agent_decision.hooks);
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
/// payment_pipeline.config and installs it in a scheduler-shaped tkdisp: the
/// request that tkdisp sends for every event it receives. Tier, scope and prompt
/// come from the run configuration; the event contributes only its offset.
///
/// Fail closed: a missing file, a config without a template, a production build
/// (the synthetic source is the only template author today) or a template the C
/// tile refuses installs nothing and the child exits nonzero. Only a tkdisp with
/// an output link (the scheduler shape) needs one; the caller checks.
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
    const buf = try allocator.alloc(u8, c_abi.multipart.max_message_bytes);
    defer allocator.free(buf);
    const body = src.buildAgentRequest(source, 0, buf);
    try c_abi.tkdisp.setTemplateBody(body);
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
// tkings source handoff — the payment generator or, in test builds, the
// agent-request source. The C tile only calls these Zig functions; what they
// build and what they withhold is decided and checked here.
// ---------------------------------------------------------------------------

fn ingestSpec() !rt.launch_spec.LaunchSpec {
    return rt.launch_spec.LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = rt.tile_ids.tkings,
        .cpu_placement = .floating,
        .workspace_name = try rt.link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "",
        .heartbeat_interval_ns = 1,
    });
}

test "tile_main_config: loadIngestConfig fails on mismatched event count" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try ingestSpec();
    const cfg = tiles.process.ProcessRuntimeConfig{ .pipeline = .{ .event_count = 4 } };
    try tiles.process.writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    try std.testing.expectError(error.IngestConfigEventCountMismatch, loadIngestConfig(std.testing.io, &spec, 100, tmp.dir));
}

test "tile_main_config: loadIngestConfig accepts the request source in a test build" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const spec = try ingestSpec();
    const cfg = tiles.process.ProcessRuntimeConfig{
        .pipeline = .{ .event_count = 4, .model_requests = .{ .fault = .omit_last, .fault_offset = 2 } },
    };
    try tiles.process.writeProcessConfig(cfg, std.testing.io, tmp.dir, "payment_pipeline.config");

    try loadIngestConfig(std.testing.io, &spec, 4, tmp.dir);
    try std.testing.expect(ingest_config.model_requests != null);
}

test "tile_main_config: the request source builds exactly the source's requests" {
    const mrs = tiles.model_request_source;
    var source = mrs.ModelRequestSource{ .pattern_len = 2 };
    source.pattern[1] = .missing_budget;
    const saved = ingest_config;
    defer ingest_config = saved;
    ingest_config = .{ .model_requests = source };

    var want_buf: [1024]u8 = undefined;
    for ([_]u64{ 0, 1, 2, 7 }) |offset| {
        var msg: [*]const u8 = undefined;
        var run_id: u64 = 0;
        const len = buildRequest(offset, &msg, &run_id);
        try std.testing.expectEqualSlices(u8, mrs.buildAgentRequest(source, offset, &want_buf), msg[0..len]);
        try std.testing.expectEqual(mrs.runIdAt(offset), run_id);
    }
}

test "tile_main_config: injectFault touches only the configured offset and fragment" {
    const header = c_abi.multipart.header_size;
    const saved = ingest_config;
    defer ingest_config = saved;
    var frag: [128]u8 = @splat(0);

    // No fault: every fragment goes out untouched.
    ingest_config = .{ .model_requests = .{} };
    try std.testing.expectEqual(@as(c_int, 0), injectFault(0, 1, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(u8, 0), frag[header + 1]);

    // drop_middle withholds fragment 1 of the faulty offset, nothing else.
    ingest_config = .{ .model_requests = .{ .fault = .drop_middle, .fault_offset = 3 } };
    try std.testing.expectEqual(@as(c_int, 0), injectFault(2, 1, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(c_int, 0), injectFault(3, 0, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(c_int, 1), injectFault(3, 1, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(c_int, 0), injectFault(3, 3, 4, &frag, frag.len));

    // omit_last withholds only the final fragment.
    ingest_config = .{ .model_requests = .{ .fault = .omit_last, .fault_offset = 3 } };
    try std.testing.expectEqual(@as(c_int, 0), injectFault(3, 2, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(c_int, 1), injectFault(3, 3, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(c_int, 0), injectFault(4, 3, 4, &frag, frag.len));

    // corrupt_payload sends fragment 1 with one payload byte flipped.
    ingest_config = .{ .model_requests = .{ .fault = .corrupt_payload, .fault_offset = 3 } };
    try std.testing.expectEqual(@as(c_int, 0), injectFault(3, 0, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(u8, 0), frag[header + 1]);
    try std.testing.expectEqual(@as(c_int, 0), injectFault(2, 1, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(u8, 0), frag[header + 1]);
    try std.testing.expectEqual(@as(c_int, 0), injectFault(3, 1, 4, &frag, frag.len));
    try std.testing.expectEqual(@as(u8, 0x5a), frag[header + 1]);
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
}
