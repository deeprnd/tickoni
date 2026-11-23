/// Process integration contracts for the agent path, with real child processes
/// and real shared-memory links:
///
///   harness -> tkings -> tknorm -> tkdedu -> tkcase -> tkpoly -> tkaudt (policy)
///                                              tkcase -> tkdisp -> tkagnt
///   tkagnt -> tkmodl[tier k] -> tkagnt -> tkaudt (audit) + tkdisp (result)
///
/// Every agent request is an event: it takes the spine, then tkdisp routes it to
/// tkagnt as one fixed record naming its prompt by reference, and tkagnt
/// resolves the prompt from the run's prompt table.
///
/// What is proved here, from the committed state of each tile's own scratch:
///   * every accepted agent request ends in exactly one terminal result, in
///     admission order, with the model's answer attributed to the instance that
///     served it;
///   * the committed audit sequence is the event order -- for each event, its
///     policy decision, then the model record (if any) and the agent record of
///     its run -- every record carrying the event's trace id, with a contiguous
///     hash chain that the independent Zig codec re-derives byte for byte;
///   * prompts and responses larger than one fragment (and than the 16-bit fd
///     size) cross every link intact, and audit records carry hashes only;
///   * a request for a tier that is not configured is an audited denial with no
///     model call; a model denial is an audited denial with its reason;
///   * more requests than slots, link depth, or credits are back-pressured, never
///     dropped; an administrative HALT drains every accepted request.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");
const supervisor_mod = @import("supervisor");
const topologies = @import("topologies");
const util = @import("util");
const audit_zig = @import("audit");
const stem_liveness = @import("stem_liveness");
const ingest = @import("ingest_harness");
const Harness = ingest.Harness;

const Supervisor = supervisor_mod.Supervisor;
const model_instances = supervisor_mod.model_instances;
const Tier = rt.model_tier.TkAgntModelTier;
const Outcome = c_abi.tkagnt.Outcome;

const tiles = @import("tiles");
const mrs = tiles.model_request_source;

// Tile indexes in topologies.agentProcess(n): tkings, tknorm, tkdedu, tkcase,
// tkpoly, tkaudt, tkdisp, tkagnt, then the tkmodl instances.
const idx_audit = 5;
const idx_agent = 7;
const first_model_idx = 8;

const record_policy_decision: u32 = 2;
const record_model_call: u32 = 3;
const record_proposal: u32 = 5;
const record_denial: u32 = 9;

const max_polls: u32 = 2000;
const poll_ns: u64 = 5 * std.time.ns_per_ms;

/// ModelDecision tags the denial kinds produce.
const decision_allow_replay: u8 = 1;

const InstanceSpec = struct { kind_id: u8, tier: Tier };

fn tileScratch(sup: *Supervisor, name: []const u8, kind_id: usize) !?*anyopaque {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    var name_buf: [8]u8 = undefined;
    const idx = c_abi.topob.topoFindTile(topo, util.toZ(&name_buf, name), kind_id);
    if (idx == c_abi.topob.not_found) return error.TileNotFound;
    return c_abi.topob.topoObjLaddr(topo, c_abi.topob.topoTileObjId(topo, idx));
}

/// Owns the per-instance configurations (fixtures and captured responses) and
/// the agent prompt table of a run: the supervisor copies them into files at
/// start, but the slices must outlive that call.
const Built = struct {
    arena: std.heap.ArenaAllocator,
    configs: []model_instances.InstanceConfig,
    prompts: []const []const u8,

    fn init(backing: std.mem.Allocator, specs: []const InstanceSpec, shape: mrs.Shape) !Built {
        var arena = std.heap.ArenaAllocator.init(backing);
        errdefer arena.deinit();
        const a = arena.allocator();
        const configs = try a.alloc(model_instances.InstanceConfig, specs.len);
        for (specs, configs) |spec, *out| {
            const class = mrs.classOf(@backingInt(spec.tier));
            const scratch = try a.alloc(u8, mrs.scratchBytes(shape) + 64);
            const cfg = mrs.fixtureConfig(class, shape, scratch);
            const contents = try a.alloc(model_instances.FixtureContent, shape.fixtures);
            for (contents, 0..) |*c, i| {
                const buf = try a.alloc(u8, mrs.scratchBytes(shape));
                const n = mrs.fillResponse(buf, class, i, shape);
                c.* = .{ .key = mrs.fixtureKey(i), .bytes = buf[0..n] };
            }
            out.* = .{ .kind_id = spec.kind_id, .tier = spec.tier, .config = cfg, .contents = contents };
        }
        // Allocate before `arena` is copied into the result, or the copy misses these.
        const prompts = try mrs.prompts(shape, a);
        return .{ .arena = arena, .configs = configs, .prompts = prompts };
    }

    fn deinit(self: *Built) void {
        self.arena.deinit();
    }
};

const AgentRun = struct {
    sup: Supervisor,
    tmp: @TypeOf(util.tmpDir()),
    built: Built,
    n_models: usize,
    /// The external producer on tkings's input, its only source.
    harness: Harness = .{},

    fn deinit(self: *AgentRun) void {
        // The harness writes into the shared workspace: stop it first.
        self.harness.finish();
        self.sup.stopProcess(std.testing.io) catch |err| std.log.err("teardown stop: {any}", .{err});
        self.sup.deinit();
        self.built.deinit();
        self.tmp.cleanup();
    }
};

fn startAgentRun(
    run: *AgentRun,
    comptime n: usize,
    specs: []const InstanceSpec,
    event_count: u64,
    source: mrs.ModelRequestSource,
) !void {
    std.debug.assert(specs.len == n);
    run.harness = .{};
    run.tmp = util.tmpDir();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try run.tmp.dir.realPath(std.testing.io, &path_buf)];

    run.built = try Built.init(std.testing.allocator, specs, source.shape);
    errdefer run.built.deinit();
    run.n_models = n;
    run.sup = try Supervisor.initForTest(std.testing.allocator, topologies.agentProcess(n));
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try run.sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = util.nextMetricPort(),
        .model_configs = run.built.configs,
        // tkdisp needs its payment template even when only agent requests arrive.
        .dispatch_template = source,
        .agent_prompts = run.built.prompts,
    });
    try run.harness.start(std.testing.allocator, &run.sup, .{ .agent_requests = source }, event_count);
}

