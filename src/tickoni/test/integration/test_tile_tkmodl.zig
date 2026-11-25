/// Process integration contracts for the tkmodl tile, with a real tkmodl child
/// on real shared-memory links. tkagnt is its requester:
///
///   harness -> tkings -> (spine) -> tkdisp -> tkagnt -> tkmodl -> tkaudt (audit)
///                                                      tkagnt -> tkdisp (result)
///
/// What is proved, from the committed state of each tile's own scratch:
///   * every request is processed once and gets exactly one tkmodl audit record
///     (a model call or a denial with its reason) and one terminal result, in
///     admission order, with tkmodl's counters equal to the committed records;
///   * an allowed request is answered from the instance's fixture table (replay
///     substitution) and a denied one carries no model output; the tile has no
///     provider path, so a live request is a denial;
///   * more requests than the link depth turn credits and dcache chunks over
///     with no loss or duplication, and the final request is published and
///     audited before the tile exits;
///   * an administrative HALT stops the tile cleanly;
///   * a bad configuration fails closed: an instance with no configuration is
///     refused before any child exists, and a live-provider configuration is
///     rejected by the child, which serves and audits nothing;
///   * the C-computed audit hash of every record tkmodl commits matches the Zig
///     codec.
///
/// Agent-side behavior (tiers, multipart model transport, timeouts, the full
/// workflow) is proved in test_tile_tkagnt.zig. The helpers here are local
/// because each integration file is its own test root.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");
const audit_zig = @import("audit");

const Supervisor = supervisor_mod.Supervisor;
const model_instances = supervisor_mod.model_instances;
const Tier = rt.model_tier.TkAgntModelTier;

const tiles = @import("tiles");
const mrs = tiles.model_request_source;
const Harness = @import("ingest_harness").Harness;

/// The one tkmodl instance every run here starts (`agentProcess(1)`).
const instance_kind_id: u8 = 0;
const instance_tier = Tier.low;
const shape = mrs.Shape{};

/// ModelDecision tags the request kinds produce under `mrs.fixtureConfig`.
const Decision = struct {
    const allow_replay: u8 = 1;
    const missing_scope: u8 = 2;
    const model_not_allowed: u8 = 3;
    const output_limit: u8 = 6;
    const live_provider_disabled: u8 = 8;
    const replay_substitution_missing: u8 = 9;
};

const record_policy_decision: u32 = 2;
const record_model_call: u32 = 3;
const record_proposal: u32 = 5;
const record_denial: u32 = 9;

const producer_tkmodl = "tkmodl";

const max_polls: u32 = 2000;
const poll_ns: u64 = 5 * std.time.ns_per_ms;

fn tileScratch(sup: *Supervisor, name: []const u8, kind_id: usize) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), kind_id);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

fn modelTileIndex(sup: *const Supervisor) usize {
    for (sup.topo.tiles, 0..) |t, i| {
        if (t.name.eql(rt.tile_ids.tkmodl)) return i;
    }
    unreachable; // Every topology in this file has one tkmodl.
}

/// The instance's configuration: governance limits, allowlist, fixture table,
/// and the captured response bytes the fixtures resolve to. The supervisor
/// copies it into the instance's file at start, but the slices must outlive
/// that call.
const Fixtures = struct {
    arena: std.heap.ArenaAllocator,
    config: model_instances.InstanceConfig,
    /// tkagnt's prompt table: the prompts the requests reference.
    prompts: []const []const u8,

    fn init(backing: std.mem.Allocator) !Fixtures {
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        const a = arena.allocator();
        const class = mrs.classOf(@backingInt(instance_tier));
        const scratch = try a.alloc(u8, mrs.scratchBytes(shape));
        const contents = try a.alloc(model_instances.FixtureContent, shape.fixtures);
        for (contents, 0..) |*c, i| {
            const buf = try a.alloc(u8, mrs.scratchBytes(shape));
            const n = mrs.fillResponse(buf, class, i, shape);
            c.* = .{ .key = mrs.fixtureKey(i), .bytes = buf[0..n] };
        }
        // Allocate before `arena` is copied into the result, or the copy misses these.
        const prompts = try mrs.prompts(shape, a);
        return .{
            .arena = arena,
            .config = .{
                .kind_id = instance_kind_id,
                .tier = instance_tier,
                .config = mrs.fixtureConfig(class, shape, scratch),
                .contents = contents,
            },
            .prompts = prompts,
        };
    }

    fn deinit(self: *Fixtures) void {
        self.arena.deinit();
    }
};

