/// Process integration contracts for tkmodl's fd_stem lifecycle, replay
/// fixtures, denials, audit correlation, and C-vs-Zig audit hash parity.
/// The single minimal topology smoke test lives in test_minimal_setup.zig.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");

const Supervisor = supervisor_mod.Supervisor;

const tiles = @import("tiles");
const mrs = tiles.model_request_source;
const ModelDecisionTag = struct {
    const allow_replay: u32 = 1;
    const missing_scope: u32 = 2;
    const model_not_allowed: u32 = 3;
    const output_limit: u32 = 6;
    const live_provider_disabled: u32 = 8;
    const replay_substitution_missing: u32 = 9;
};
const record_model_call: u32 = 3;
const record_denial: u32 = 9;

const model_max_polls: u32 = 600;
const model_poll_ns: u64 = 5 * std.time.ns_per_ms;

fn tileScratch(sup: *Supervisor, name: []const u8) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), 0);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

/// Polls until every consumer has COMMITTED `event_count` records. CNC counters
/// are advisory hints while a child is still writing, so completion is judged
/// from the committed counts in each tile's own scratch: the result sink, the
/// audit sink, and the gateway.
fn waitForModelRun(sup: *Supervisor, event_count: u64) void {
    const agent = tileScratch(sup, "tkagnt") catch return;
    const audit = tileScratch(sup, "tkaudt") catch return;
    const model = tileScratch(sup, "tkmodl") catch return;
    var poll: u32 = 0;
    while (poll < model_max_polls) : (poll += 1) {
        if (c_abi.tkagnt.resultCount(agent) >= event_count and
            c_abi.tkaudit.recordCount(audit) >= event_count and
            c_abi.tkmodl.ctxProcessed(model) >= event_count) return;
        util.process.sleepNanos(model_poll_ns);
    }
}

const ModelRun = struct {
    sup: Supervisor,
    tmp: @TypeOf(util.tmpDir()),

    fn deinit(self: *ModelRun) void {
        self.sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
        self.sup.deinit();
        self.tmp.cleanup();
    }
};

fn startModelRun(
    run: *ModelRun,
    event_count: u64,
    pattern: []const mrs.RequestKind,
    model_config: ?c_abi.tkmodl.TkModlRuntimeConfig,
) !void {
    run.tmp = util.tmpDir();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try run.tmp.dir.realPath(std.testing.io, &path_buf)];

    var source = mrs.ModelRequestSource{ .pattern_len = @intCast(pattern.len) };
    for (pattern, 0..) |kind, i| source.pattern[i] = kind;

    run.sup = try Supervisor.initForTest(std.testing.allocator, topologies.minimalWithModelProcess());
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try run.sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = util.nextMetricPort(),
        .model_requests = source,
        .model_config = model_config,
    });
}

/// Expected decision tag for one request kind under `mrs.runtimeConfig()`.
fn expectedDecision(kind: mrs.RequestKind) u32 {
    return switch (kind) {
        .valid_replay => ModelDecisionTag.allow_replay,
        .missing_budget => ModelDecisionTag.missing_scope,
        .model_not_allowed => ModelDecisionTag.model_not_allowed,
        .unknown_substitution => ModelDecisionTag.replay_substitution_missing,
        .live_request => ModelDecisionTag.live_provider_disabled,
        .over_output_limit => ModelDecisionTag.output_limit,
    };
}