/// Polls until every accepted request has its terminal result committed at
/// tkdisp and its agent record committed at tkaudt.
fn waitForRun(sup: *Supervisor, event_count: u64) void {
    const agent = tileScratch(sup, "tkagnt", 0) catch return;
    const audit = tileScratch(sup, "tkaudt", 0) catch return;
    const disp = tileScratch(sup, "tkdisp", 0) catch return;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (c_abi.tkdisp.resultCount(disp) >= event_count and
            c_abi.tkaudit.agentCommitted(audit) >= event_count and
            c_abi.tkagnt.terminalDone(agent) >= event_count) return;
        util.process.sleepNanos(poll_ns);
    }
}

/// The full investment workflow (14 tiles): the harness publishes payment events
/// on tkings's input, and tkdisp turns each one that tkcase forwards into one
/// agent request from the run's dispatch template.
fn startWorkflowRun(
    run: *AgentRun,
    specs: []const InstanceSpec,
    event_count: u64,
    template: mrs.ModelRequestSource,
) !void {
    // 0 derives the supervisor's default stale threshold.
    try startWorkflowRunStale(run, specs, event_count, template, 0);
}

/// `startWorkflowRun` with an explicit heartbeat stale threshold.
fn startWorkflowRunStale(
    run: *AgentRun,
    specs: []const InstanceSpec,
    event_count: u64,
    template: mrs.ModelRequestSource,
    stale_after_ns: u64,
) !void {
    run.harness = .{};
    run.tmp = util.tmpDir();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const run_dir = path_buf[0..try run.tmp.dir.realPath(std.testing.io, &path_buf)];

    run.built = try Built.init(std.testing.allocator, specs, template.shape);
    errdefer run.built.deinit();
    run.n_models = specs.len;
    // `init`, not `initForTest`: the registry must accept the whole topology.
    run.sup = try Supervisor.init(std.testing.allocator, topologies.investmentWorkflow());
    var ws_buf: [16]u8 = undefined;
    const workspace_name = util.nextWorkspaceName(&ws_buf);
    try run.sup.startPaymentPipelineProcess(std.testing.io, .{
        .run_dir = run_dir,
        .event_count = event_count,
        .heartbeat_stale_after_ns = stale_after_ns,
        .tile_exe_path = "build/zig-out/bin/tickoni-supervisor",
        .workspace_name = workspace_name,
        .metric_port = util.nextMetricPort(),
        .dispatch_template = template,
        .agent_prompts = run.built.prompts,
        .model_configs = run.built.configs,
    });
    if (event_count > 0) try run.harness.start(std.testing.allocator, &run.sup, .{ .payments = .{ .event_count = event_count } }, event_count);
}

/// Polls until every event has its terminal result at tkdisp and every record
/// (one policy decision, one model call and one proposal per event) is committed.
fn waitForWorkflow(sup: *Supervisor, event_count: u64) void {
    const audit = tileScratch(sup, "tkaudt", 0) catch return;
    const disp = tileScratch(sup, "tkdisp", 0) catch return;
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        if (c_abi.tkdisp.resultCount(disp) >= event_count and
            c_abi.tkaudit.recordCount(audit) >= 3 * event_count) return;
        util.process.sleepNanos(poll_ns);
    }
}

fn expectNoCrash(sup: *Supervisor) !void {
    for (sup.monitor()) |h| try std.testing.expect(h.state != .crashed);
}

// ---------------------------------------------------------------------------
// What each request should produce.
// ---------------------------------------------------------------------------

const ModelRecord = enum { none, call, denial };

const Expect = struct {
    outcome: Outcome,
    model_record: ModelRecord,
    /// ModelDecision of the result when a model answered, else 0.
    decision: u8,
    /// Tier ordinal that answered, or `tier_none`.
    source_tier: u8,
    kind: mrs.RequestKind,
    offset: u64,
};

fn configured(specs: []const InstanceSpec, tier: u8) bool {
    for (specs) |s| if (@backingInt(s.tier) == tier) return true;
    return false;
}

fn expectedFor(source: mrs.ModelRequestSource, specs: []const InstanceSpec, offset: u64) Expect {
    const kind = source.kindAt(offset);
    const tier = source.tierAt(offset);
    if (!configured(specs, tier)) {
        return .{ .outcome = .deny_absent_tier, .model_record = .none, .decision = 0, .source_tier = c_abi.tkagnt.tier_none, .kind = kind, .offset = offset };
    }
    // ModelDecision tags: 1 allow_replay, 2 missing scope, 3 model not allowed,
    // 6 output limit, 8 live provider disabled, 9 replay substitution missing.
    const decision: u8 = switch (kind) {
        .valid_replay => decision_allow_replay,
        // Only an embedding tier serves widths; on any other tier the kind is a no-op.
        .bad_embedding_dimension => if (mrs.classOf(tier) == .embedding) 10 else decision_allow_replay,
        .missing_budget => 2,
        .model_not_allowed => 3,
        .unknown_substitution => 9,
        .live_request => 8,
        .over_output_limit => 6,
    };
    const ok = decision == decision_allow_replay;
    return .{
        .outcome = if (ok) .ok else .model_denied,
        .model_record = if (ok) .call else .denial,
        .decision = decision,
        .source_tier = tier,
        .kind = kind,
        .offset = offset,
    };
}

/// Hash of the captured response for fixture `i` of `class`.
fn responseHashOf(alloc: std.mem.Allocator, class: mrs.TierClass, shape: mrs.Shape, i: u64) !struct { hash: u64, len: usize } {
    const buf = try alloc.alloc(u8, mrs.scratchBytes(shape));
    defer alloc.free(buf);
    const n = mrs.fillResponse(buf, class, i, shape);
    return .{ .hash = c_abi.multipart.messageHash(buf[0..n]), .len = n };
}