/// Every slot names the instance's tier, so the requester routes it to tkmodl.
fn sourceOf(pattern: []const mrs.RequestKind) mrs.ModelRequestSource {
    var source = mrs.ModelRequestSource{ .shape = shape, .pattern_len = @intCast(pattern.len) };
    for (pattern, 0..) |kind, i| {
        source.pattern[i] = kind;
        source.tiers[i] = @backingInt(instance_tier);
    }
    return source;
}

fn pipelineConfig(
    run_dir: []const u8,
    ws_buf: []u8,
    event_count: u64,
    configs: []const model_instances.InstanceConfig,
    prompts: []const []const u8,
) supervisor_mod.ProcessPipelineConfig {
    return .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = util.nextWorkspaceName(ws_buf),
        .metric_port = util.nextMetricPort(),
        .model_configs = configs,
        // tkdisp's payment template; every event here is an agent request.
        .dispatch_template = sourceOf(&.{.valid_replay}),
        .agent_prompts = prompts,
    };
}

const Run = struct {
    sup: Supervisor,
    tmp: @TypeOf(util.tmpDir()),
    fx: Fixtures,
    /// The external producer on tkings's input link.
    harness: Harness = .{},

    fn deinit(self: *Run) void {
        // The harness writes into the shared workspace: stop it first.
        self.harness.finish();
        self.sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
        self.sup.deinit();
        self.fx.deinit();
        self.tmp.cleanup();
    }
};

/// Starts a run that owns `fx`.
fn startRun(run: *Run, fx: Fixtures, event_count: u64, source: mrs.ModelRequestSource) !void {
    run.fx = fx;
    errdefer run.fx.deinit();
    run.harness = .{};
    run.tmp = util.tmpDir();
    errdefer run.tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try run.tmp.dir.realPath(std.testing.io, &path_buf)];

    run.sup = try Supervisor.initForTest(std.testing.allocator, topologies.agentProcess(1));
    errdefer run.sup.deinit();
    var ws_buf: [16]u8 = undefined;
    try run.sup.startPaymentPipelineProcess(
        std.testing.io,
        pipelineConfig(run_dir, &ws_buf, event_count, (&run.fx.config)[0..1], run.fx.prompts),
    );
    try run.harness.start(std.testing.allocator, &run.sup, .{ .agent_requests = source }, event_count);
}

/// Polls until every request has its terminal result at tkdisp, its agent
/// record committed at tkaudt, and has been processed by tkmodl. CNC counters
/// are advisory while a child is still writing, so completion is judged from
/// each tile's own committed scratch.
fn waitForRun(sup: *Supervisor, event_count: u64) void {
    const model = tileScratch(sup, "tkmodl", instance_kind_id) catch return;
    const audit = tileScratch(sup, "tkaudt", 0) catch return;
    const disp = tileScratch(sup, "tkdisp", 0) catch return;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (c_abi.tkdisp.resultCount(disp) >= event_count and
            c_abi.tkaudit.agentCommitted(audit) >= event_count and
            c_abi.tkmodl.ctxProcessed(model) >= event_count) return;
        util.process.sleepNanos(poll_ns);
    }
}

fn waitForState(sup: *Supervisor, idx: usize, want: rt.tile.TileState) void {
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.reapExitedChildrenNoHang();
        sup.refreshProcessHealth();
        if (sup.monitor()[idx].state == want) return;
        util.process.sleepNanos(poll_ns);
    }
}

fn expectNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |h| try std.testing.expect(h.state != .crashed);
}

fn expectedDecision(kind: mrs.RequestKind) u8 {
    return switch (kind) {
        .valid_replay => Decision.allow_replay,
        .missing_budget => Decision.missing_scope,
        .model_not_allowed => Decision.model_not_allowed,
        .unknown_substitution => Decision.replay_substitution_missing,
        .live_request => Decision.live_provider_disabled,
        .over_output_limit => Decision.output_limit,
        // Only an embedding tier serves vector widths; this file runs one
        // LLM-class instance.
        .bad_embedding_dimension => unreachable,
    };
}