/// Asserts the request-to-result-to-audit relationship for every offset:
/// each request reaches the requester with its exact correlated result, and
/// each is audited exactly once with a contiguous hash chain. Returns the
/// number of allowed requests.
fn expectCorrelated(sup: *Supervisor, event_count: u64, source: mrs.ModelRequestSource) !u64 {
    const agent = try tileScratch(sup, "tkagnt");
    const audit = try tileScratch(sup, "tkaudt");
    const model = try tileScratch(sup, "tkmodl");
    const cfg = mrs.runtimeConfig();

    try std.testing.expectEqual(event_count, c_abi.tkagnt.resultCount(agent));
    try std.testing.expectEqual(event_count, c_abi.tkaudit.recordCount(audit));
    try std.testing.expectEqual(event_count, c_abi.tkmodl.ctxProcessed(model));

    var allowed: u64 = 0;
    var i: u64 = 0;
    while (i < event_count) : (i += 1) {
        const kind = source.kindAt(i);
        const decision = expectedDecision(kind);
        const req = mrs.buildRequest(source, i);

        // Result, delivered in request order with the exact request id.
        try std.testing.expectEqual(i + 1, c_abi.tkagnt.resultRequestId(agent, i));
        try std.testing.expectEqual(mrs.run_id, c_abi.tkagnt.resultRunId(agent, i));
        try std.testing.expectEqual(decision, c_abi.tkagnt.resultDecision(agent, i));
        try std.testing.expectEqual(req.prompt_hash, c_abi.tkagnt.resultPromptHash(agent, i));
        try std.testing.expectEqual(req.replay_substitution_id, c_abi.tkagnt.resultReplaySubstitutionId(agent, i));

        // Audit record for the same request: same offset, intact chain.
        try std.testing.expectEqual(i, c_abi.tkaudit.recordSeq(audit, i));
        try std.testing.expectEqual(i + 1, c_abi.tkaudit.recordSourceOffset(audit, i));
        var producer: [6]u8 = undefined;
        c_abi.tkaudit.recordDecidedBy(audit, i, &producer);
        try std.testing.expectEqualSlices(u8, "tkmodl", &producer);
        try std.testing.expect(c_abi.tkaudit.recordCapabilityEnvelope(audit, i) != 0);
        if (i == 0) {
            try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordPrevHash(audit, i));
        } else {
            try std.testing.expectEqual(c_abi.tkaudit.recordHash(audit, i - 1), c_abi.tkaudit.recordPrevHash(audit, i));
        }
        try std.testing.expect(c_abi.tkaudit.recordHash(audit, i) != 0);

        if (decision == ModelDecisionTag.allow_replay) {
            allowed += 1;
            const entry = cfg.fixtures[@intCast(mrs.fixtureIndexAt(i))];
            try std.testing.expectEqual(entry.response_hash, c_abi.tkagnt.resultResponseHash(agent, i));
            try std.testing.expectEqual(entry.total_tokens, c_abi.tkagnt.resultTotalTokens(agent, i));
            try std.testing.expectEqual(record_model_call, c_abi.tkaudit.recordType(audit, i));
            try std.testing.expectEqual(req.prompt_hash, c_abi.tkaudit.recordModelPromptHash(audit, i));
            try std.testing.expectEqual(entry.response_hash, c_abi.tkaudit.recordModelResponseHash(audit, i));
            try std.testing.expectEqual(entry.total_tokens, c_abi.tkaudit.recordModelTokenEstimate(audit, i));
            try std.testing.expectEqual(req.policy_decision_id, c_abi.tkaudit.recordModelPolicyDecisionId(audit, i));
            try std.testing.expectEqual(req.replay_substitution_id, c_abi.tkaudit.recordModelReplaySubstitutionId(audit, i));
            var model_id: [32]u8 = undefined;
            c_abi.tkaudit.recordModelId(audit, i, &model_id);
            try std.testing.expectEqualStrings(mrs.model_id, std.mem.sliceTo(&model_id, 0));
        } else {
            // A denied request carries no model output and is audited as a
            // denial with its reason code.
            try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.resultResponseHash(agent, i));
            try std.testing.expectEqual(@as(u32, 0), c_abi.tkagnt.resultTotalTokens(agent, i));
            try std.testing.expectEqual(record_denial, c_abi.tkaudit.recordType(audit, i));
            try std.testing.expectEqual(decision, c_abi.tkaudit.recordDenialReasonCode(audit, i));
        }
    }
    return allowed;
}

test "tkmodl_tile: replay requests are answered from the fixture table and audited" {
    const event_count: u64 = 8;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &.{.valid_replay}, mrs.runtimeConfig());
    defer run.deinit();
    waitForModelRun(&run.sup, event_count);

    for (run.sup.monitor()) |h| try std.testing.expect(h.state != .crashed);
    const m = run.sup.snapshotProcessMetrics();
    try std.testing.expectEqual(event_count, m.produced);
    try std.testing.expectEqual(event_count, m.allowed);
    try std.testing.expectEqual(@as(u64, 0), m.denied);
    try std.testing.expectEqual(event_count, m.audited);

    var source = mrs.ModelRequestSource{};
    source.pattern_len = 1;
    const allowed = try expectCorrelated(&run.sup, event_count, source);
    try std.testing.expectEqual(event_count, allowed);
}