fn promptHashOf(alloc: std.mem.Allocator, shape: mrs.Shape, i: u64) !u64 {
    const buf = try alloc.alloc(u8, shape.prompt_bytes);
    defer alloc.free(buf);
    mrs.fillPrompt(buf, i);
    return c_abi.multipart.messageHash(buf);
}

/// Asserts, for every offset, the terminal result and the committed audit
/// sequence, and that the chain is intact. Returns the number of runs that
/// completed OK.
fn expectRun(
    sup: *Supervisor,
    source: mrs.ModelRequestSource,
    specs: []const InstanceSpec,
    event_count: u64,
) !u64 {
    const alloc = std.testing.allocator;
    const agent = try tileScratch(sup, "tkagnt", 0);
    const audit = try tileScratch(sup, "tkaudt", 0);
    const disp = try tileScratch(sup, "tkdisp", 0);
    const shape = source.shape;

    // One terminal result per accepted request, and nothing else.
    try std.testing.expectEqual(event_count, c_abi.tkagnt.admitted(agent));
    try std.testing.expectEqual(event_count, c_abi.tkagnt.terminalDone(agent));
    try std.testing.expectEqual(event_count, c_abi.tkdisp.resultCount(disp));
    try std.testing.expectEqual(event_count, c_abi.tkaudit.agentCommitted(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.rejectedCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.heldModelCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.heldAgentCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.mismatched(agent));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.transportDropped(agent));

    var ok_runs: u64 = 0;
    var rec: usize = 0; // next committed audit record
    var offset: u64 = 0;
    while (offset < event_count) : (offset += 1) {
        const want = expectedFor(source, specs, offset);
        const seq = offset + 1;
        const fixture = mrs.fixtureIndexAt(offset, shape);
        const class = mrs.classOf(source.tierAt(offset));

        // Terminal result: admission order, exact identity and outcome.
        const r = c_abi.tkdisp.result(disp, @intCast(offset));
        try std.testing.expectEqual(c_abi.tkagnt.wire_version, r.version);
        try std.testing.expectEqual(seq, r.agent_seq);
        try std.testing.expectEqual(mrs.runIdAt(offset), r.run_id);
        try std.testing.expectEqual(@backingInt(want.outcome), r.outcome);
        try std.testing.expectEqual(want.source_tier, r.source_tier);
        if (want.outcome == .ok) {
            ok_runs += 1;
            const expect_resp = try responseHashOf(alloc, class, shape, fixture);
            try std.testing.expectEqual(expect_resp.hash, r.response_hash);
            try std.testing.expectEqual(expect_resp.hash, r.proposal_hash);
            try std.testing.expectEqual(@as(u32, @intCast(expect_resp.len)), r.response_len);
            try std.testing.expectEqual(try promptHashOf(alloc, shape, fixture), r.prompt_hash);
            try std.testing.expectEqual(decision_allow_replay, r.model_decision);
            try std.testing.expectEqualStrings(mrs.model_id, std.mem.sliceTo(&r.model_id, 0));
        } else {
            try std.testing.expectEqual(@as(u64, 0), r.proposal_hash);
            try std.testing.expectEqual(@as(u32, 0), r.response_len);
        }

        // Committed audit sequence, in event order: this event's policy decision
        // (tkpoly allows every well-framed agent request, decision O1), then the
        // model record (if any) and the agent record of its run -- whatever order
        // the models answered in. Every record carries the event's trace id.
        try std.testing.expectEqual(record_policy_decision, c_abi.tkaudit.recordType(audit, rec));
        try std.testing.expectEqual(offset, c_abi.tkaudit.recordSourceOffset(audit, rec));
        try std.testing.expectEqual(@as(u8, 0), c_abi.tkaudit.recordOutcome(audit, rec));
        try std.testing.expectEqual(ingest.traceIdAt(offset), c_abi.tkaudit.recordTraceId(audit, rec));
        var by: [6]u8 = undefined;
        c_abi.tkaudit.recordDecidedBy(audit, rec, &by);
        try std.testing.expectEqualStrings("tkpoly", &by);
        rec += 1;
        if (want.model_record != .none) {
            try expectRecordHeader(audit, rec, "tkmodl", seq);
            try std.testing.expectEqual(ingest.traceIdAt(offset), c_abi.tkaudit.recordTraceId(audit, rec));
            switch (want.model_record) {
                .call => {
                    try std.testing.expectEqual(record_model_call, c_abi.tkaudit.recordType(audit, rec));
                    try std.testing.expectEqual(try promptHashOf(alloc, shape, fixture), c_abi.tkaudit.recordModelPromptHash(audit, rec));
                    const expect_resp = try responseHashOf(alloc, class, shape, fixture);
                    try std.testing.expectEqual(expect_resp.hash, c_abi.tkaudit.recordModelResponseHash(audit, rec));
                    try std.testing.expectEqual(mrs.fixtureKey(fixture), c_abi.tkaudit.recordModelReplaySubstitutionId(audit, rec));
                    var model_id: [32]u8 = undefined;
                    c_abi.tkaudit.recordModelId(audit, rec, &model_id);
                    try std.testing.expectEqualStrings(mrs.model_id, std.mem.sliceTo(&model_id, 0));
                },
                .denial => {
                    try std.testing.expectEqual(record_denial, c_abi.tkaudit.recordType(audit, rec));
                    try std.testing.expectEqual(@as(u32, want.decision), c_abi.tkaudit.recordDenialReasonCode(audit, rec));
                },
                .none => unreachable,
            }
            rec += 1;
        }
        try expectRecordHeader(audit, rec, "tkagnt", seq);
        try std.testing.expectEqual(ingest.traceIdAt(offset), c_abi.tkaudit.recordTraceId(audit, rec));
        try std.testing.expectEqual(ingest.traceIdAt(offset), r.trace_id);
        if (want.outcome == .ok) {
            try std.testing.expectEqual(record_proposal, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(r.proposal_hash, c_abi.tkaudit.recordProposalHash(audit, rec));
            var kind: [32]u8 = undefined;
            c_abi.tkaudit.recordProposalType(audit, rec, &kind);
            try std.testing.expectEqualStrings("agent_result", std.mem.sliceTo(&kind, 0));
        } else {
            try std.testing.expectEqual(record_denial, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(@as(u32, @backingInt(want.outcome)), c_abi.tkaudit.recordDenialReasonCode(audit, rec));
        }
        rec += 1;
    }
    try std.testing.expectEqual(@as(usize, rec), c_abi.tkaudit.recordCount(audit));

    // The hash chain is contiguous from the zero seed.
    var i: usize = 0;
    while (i < rec) : (i += 1) {
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSeq(audit, i));
        try std.testing.expectEqual(
            if (i == 0) @as(u64, 0) else c_abi.tkaudit.recordHash(audit, i - 1),
            c_abi.tkaudit.recordPrevHash(audit, i),
        );
        try std.testing.expect(c_abi.tkaudit.recordHash(audit, i) != 0);
    }
    return ok_runs;
}

fn expectRecordHeader(audit: ?*anyopaque, idx: usize, producer_name: []const u8, seq: u64) !void {
    try std.testing.expectEqual(seq, c_abi.tkaudit.recordSourceOffset(audit, idx));
    var producer: [6]u8 = undefined;
    c_abi.tkaudit.recordDecidedBy(audit, idx, &producer);
    try std.testing.expectEqualStrings(producer_name, &producer);
    try std.testing.expect(c_abi.tkaudit.recordCapabilityEnvelope(audit, idx) != 0);
}

/// Every committed record is copied out whole and re-hashed by the independent
/// Zig codec: the chain only means something if the two agree byte for byte.
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

/// Re-hashes every committed record with the Zig codec and compares. Returns
/// which record types the comparison covered, so a caller can assert that it
/// exercised the types its run is meant to produce.
const HashCoverage = struct { policy_decision: bool = false, model_call: bool = false, proposal: bool = false, denial: bool = false };

fn expectZigHashParity(sup: *Supervisor) !HashCoverage {
    const audit = try tileScratch(sup, "tkaudt", 0);
    const count = c_abi.tkaudit.recordCount(audit);
    var saw = HashCoverage{};
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var ev: c_abi.tkaudit.CAuditEvent = undefined;
        c_abi.tkaudit.recordCopy(audit, i, &ev);
        try std.testing.expectEqual(c_abi.tkaudit.recordHash(audit, i), try zigHashOfCommittedRecord(ev));
        switch (ev.record_type) {
            record_policy_decision => saw.policy_decision = true,
            record_model_call => saw.model_call = true,
            record_proposal => saw.proposal = true,
            record_denial => saw.denial = true,
            else => {},
        }
    }
    return saw;
}