/// Index of the next committed record at or after `from` that tkmodl produced.
fn nextTkmodlRecord(audit: ?*anyopaque, from: usize) !usize {
    const count = c_abi.tkaudit.recordCount(audit);
    var i = from;
    while (i < count) : (i += 1) {
        var producer: [producer_tkmodl.len]u8 = undefined;
        c_abi.tkaudit.recordDecidedBy(audit, i, &producer);
        if (std.mem.eql(u8, &producer, producer_tkmodl)) return i;
    }
    return error.TkmodlRecordMissing;
}

const Tally = struct { allowed: u64, denied: u64 };

/// Asserts, for every request, that tkmodl produced exactly one committed
/// record and the requester received exactly one correlated result, that
/// tkmodl's counters equal those records, and that the audit hash chain is
/// intact. Returns how many requests were allowed and denied.
fn expectRun(run: *Run, source: mrs.ModelRequestSource, event_count: u64) !Tally {
    const sup = &run.sup;
    const cfg = &run.fx.config.config;
    const model = try tileScratch(sup, "tkmodl", instance_kind_id);
    const audit = try tileScratch(sup, "tkaudt", 0);
    const disp = try tileScratch(sup, "tkdisp", 0);

    try std.testing.expectEqual(event_count, c_abi.tkmodl.ctxProcessed(model));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkmodl.ctxDropped(model));
    try std.testing.expectEqual(event_count, c_abi.tkdisp.resultCount(disp));

    var tally = Tally{ .allowed = 0, .denied = 0 };
    var cursor: usize = 0; // next committed record to look at
    var offset: u64 = 0;
    while (offset < event_count) : (offset += 1) {
        const seq = offset + 1;
        const kind = source.kindAt(offset);
        const decision = expectedDecision(kind);
        const entry = cfg.fixtures[@intCast(mrs.fixtureIndexAt(offset, shape))];

        // tkmodl's committed record for this request.
        const rec = try nextTkmodlRecord(audit, cursor);
        cursor = rec + 1;
        try std.testing.expectEqual(seq, c_abi.tkaudit.recordSourceOffset(audit, rec));
        try std.testing.expect(c_abi.tkaudit.recordCapabilityEnvelope(audit, rec) != 0);

        // The terminal result the requester received, in admission order.
        const r = c_abi.tkdisp.result(disp, @intCast(offset));
        try std.testing.expectEqual(seq, r.agent_seq);

        if (decision == Decision.allow_replay) {
            tally.allowed += 1;
            // Answered from the fixture table, and audited as a model call.
            try std.testing.expectEqual(@backingInt(c_abi.tkagnt.Outcome.ok), r.outcome);
            try std.testing.expectEqual(Decision.allow_replay, r.model_decision);
            try std.testing.expectEqual(entry.response_hash, r.response_hash);
            try std.testing.expectEqual(entry.prompt_hash, r.prompt_hash);
            try std.testing.expectEqualStrings(mrs.model_id, std.mem.sliceTo(&r.model_id, 0));

            try std.testing.expectEqual(record_model_call, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(entry.prompt_hash, c_abi.tkaudit.recordModelPromptHash(audit, rec));
            try std.testing.expectEqual(entry.response_hash, c_abi.tkaudit.recordModelResponseHash(audit, rec));
            try std.testing.expectEqual(entry.total_tokens, c_abi.tkaudit.recordModelTokenEstimate(audit, rec));
            try std.testing.expectEqual(entry.key, c_abi.tkaudit.recordModelReplaySubstitutionId(audit, rec));
            var model_id: [32]u8 = undefined;
            c_abi.tkaudit.recordModelId(audit, rec, &model_id);
            try std.testing.expectEqualStrings(mrs.model_id, std.mem.sliceTo(&model_id, 0));
        } else {
            tally.denied += 1;
            // A denial carries no model output and names its reason.
            try std.testing.expectEqual(@backingInt(c_abi.tkagnt.Outcome.model_denied), r.outcome);
            try std.testing.expectEqual(@as(u32, 0), r.response_len);
            try std.testing.expectEqual(@as(u64, 0), r.proposal_hash);

            try std.testing.expectEqual(record_denial, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(@as(u32, decision), c_abi.tkaudit.recordDenialReasonCode(audit, rec));
            if (kind == .missing_budget) {
                // A missing-scope denial names the missing field.
                var dim: [32]u8 = undefined;
                c_abi.tkaudit.recordDenialFailedScopeDim(audit, rec, &dim);
                try std.testing.expectEqualStrings("budget_id", std.mem.sliceTo(&dim, 0));
            }
        }
    }
    // tkmodl produced no record beyond one per request.
    try std.testing.expectError(error.TkmodlRecordMissing, nextTkmodlRecord(audit, cursor));

    // Counters equal the committed records.
    try std.testing.expectEqual(tally.allowed, c_abi.tkmodl.ctxAllowed(model));
    try std.testing.expectEqual(tally.denied, c_abi.tkmodl.ctxDenied(model));

    // The hash chain over everything committed is contiguous from the zero seed.
    const count = c_abi.tkaudit.recordCount(audit);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSeq(audit, i));
        try std.testing.expectEqual(
            if (i == 0) @as(u64, 0) else c_abi.tkaudit.recordHash(audit, i - 1),
            c_abi.tkaudit.recordPrevHash(audit, i),
        );
        try std.testing.expect(c_abi.tkaudit.recordHash(audit, i) != 0);
    }
    return tally;
}