test "tkmodl_tile: every denial reason is audited, answered, and never reaches a provider" {
    const pattern = [_]mrs.RequestKind{
        .valid_replay,
        .missing_budget,
        .model_not_allowed,
        .unknown_substitution,
        .live_request,
        .over_output_limit,
    };
    const event_count: u64 = 12; // two full cycles
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &pattern, mrs.runtimeConfig());
    defer run.deinit();
    waitForModelRun(&run.sup, event_count);

    for (run.sup.monitor()) |h| try std.testing.expect(h.state != .crashed);

    var source = mrs.ModelRequestSource{ .pattern_len = pattern.len };
    for (pattern, 0..) |kind, i| source.pattern[i] = kind;
    const allowed = try expectCorrelated(&run.sup, event_count, source);
    try std.testing.expectEqual(@as(u64, 2), allowed);

    const m = run.sup.snapshotProcessMetrics();
    try std.testing.expectEqual(@as(u64, 2), m.allowed);
    try std.testing.expectEqual(@as(u64, 10), m.denied);

    // Missing-scope denials name the missing field in both the result and the audit denial.
    const agent = try tileScratch(&run.sup, "tkagnt");
    const audit = try tileScratch(&run.sup, "tkaudt");
    var dim: [32]u8 = undefined;
    c_abi.tkagnt.resultFailedScopeDim(agent, 1, &dim);
    try std.testing.expectEqualStrings("budget_id", std.mem.sliceTo(&dim, 0));
    c_abi.tkaudit.recordDenialFailedScopeDim(audit, 1, &dim);
    try std.testing.expectEqualStrings("budget_id", std.mem.sliceTo(&dim, 0));
}

test "tkmodl_tile: more requests than link depth turn over credits with no loss or duplication" {
    // Request, audit and result links are depth 32; 96 requests force each
    // link's credits and dcache chunks to turn over three times.
    const event_count: u64 = 96;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &.{.valid_replay}, mrs.runtimeConfig());
    defer run.deinit();
    waitForModelRun(&run.sup, event_count);

    for (run.sup.monitor()) |h| try std.testing.expect(h.state != .crashed);
    const source = mrs.ModelRequestSource{};
    const allowed = try expectCorrelated(&run.sup, event_count, source);
    try std.testing.expectEqual(event_count, allowed);
}

test "tkmodl_tile: the final request is published and audited before the tile exits" {
    const event_count: u64 = 1;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &.{.valid_replay}, mrs.runtimeConfig());
    defer run.deinit();
    waitForModelRun(&run.sup, event_count);

    // tkmodl self-exits on its Nth committed request, without a HALT.
    var polls: u32 = 0;
    const model_idx = blk: {
        for (run.sup.topo.tiles, 0..) |t, i| if (t.name.eql(rt.tile_ids.tkmodl)) break :blk i;
        unreachable;
    };
    while (polls < model_max_polls) : (polls += 1) {
        run.sup.reapExitedChildrenNoHang();
        if (run.sup.monitor()[model_idx].state == .stopped) break;
        util.process.sleepNanos(model_poll_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, run.sup.monitor()[model_idx].state);
    _ = try expectCorrelated(&run.sup, event_count, mrs.ModelRequestSource{});
}

test "tkmodl_tile: a missing tkmodl.config makes the child fail closed with no output" {
    const event_count: u64 = 4;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &.{.valid_replay}, null);
    defer run.deinit();

    // tkmodl exits nonzero during setup; nothing is ever audited or answered.
    const model_idx = blk: {
        for (run.sup.topo.tiles, 0..) |t, i| if (t.name.eql(rt.tile_ids.tkmodl)) break :blk i;
        unreachable;
    };
    var polls: u32 = 0;
    while (polls < model_max_polls) : (polls += 1) {
        run.sup.reapExitedChildrenNoHang();
        if (run.sup.monitor()[model_idx].state != .running) break;
        util.process.sleepNanos(model_poll_ns);
    }
    try std.testing.expect(run.sup.monitor()[model_idx].state != .running);
    const audit = try tileScratch(&run.sup, "tkaudt");
    const agent = try tileScratch(&run.sup, "tkagnt");
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.resultCount(agent));
}