/// The committed-audit watermark: tkaudt's last committed admission ordinal.
fn watermark(sup: *Supervisor) !u64 {
    const topo = sup.getTopo() orelse return error.NoProcessState;
    const obj = c_abi.topob.topoAuditWatermarkObj(topo);
    if (obj == c_abi.topob.not_found) return error.NoWatermark;
    const fseq = c_abi.fseq.fseqJoin(c_abi.topob.topoObjLaddr(topo, obj)) orelse return error.NoWatermark;
    return c_abi.fseq.fseqQuery(fseq);
}

fn singleSource(kind: mrs.RequestKind, tier: Tier, shape: mrs.Shape) mrs.ModelRequestSource {
    var s = mrs.ModelRequestSource{ .shape = shape };
    s.pattern[0] = kind;
    s.tiers[0] = @backingInt(tier);
    return s;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "tkagnt_tile: requests to one model complete with attributed, audited terminal results" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 8;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const source = singleSource(.valid_replay, .low, .{});
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(event_count, ok);
    const covered = try expectZigHashParity(&run.sup);
    try std.testing.expect(covered.model_call and covered.proposal and !covered.denial);

    // The watermark reached the last admission ordinal, and the counters agree.
    try std.testing.expectEqual(event_count, try watermark(&run.sup));
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(event_count, c_abi.tkagnt.dispatched(agent));
    try std.testing.expectEqual(event_count, c_abi.tkagnt.results(agent));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.denied(agent));
    const m = run.sup.snapshotProcessMetrics();
    try std.testing.expectEqual(event_count, m.produced);
    try std.testing.expectEqual(event_count, m.agent_dispatched);
    // `allowed` sums tkpoly's (every request passes the spine) and tkmodl's.
    try std.testing.expectEqual(2 * event_count, m.allowed);
}

test "tkagnt_tile: every model denial is audited, answered once, and carries its reason" {
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
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    var source = mrs.ModelRequestSource{ .pattern_len = pattern.len };
    for (pattern, 0..) |kind, i| source.pattern[i] = kind;
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(@as(u64, 2), ok);
    // The parity check covered all three record types the run commits.
    const covered = try expectZigHashParity(&run.sup);
    try std.testing.expect(covered.model_call and covered.proposal and covered.denial);

    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(@as(u64, 10), c_abi.tkagnt.denied(agent));
    const m = run.sup.snapshotProcessMetrics();
    // `allowed` sums tkpoly's (all 12 requests pass the spine) and tkmodl's (2).
    try std.testing.expectEqual(@as(u64, 12 + 2), m.allowed);
    try std.testing.expectEqual(@as(u64, 10), m.denied);

    // A missing-scope denial names the missing field in tkmodl's own record.
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    // Run 2 (index 1) is missing_budget: committed records are
    // [policy, model call, proposal, policy, model denial, agent denial, ...].
    var dim: [32]u8 = undefined;
    c_abi.tkaudit.recordDenialFailedScopeDim(audit, 4, &dim);
    try std.testing.expectEqualStrings("budget_id", std.mem.sliceTo(&dim, 0));
}

test "tkagnt_tile: a classifier result is interpreted and its confidence reported as it is" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 6; // fixtures cycle low/medium/high confidence
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .classifier_fast }};
    const source = singleSource(.valid_replay, .classifier_fast, .{});
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);
    _ = try expectRun(&run.sup, source, &specs, event_count);

    // No cascade: low confidence is a normal result, never a second dispatch.
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(event_count, c_abi.tkagnt.dispatched(agent));
    const levels = [_]c_abi.tkagnt.Confidence{ .low, .medium, .high };
    var i: usize = 0;
    while (i < event_count) : (i += 1) {
        const r = c_abi.tkdisp.result(disp, i);
        try std.testing.expectEqual(@backingInt(Outcome.ok), r.outcome);
        try std.testing.expectEqual(@backingInt(levels[i % 3]), r.confidence);
        try std.testing.expectEqual(@as(u8, @backingInt(Tier.medium)), r.recommended_tier);
        try std.testing.expectEqual(@as(u8, @backingInt(Tier.classifier_fast)), r.source_tier);
    }
}