test "tkmodl_tile: replay requests are answered from the fixture table and audited" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 8;
    const source = sourceOf(&.{.valid_replay});
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const tally = try expectRun(&run, source, event_count);
    try std.testing.expectEqual(event_count, tally.allowed);
    try std.testing.expectEqual(@as(u64, 0), tally.denied);
}

test "tkmodl_tile: every denial reason is audited, answered, and never produces model output" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const pattern = [_]mrs.RequestKind{
        .valid_replay,
        .missing_budget,
        .model_not_allowed,
        .unknown_substitution,
        .live_request,
        .over_output_limit,
    };
    const event_count: u64 = 12; // two full cycles
    const source = sourceOf(&pattern);
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const tally = try expectRun(&run, source, event_count);
    try std.testing.expectEqual(@as(u64, 2), tally.allowed);
    try std.testing.expectEqual(@as(u64, 10), tally.denied);
}

test "tkmodl_tile: more requests than link depth turn over credits with no loss or duplication" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // The links carry 32 fragments; 96 requests force every link's credits and
    // dcache chunks to turn over three times.
    const event_count: u64 = 96;
    const source = sourceOf(&.{.valid_replay});
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const tally = try expectRun(&run, source, event_count);
    try std.testing.expectEqual(event_count, tally.allowed);
}

test "tkmodl_tile: the final request is published and audited before the tile exits" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const event_count: u64 = 1;
    const source = sourceOf(&.{.valid_replay});
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);

    // tkmodl self-exits on its Nth committed request, without a HALT.
    const idx = modelTileIndex(&run.sup);
    waitForState(&run.sup, idx, .stopped);
    try std.testing.expectEqual(rt.tile.TileState.stopped, run.sup.monitor()[idx].state);
    _ = try expectRun(&run, source, event_count);
}

test "tkmodl_tile: an administrative HALT with zero event count stops every tile cleanly" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    // event_count = 0 disables the stem gates, so tkmodl waits for work until
    // the supervisor's CNC HALT; it must stop cleanly with nothing committed.
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), 0, sourceOf(&.{.valid_replay}));
    defer run.deinit();

    const idx = modelTileIndex(&run.sup);
    waitForState(&run.sup, idx, .running);
    try std.testing.expectEqual(rt.tile.TileState.running, run.sup.monitor()[idx].state);
    const model = try tileScratch(&run.sup, "tkmodl", instance_kind_id);
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkmodl.ctxProcessed(model));

    run.harness.finish();
    run.sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
    // stopProcess detaches the workspace, so scratch is not read past this
    // point; the committed count was asserted above, before the HALT.
    for (run.sup.monitor()) |h| try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
}

test "tkmodl_tile: an instance with no configuration refuses the run before any child exists" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    var tmp = util.tmpDir();
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try tmp.dir.realPath(std.testing.io, &path_buf)];

    var sup = try Supervisor.initForTest(std.testing.allocator, topologies.agentProcess(1));
    defer sup.deinit();
    var ws_buf: [16]u8 = undefined;
    try std.testing.expectError(
        error.ModelConfigMissing,
        sup.startPaymentPipelineProcess(
            std.testing.io,
            pipelineConfig(run_dir, &ws_buf, 4, &.{}, &.{}),
        ),
    );

    // Refused up front: no process state, no children, and no config file left
    // for a later run to pick up.
    try std.testing.expect(sup.getTopo() == null);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, "tkmodl.0.config", .{}));
}