test "tkmodl_tile: a live-provider configuration is rejected and nothing is served" {
    const event_count: u64 = 4;
    var cfg = mrs.runtimeConfig();
    cfg.live_provider_enabled = 1;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &.{.valid_replay}, cfg);
    defer run.deinit();

    const model_idx = blk: {
        for (run.sup.topo.tiles, 0..) |t, i| if (t.name.eql(rt.tile_ids.tkmodl)) break :blk i;
        unreachable;
    };
    var polls: u32 = 0;
    while (polls < model_max_polls) : (polls += 1) {
        run.sup.reapExitedChildrenNoHang();
        if (run.sup.monitor()[model_idx].state != .running) break;
        util.process.sleepNanos(model_poll_ns);
    }
    try std.testing.expect(run.sup.monitor()[model_idx].state != .running);
    const audit = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.recordCount(audit));
}

test "tkmodl_tile: administrative HALT with zero event count stops every tile cleanly" {
    // event_count = 0 disables the stem gates, so tkmodl waits for work until
    // the supervisor's CNC HALT; it must stop cleanly with nothing committed.
    var run: ModelRun = undefined;
    try startModelRun(&run, 0, &.{.valid_replay}, mrs.runtimeConfig());
    defer run.deinit();

    const model_idx = blk: {
        for (run.sup.topo.tiles, 0..) |t, i| if (t.name.eql(rt.tile_ids.tkmodl)) break :blk i;
        unreachable;
    };
    var poll: u32 = 0;
    while (poll < model_max_polls) : (poll += 1) {
        run.sup.refreshProcessHealth();
        if (run.sup.monitor()[model_idx].state == .running) break;
        util.process.sleepNanos(model_poll_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.running, run.sup.monitor()[model_idx].state);

    const model = try tileScratch(&run.sup, "tkmodl");
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkmodl.ctxProcessed(model));

    run.sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
    // stopProcess detaches the workspace, so scratch is not read past this
    // point; the committed count was asserted above, before the HALT.
    for (run.sup.monitor()) |h| try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
}

// ---------------------------------------------------------------------------
// C-vs-Zig audit hash parity for the tkmodl record types.
//
// tkaudt hashes model_call and denial records in C (tk_audit_stem.c); the Zig
// codec (codec/audit/hash.zig) is the independent reference. Every committed
// record is copied out whole and re-hashed by the Zig implementation: the
// chain only means something if the two agree byte for byte.
// ---------------------------------------------------------------------------

const audit_zig = @import("audit");

fn zigHashOfCommittedRecord(ev: c_abi.tkaudit.CAuditEvent) !u64 {
    const payload: audit_zig.AuditEvent.Payload = switch (ev.record_type) {
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
    const pattern = [_]mrs.RequestKind{ .valid_replay, .missing_budget, .model_not_allowed, .live_request };
    const event_count: u64 = 8;
    var run: ModelRun = undefined;
    try startModelRun(&run, event_count, &pattern, mrs.runtimeConfig());
    defer run.deinit();
    waitForModelRun(&run.sup, event_count);

    const audit_scratch = try tileScratch(&run.sup, "tkaudt");
    try std.testing.expectEqual(event_count, c_abi.tkaudit.recordCount(audit_scratch));

    var saw_model_call = false;
    var saw_denial = false;
    var i: usize = 0;
    while (i < event_count) : (i += 1) {
        var ev: c_abi.tkaudit.CAuditEvent = undefined;
        c_abi.tkaudit.recordCopy(audit_scratch, i, &ev);
        const zig_hash = try zigHashOfCommittedRecord(ev);
        try std.testing.expectEqual(c_abi.tkaudit.recordHash(audit_scratch, i), zig_hash);
        if (ev.record_type == record_model_call) saw_model_call = true;
        if (ev.record_type == record_denial) saw_denial = true;
    }
    // The comparison covered both new record types, not just one.
    try std.testing.expect(saw_model_call);
    try std.testing.expect(saw_denial);
}