test "tkagnt_tile: an embedding request returns its vector and is counted" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 4;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .embedding }};
    const source = singleSource(.valid_replay, .embedding, .{ .response_bytes = 4096 });
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);
    _ = try expectRun(&run.sup, source, &specs, event_count);

    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(event_count, c_abi.tkagnt.embeddings(agent));
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    try std.testing.expectEqual(@as(u32, 4096), c_abi.tkdisp.result(disp, 0).response_len);
}

test "tkagnt_tile: a sparse set of tiers serves its own requests and denies an absent tier without a model call" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // Three configured instances: kind 0 classifier_fast, 1 embedding, 2 max.
    // The stream cycles through those and `high`, which is not configured.
    const specs = [_]InstanceSpec{
        .{ .kind_id = 0, .tier = .classifier_fast },
        .{ .kind_id = 1, .tier = .embedding },
        .{ .kind_id = 2, .tier = .max },
    };
    var source = mrs.ModelRequestSource{ .pattern_len = 4 };
    source.tiers[0] = @backingInt(Tier.classifier_fast);
    source.tiers[1] = @backingInt(Tier.embedding);
    source.tiers[2] = @backingInt(Tier.max);
    source.tiers[3] = @backingInt(Tier.high); // absent
    const event_count: u64 = 16;
    var run: AgentRun = undefined;
    try startAgentRun(&run, 3, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(@as(u64, 12), ok);
    _ = try expectZigHashParity(&run.sup);

    // Only the served tiers were dispatched to; the absent-tier runs were
    // denied at routing with no model record and no dispatch.
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(@as(u64, 12), c_abi.tkagnt.dispatched(agent));
    try std.testing.expectEqual(@as(u64, 4), c_abi.tkagnt.denied(agent));
    // Each instance answered only its own tier's requests.
    for (0..3) |k| {
        const model = try tileScratch(&run.sup, "tkmodl", k);
        try std.testing.expectEqual(@as(u64, 4), c_abi.tkmodl.ctxProcessed(model));
    }
}

test "tkagnt_tile: all eleven tiers run at once with per-instance attribution" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    var specs: [11]InstanceSpec = undefined;
    for (&specs, 0..) |*s, k| s.* = .{ .kind_id = @intCast(k), .tier = @fromBackingInt(@intCast(k)) };
    var source = mrs.ModelRequestSource{ .pattern_len = 11 };
    for (0..11) |k| source.tiers[k] = @intCast(k);
    const event_count: u64 = 33; // three per tier
    var run: AgentRun = undefined;
    try startAgentRun(&run, 11, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(event_count, ok);
    _ = try expectZigHashParity(&run.sup);
    for (0..11) |k| {
        const model = try tileScratch(&run.sup, "tkmodl", k);
        try std.testing.expectEqual(@as(u64, 3), c_abi.tkmodl.ctxProcessed(model));
        try std.testing.expectEqual(@as(u64, 0), c_abi.tkmodl.ctxDropped(model));
    }
    try std.testing.expectEqual(event_count, try watermark(&run.sup));
}

test "tkagnt_tile: a prompt and a response each above 65535 bytes cross every link intact" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // 100,000 bytes is 13 fragments each way and above the 16-bit fd size.
    const shape = mrs.Shape{ .prompt_bytes = 100_000, .response_bytes = 100_000, .fixtures = 2 };
    try std.testing.expect(shape.prompt_bytes > c_abi.multipart.fd_sz_ceiling);
    const event_count: u64 = 4;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .high }};
    const source = singleSource(.valid_replay, .high, shape);
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    // expectRun checks the response hash and length against the bytes the
    // capture holds, and the prompt hash tkmodl computed from what it received.
    _ = try expectRun(&run.sup, source, &specs, event_count);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    try std.testing.expectEqual(@as(u32, 100_000), c_abi.tkdisp.result(disp, 0).response_len);
}

test "tkagnt_tile: messages near the 256 KiB ceiling are exact and the audit records carry hashes only" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // The prompt and the response each fill most of the multipart ceiling
    // (33 fragments, more than the link depth of 32).
    const shape = mrs.Shape{ .prompt_bytes = 260_000, .response_bytes = 260_000, .fixtures = 2 };
    const event_count: u64 = 3;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .max }};
    const source = singleSource(.valid_replay, .max, shape);
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);
    _ = try expectRun(&run.sup, source, &specs, event_count);

    // Audit records are fixed-size and body-free: every committed record fits
    // the audit link and none grew with the message.
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    var i: usize = 0;
    while (i < c_abi.tkaudit.recordCount(audit)) : (i += 1) {
        var ev: c_abi.tkaudit.CAuditEvent = undefined;
        c_abi.tkaudit.recordCopy(audit, i, &ev);
        try std.testing.expect(@sizeOf(c_abi.tkaudit.CAuditEvent) < 1024);
    }
    _ = try expectZigHashParity(&run.sup);
}

test "tkagnt_tile: more requests than slots, credits and link depth are back-pressured, never dropped" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // 24 requests of 100,000-byte prompts against 4 request slots and links
    // 32 fragments deep: the source must be held back, not the requests lost.
    const shape = mrs.Shape{ .prompt_bytes = 100_000, .response_bytes = 2_000, .fixtures = 2 };
    const event_count: u64 = 24;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .medium }};
    const source = singleSource(.valid_replay, .medium, shape);
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);
    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(event_count, ok);
}

test "tkagnt_tile: link credits and dcache chunks turn over without loss or duplication" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // 96 requests over links 32 fragments deep: three turnovers per link.
    const event_count: u64 = 96;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const source = singleSource(.valid_replay, .low, .{});
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);
    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(event_count, ok);
}