test "tkmodl_tile: a live-provider configuration is rejected by the child and nothing is served" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const event_count: u64 = 4;
    var fx = try Fixtures.init(std.testing.allocator);
    fx.config.config.live_provider_enabled = 1;
    var run: Run = undefined;
    try startRun(&run, fx, event_count, sourceOf(&.{.valid_replay}));
    defer run.deinit();

    // The supervisor accepts the file (it does not judge the provider flag); the
    // child's own configure step rejects it, so tkmodl exits nonzero in setup.
    const idx = modelTileIndex(&run.sup);
    waitForState(&run.sup, idx, .crashed);
    try std.testing.expectEqual(rt.tile.TileState.crashed, run.sup.monitor()[idx].state);

    // tkmodl audited nothing, no agent run completed, and no terminal result
    // reached the dispatcher. (The first event's policy decision is the spine's,
    // committed before any agent run.)
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    try std.testing.expectError(error.TkmodlRecordMissing, nextTkmodlRecord(audit, 0));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.agentCommitted(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkdisp.resultCount(disp));
}

// ---------------------------------------------------------------------------
// C-vs-Zig audit hash parity for the records tkmodl commits.
//
// tkaudt hashes model_call and denial records in C (tk_audit_stem.c); the Zig
// codec (codec/audit/hash.zig) is the independent reference. Every committed
// record is copied out whole and re-hashed by the Zig implementation: the chain
// only means something if the two agree byte for byte.
// ---------------------------------------------------------------------------

fn zigHashOfCommittedRecord(ev: c_abi.tkaudit.CAuditEvent) !u64 {
    const payload: audit_zig.AuditEvent.Payload = switch (ev.record_type) {
        record_policy_decision => .{ .policy_decision = ev.unnamed_0.policy_decision },
        record_model_call => .{ .model_call = .{
            .model_id = ev.unnamed_0.model_call.model_id,
            .prompt_hash = ev.unnamed_0.model_call.prompt_hash,
            .response_hash = ev.unnamed_0.model_call.response_hash,
            .token_estimate = ev.unnamed_0.model_call.token_estimate,
            .retry_count = ev.unnamed_0.model_call.retry_count,
            .actor_role = ev.unnamed_0.model_call.actor_role,
            .workflow = ev.unnamed_0.model_call.workflow,
            .policy_decision_id = ev.unnamed_0.model_call.policy_decision_id,
            .replay_substitution_id = ev.unnamed_0.model_call.replay_substitution_id,
        } },
        record_proposal => .{ .proposal = .{
            .proposal_type = ev.unnamed_0.proposal.proposal_type,
            .proposal_hash = ev.unnamed_0.proposal.proposal_hash,
            .approval_state = ev.unnamed_0.proposal.approval_state,
        } },
        record_denial => .{ .denial = .{
            .action_class = ev.unnamed_0.denial.action_class,
            .reason_code = ev.unnamed_0.denial.reason_code,
            .failed_scope_dim = ev.unnamed_0.denial.failed_scope_dim,
            .catalog_schema_version = ev.unnamed_0.denial.catalog_schema_version,
            .taxonomy_id = ev.unnamed_0.denial.taxonomy_id,
            .taxonomy_version = ev.unnamed_0.denial.taxonomy_version,
            .classification_code = ev.unnamed_0.denial.classification_code,
        } },
        else => return error.UnexpectedRecordType,
    };
    return audit_zig.computeRecordHash(.{ .header = ev.header, .payload = payload });
}

test "tkmodl_tile: C audit hash for model_call and denial records matches the Zig codec" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;

    const pattern = [_]mrs.RequestKind{ .valid_replay, .missing_budget, .model_not_allowed, .live_request };
    const event_count: u64 = 8;
    var run: Run = undefined;
    try startRun(&run, try Fixtures.init(std.testing.allocator), event_count, sourceOf(&pattern));
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    const count = c_abi.tkaudit.recordCount(audit);
    var saw_model_call = false;
    var saw_denial = false;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var ev: c_abi.tkaudit.CAuditEvent = undefined;
        c_abi.tkaudit.recordCopy(audit, i, &ev);
        try std.testing.expectEqual(c_abi.tkaudit.recordHash(audit, i), try zigHashOfCommittedRecord(ev));
        if (ev.record_type == record_model_call) saw_model_call = true;
        if (ev.record_type == record_denial) saw_denial = true;
    }
    // The comparison covered both record types tkmodl commits, not just one.
    try std.testing.expect(saw_model_call);
    try std.testing.expect(saw_denial);
}