test "tkagnt_tile: the same accepted requests and captures commit the same audit chain on every run" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // Replay determinism at the audit layer: two independent runs of the same
    // requests against the same captures commit identical chain heads, even
    // though model processes and arrival times differ between the runs.
    const specs = [_]InstanceSpec{
        .{ .kind_id = 0, .tier = .low },
        .{ .kind_id = 1, .tier = .medium },
        .{ .kind_id = 2, .tier = .high },
    };
    var source = mrs.ModelRequestSource{ .pattern_len = 3 };
    source.tiers[0] = @backingInt(Tier.low);
    source.tiers[1] = @backingInt(Tier.medium);
    source.tiers[2] = @backingInt(Tier.high);
    const event_count: u64 = 24;

    var heads: [2]u64 = undefined;
    for (&heads) |*head| {
        var run: AgentRun = undefined;
        try startAgentRun(&run, 3, &specs, event_count, source);
        defer run.deinit();
        waitForRun(&run.sup, event_count);
        try expectNoCrash(&run.sup);
        _ = try expectRun(&run.sup, source, &specs, event_count);
        const audit = try tileScratch(&run.sup, "tkaudt", 0);
        head.* = c_abi.tkaudit.recordHash(audit, c_abi.tkaudit.recordCount(audit) - 1);
    }
    try std.testing.expect(heads[0] != 0);
    try std.testing.expectEqual(heads[0], heads[1]);
}

test "tkagnt_tile: an administrative HALT with nothing in flight stops every tile cleanly" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // event_count = 0 disables the event gates, so the agent waits for work
    // until the supervisor's CNC HALT; it must stop cleanly with nothing owed.
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, 0, singleSource(.valid_replay, .low, .{}));
    defer run.deinit();

    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        run.sup.refreshProcessHealth();
        if (run.sup.monitor()[idx_agent].state == .running) break;
        util.process.sleepNanos(poll_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.running, run.sup.monitor()[idx_agent].state);
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.admitted(agent));

    run.harness.finish();
    run.sup.stopProcess(std.testing.io) catch |err| @panic(@errorName(err));
    for (run.sup.monitor()) |h| try std.testing.expectEqual(rt.tile.TileState.stopped, h.state);
}

test "tkagnt_tile: a HALT mid-run drains every accepted request into one audited terminal result" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // Many large requests, halted while some are in flight. Whatever tkagnt had
    // accepted when it saw the HALT must end in a terminal result (completed, or
    // failed as shutdown) and an audit record; nothing accepted is lost.
    const shape = mrs.Shape{ .prompt_bytes = 100_000, .response_bytes = 2_000, .fixtures = 2 };
    const event_count: u64 = 400;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .medium }};
    const source = singleSource(.valid_replay, .medium, shape);
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();

    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);

    // Let some complete, then halt the agent alone (its own CNC) so the other
    // tiles keep running and can still be read after the drain.
    var poll: u32 = 0;
    while (poll < max_polls and c_abi.tkdisp.resultCount(disp) < 5) : (poll += 1) util.process.sleepNanos(poll_ns);
    try std.testing.expect(c_abi.tkdisp.resultCount(disp) >= 5);
    const state = run.sup.process_state orelse return error.NoProcessState;
    c_abi.cnc.signal(state.cncs[idx_agent].?, c_abi.cnc.signal_halt);

    poll = 0;
    while (poll < max_polls) : (poll += 1) {
        run.sup.reapExitedChildrenNoHang();
        if (run.sup.monitor()[idx_agent].state == .stopped) break;
        util.process.sleepNanos(poll_ns);
    }
    try std.testing.expectEqual(rt.tile.TileState.stopped, run.sup.monitor()[idx_agent].state);

    // tkaudt and tkdisp are still up: read what the drain produced.
    const admitted = c_abi.tkagnt.admitted(agent);
    try std.testing.expect(admitted >= 5 and admitted < event_count);
    try std.testing.expectEqual(admitted, c_abi.tkagnt.terminalDone(agent));
    try std.testing.expectEqual(admitted, c_abi.tkdisp.resultCount(disp));
    try std.testing.expectEqual(admitted, c_abi.tkaudit.agentCommitted(audit));
    var i: usize = 0;
    while (i < admitted) : (i += 1) {
        const r = c_abi.tkdisp.result(disp, i);
        try std.testing.expectEqual(@as(u64, i + 1), r.agent_seq);
        const outcome = r.outcome;
        try std.testing.expect(outcome == @backingInt(Outcome.ok) or outcome == @backingInt(Outcome.shutdown));
    }
    // And a terminal result never preceded its audit commit.
    try std.testing.expectEqual(admitted, try watermark(&run.sup));
}

fn haltTile(sup: *Supervisor, tile_idx: usize) !void {
    const state = sup.process_state orelse return error.NoProcessState;
    c_abi.cnc.signal(state.cncs[tile_idx].?, c_abi.cnc.signal_halt);
    var poll: u32 = 0;
    while (poll < max_polls) : (poll += 1) {
        sup.reapExitedChildrenNoHang();
        if (sup.monitor()[tile_idx].state == .stopped) return;
        util.process.sleepNanos(poll_ns);
    }
    return error.TileDidNotStop;
}

test "tkagnt_tile: no terminal result is published ahead of its audit commit" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // Stop tkaudt, the only tile that advances the committed-order watermark.
    // The agent keeps admitting, dispatching and resolving runs, but it must not
    // publish a terminal result for any run whose audit record is not committed:
    // the terminal results delivered are exactly the committed ordinals.
    const event_count: u64 = 200;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const source = singleSource(.valid_replay, .low, .{});
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();

    try haltTile(&run.sup, idx_audit);
    // Give the still-running agent time to run into the blocked audit path.
    util.process.sleepNanos(600 * std.time.ns_per_ms);

    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    const wm = try watermark(&run.sup);
    const committed: u64 = if (wm == std.math.maxInt(u64)) 0 else wm;
    const done = c_abi.tkagnt.terminalDone(agent);

    try std.testing.expectEqual(committed, done);
    try std.testing.expectEqual(done, c_abi.tkdisp.resultCount(disp));
    // The agent has more work stuck behind the barrier, so the equality above is
    // the barrier holding, not the run having finished.
    try std.testing.expect(c_abi.tkagnt.admitted(agent) > done);
    var i: usize = 0;
    while (i < done) : (i += 1) {
        try std.testing.expect(c_abi.tkdisp.result(disp, i).agent_seq <= committed);
    }
}

test "tkagnt_tile: a model that stops answering ends each run in an audited timeout" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // The only tkmodl is stopped before the requests can be answered (or just
    // after the first). Each unanswered run must still end in one terminal
    // result and one agent audit record, with no model record to wait for.
    const event_count: u64 = 4;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const source = singleSource(.valid_replay, .low, .{ .timeout_ms = 300 });
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    try haltTile(&run.sup, first_model_idx);
    waitForRun(&run.sup, event_count);

    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    try std.testing.expectEqual(event_count, c_abi.tkdisp.resultCount(disp));
    try std.testing.expectEqual(event_count, c_abi.tkaudit.agentCommitted(audit));

    // Walk the committed chain against the terminal results: each event's policy
    // decision, then for an OK run a model record and a proposal, for a timed-out
    // run a single agent denial.
    var rec: usize = 0;
    var timeouts: u64 = 0;
    var i: usize = 0;
    while (i < event_count) : (i += 1) {
        const r = c_abi.tkdisp.result(disp, i);
        try std.testing.expectEqual(@as(u64, i + 1), r.agent_seq);
        try std.testing.expectEqual(record_policy_decision, c_abi.tkaudit.recordType(audit, rec));
        rec += 1;
        if (r.outcome == @backingInt(Outcome.ok)) {
            try std.testing.expectEqual(record_model_call, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(record_proposal, c_abi.tkaudit.recordType(audit, rec + 1));
            rec += 2;
        } else {
            try std.testing.expectEqual(@backingInt(Outcome.model_timeout), r.outcome);
            try std.testing.expectEqual(record_denial, c_abi.tkaudit.recordType(audit, rec));
            try std.testing.expectEqual(@as(u32, @backingInt(Outcome.model_timeout)), c_abi.tkaudit.recordDenialReasonCode(audit, rec));
            try std.testing.expectEqual(c_abi.tkagnt.tier_none, r.source_tier);
            rec += 1;
            timeouts += 1;
        }
    }
    try std.testing.expect(timeouts >= 1);
    try std.testing.expectEqual(rec, c_abi.tkaudit.recordCount(audit));
    try std.testing.expectEqual(event_count, c_abi.tkagnt.terminalDone(agent));
}

test "tkagnt_tile: embedding governance denies a model or vector width the instance does not serve" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    // An embedding instance serves one model at one width. A request for another
    // width, or for a model outside the embedding allowlist, is denied before any
    // vector is produced: audited, never truncated or padded.
    const pattern = [_]mrs.RequestKind{ .valid_replay, .bad_embedding_dimension, .model_not_allowed };
    var source = mrs.ModelRequestSource{ .pattern_len = pattern.len, .shape = .{ .response_bytes = 4096 } };
    for (pattern, 0..) |kind, i| {
        source.pattern[i] = kind;
        source.tiers[i] = @backingInt(Tier.embedding);
    }
    const event_count: u64 = 9;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .embedding }};
    var run: AgentRun = undefined;
    try startAgentRun(&run, 1, &specs, event_count, source);
    defer run.deinit();
    waitForRun(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const ok = try expectRun(&run.sup, source, &specs, event_count);
    try std.testing.expectEqual(@as(u64, 3), ok);
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    try std.testing.expectEqual(@as(u64, 6), c_abi.tkagnt.denied(agent));
    try std.testing.expectEqual(@as(u64, 3), c_abi.tkagnt.embeddings(agent));
    // The dimension denial carries its own reason in tkmodl's audit record.
    const audit = try tileScratch(&run.sup, "tkaudt", 0);
    // Committed order: [policy, call, proposal] for run 1, then [policy,
    // denial(10), agent denial] for run 2 (bad width).
    try std.testing.expectEqual(@as(u32, 10), c_abi.tkaudit.recordDenialReasonCode(audit, 4));
}

test "tkagnt_tile: the full investment workflow turns each event into one audited agent run" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 6;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const template = singleSource(.valid_replay, .low, .{});
    var run: AgentRun = undefined;
    try startWorkflowRun(&run, &specs, event_count, template);
    defer run.deinit();
    waitForWorkflow(&run.sup, event_count);
    try expectNoCrash(&run.sup);

    const alloc = std.testing.allocator;
    const case = try tileScratch(&run.sup, "tkcase", 0);
    const tool = try tileScratch(&run.sup, "tktool", 0);
    const adapter = try tileScratch(&run.sup, "tkadpt", 0);
    const disp = try tileScratch(&run.sup, "tkdisp", 0);
    const agent = try tileScratch(&run.sup, "tkagnt", 0);
    const audit = try tileScratch(&run.sup, "tkaudt", 0);

    // tkcase forwarded every event; the idle tool and adapter tiles saw nothing.
    try std.testing.expectEqual(event_count, c_abi.tkpass.forwarded(case));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkpass.consumed(tool));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkpass.consumed(adapter));

    // Each event became exactly one request, one admission and one terminal result.
    try std.testing.expectEqual(event_count, c_abi.tkdisp.eventsSeen(disp));
    try std.testing.expectEqual(event_count, c_abi.tkdisp.scheduled(disp));
    try std.testing.expectEqual(event_count, c_abi.tkagnt.admitted(agent));
    try std.testing.expectEqual(event_count, c_abi.tkagnt.terminalDone(agent));
    try std.testing.expectEqual(event_count, c_abi.tkdisp.resultCount(disp));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.mismatched(agent));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkagnt.transportDropped(agent));

    // The request is the template, not the event: every run names the template's
    // tier and fixture, and carries the event's own source offset as its run id.
    const resp = try responseHashOf(alloc, mrs.classOf(@backingInt(Tier.low)), template.shape, mrs.fixtureIndexAt(0, template.shape));
    var offset: u64 = 0;
    while (offset < event_count) : (offset += 1) {
        const r = c_abi.tkdisp.result(disp, @intCast(offset));
        try std.testing.expectEqual(offset + 1, r.agent_seq);
        try std.testing.expectEqual(mrs.runIdAt(offset), r.run_id);
        try std.testing.expectEqual(@backingInt(Outcome.ok), r.outcome);
        try std.testing.expectEqual(resp.hash, r.proposal_hash);
        try std.testing.expectEqual(@as(u8, @backingInt(Tier.low)), r.source_tier);
    }

    // The audit chain holds, per event, its policy decision (from the spine),
    // then the model record and the agent record of its admission ordinal.
    try std.testing.expectEqual(event_count, c_abi.tkaudit.agentCommitted(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.rejectedCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.heldModelCount(audit));
    try std.testing.expectEqual(@as(u64, 0), c_abi.tkaudit.heldAgentCount(audit));
    const count = c_abi.tkaudit.recordCount(audit);
    try std.testing.expectEqual(@as(usize, 3 * event_count), count);

    // One chain in event order: for event e, its policy decision (source offset
    // e), then its model record and its agent record (admission ordinal e + 1).
    // Nothing interleaves differently from run to run.
    var e: usize = 0;
    while (e < event_count) : (e += 1) {
        const first = 3 * e;
        try std.testing.expectEqual(record_policy_decision, c_abi.tkaudit.recordType(audit, first));
        try std.testing.expectEqual(@as(u64, e), c_abi.tkaudit.recordSourceOffset(audit, first));
        // One trace per event, on all three of its records.
        for (0..3) |k| try std.testing.expectEqual(ingest.traceIdAt(e), c_abi.tkaudit.recordTraceId(audit, first + k));
        try std.testing.expectEqual(record_model_call, c_abi.tkaudit.recordType(audit, first + 1));
        try expectRecordHeader(audit, first + 1, "tkmodl", e + 1);
        try std.testing.expectEqual(record_proposal, c_abi.tkaudit.recordType(audit, first + 2));
        try expectRecordHeader(audit, first + 2, "tkagnt", e + 1);
    }
    var i: usize = 0;
    while (i < count) : (i += 1) {
        // The chain is contiguous from the zero seed.
        try std.testing.expectEqual(@as(u64, i), c_abi.tkaudit.recordSeq(audit, i));
        try std.testing.expectEqual(
            if (i == 0) @as(u64, 0) else c_abi.tkaudit.recordHash(audit, i - 1),
            c_abi.tkaudit.recordPrevHash(audit, i),
        );
    }
    try std.testing.expectEqual(event_count, try watermark(&run.sup));

    // The Zig codec agrees with the C chain on every record.
    i = 0;
    while (i < count) : (i += 1) {
        var ev: c_abi.tkaudit.CAuditEvent = undefined;
        c_abi.tkaudit.recordCopy(audit, i, &ev);
        try std.testing.expectEqual(c_abi.tkaudit.recordHash(audit, i), try zigHashOfCommittedRecord(ev));
    }

    const m = run.sup.snapshotProcessMetrics();
    try std.testing.expectEqual(event_count, m.produced);
    try std.testing.expectEqual(event_count, m.agent_dispatched);
}

test "tkagnt_tile: the full workflow commits the same event-ordered chain on every run" {
    const shouldSkip = false;
    if (shouldSkip) return error.SkipZigTest;
    const event_count: u64 = 6;
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    const template = singleSource(.valid_replay, .low, .{});
    var heads: [3]u64 = undefined;
    for (&heads) |*head| {
        var run: AgentRun = undefined;
        try startWorkflowRun(&run, &specs, event_count, template);
        defer run.deinit();
        waitForWorkflow(&run.sup, event_count);
        try expectNoCrash(&run.sup);
        const audit = try tileScratch(&run.sup, "tkaudt", 0);
        const count = c_abi.tkaudit.recordCount(audit);
        try std.testing.expectEqual(@as(usize, 3 * event_count), count);
        head.* = c_abi.tkaudit.recordHash(audit, count - 1);
    }
    try std.testing.expect(heads[0] != 0);
    try std.testing.expectEqual(heads[0], heads[1]);
    try std.testing.expectEqual(heads[1], heads[2]);
}

// ---------------------------------------------------------------------------
// CNC liveness of every stem tile in the 14-tile workflow: tknorm, tkdedu,
// tkcase, tkpoly, tkaudt, tkdisp (scheduler), tkagnt, tkmodl, tktool, tkadpt
// and tkdiag, i.e. every tk_*_stem.c, plus the metric tile. event_count = 0 disables the event gates,
// so each tile idles in its stem loop; see stem_liveness.zig.
// ---------------------------------------------------------------------------

test "tkagnt_tile: every stem tile of the full workflow reaches CNC RUN and advances its heartbeat while idle" {
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    var run: AgentRun = undefined;
    try startWorkflowRunStale(&run, &specs, 0, singleSource(.valid_replay, .low, .{}), stem_liveness.stale_after_ns);
    defer run.deinit();

    try stem_liveness.expectStemTilesAlive(&run.sup);
    try stem_liveness.expectNoStemTileStale(&run.sup);
    try expectNoCrash(&run.sup);
}

test "tkagnt_tile: a frozen stem tile of the full workflow is classified stale and its siblings are not" {
    const specs = [_]InstanceSpec{.{ .kind_id = 0, .tier = .low }};
    var run: AgentRun = undefined;
    try startWorkflowRunStale(&run, &specs, 0, singleSource(.valid_replay, .low, .{}), stem_liveness.stale_after_ns);
    defer run.deinit();
    try stem_liveness.expectStemTilesAlive(&run.sup);

    // tkagnt is the tile whose loop carries the most work; freeze it alone,
    // then freeze every remaining stem tile.
    try stem_liveness.expectFrozenTileGoesStaleAlone(&run.sup, stem_liveness.indexOf(&run.sup, rt.tile_ids.tkagnt));
    try stem_liveness.expectEveryFrozenStemTileGoesStale(&run.sup);
    try expectNoCrash(&run.sup);
}
