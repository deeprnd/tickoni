//! Test-build synthetic agent-request source for the tkagnt fixture/replay
//! topologies, and the fixture material it is paired with.
//!
//! The integration test harness publishes these requests on tkings's input as
//! agent-request events, and the full workflow's dispatch template is built
//! from the same source. Each request is a `TkAgentRequestMsg`: the scope and a
//! reference to its prompt (`TkPromptRef`), never the prompt bytes. The prompts
//! themselves are the run's agent prompt table (`prompts`), which tkagnt
//! resolves references against and sends to tkmodl as a multipart stream, so a
//! prompt larger than one fragment (or one 16-bit fd size) is exercised exactly
//! as a real one would be. The same module builds the matching tkmodl fixtures
//! and their captured response bytes, so the requests, the prompt table and the
//! fixture table share one definition: a "valid replay" request always
//! resolves, and each injected kind fails for exactly one named reason.
//!
//! Gated on `runtime.test_build.enabled` by the caller; this file carries no
//! gate of its own and has no effect unless a process is handed a source.
const std = @import("std");
const c_abi = @import("c_abi");

const tkmodl = c_abi.tkmodl;
const multipart = c_abi.multipart;
const audit_mod = @import("audit_mod");

pub const model_id = "fixture.model";
pub const other_model_id = "other.model";
pub const fixture_key_base: u64 = 1000;
/// A substitution id that is deliberately absent from the fixture table.
pub const unknown_substitution_id: u64 = 9999;
/// Hard limits applied by `fixtureConfig`. `over_output_limit` requests
/// exceed `hard_max_output_tokens` by one.
pub const hard_max_output_tokens: u32 = 1024;
pub const pattern_cap = 16;

/// The tier ordinal a pattern slot requests when none is given: `low`.
pub const default_tier: u8 = 6;

/// What one synthetic request is built to trigger.
pub const RequestKind = enum(u8) {
    valid_replay,
    missing_budget,
    model_not_allowed,
    unknown_substitution,
    live_request,
    over_output_limit,
    /// Embedding tiers only: the requested vector width is one the instance does
    /// not serve. On any other tier this behaves as `valid_replay`.
    bad_embedding_dimension,
};

/// How a tier's captured responses are shaped, which fixes what the agent
/// interprets: a classifier returns its strict JSON object, an embedding tier a
/// vector (whole f32 elements), an LLM tier opaque text.
pub const TierClass = enum { classifier, embedding, llm };

pub fn classOf(tier: u8) TierClass {
    const t = @import("runtime").model_tier.TkAgntModelTier.fromInt(tier) orelse return .llm;
    if (t.isClassifier()) return .classifier;
    if (t.isEmbedding()) return .embedding;
    return .llm;
}

/// Sizes of the prompt each request carries and of each captured response. Set
/// either above `multipart.frag_payload_max` (or the 16-bit fd size) to drive
/// multi-fragment transport.
pub const Shape = struct {
    prompt_bytes: u32 = 96,
    response_bytes: u32 = 128,
    /// Captured results per tkmodl instance. The captures of one instance
    /// together must fit tkmodl's content store, so a shape with very large
    /// responses uses few of them.
    fixtures: u8 = 8,
    /// How long the agent waits for the model's result, in the request scope.
    timeout_ms: u32 = 30_000,
};

/// The request stream: `pattern[offset % pattern_len]` selects each kind and
/// `tiers[offset % pattern_len]` the tier it names.
pub const ModelRequestSource = struct {
    pattern: [pattern_cap]RequestKind = @splat(.valid_replay),
    tiers: [pattern_cap]u8 = @splat(default_tier),
    pattern_len: u8 = 1,
    shape: Shape = .{},

    pub fn kindAt(self: ModelRequestSource, offset: u64) RequestKind {
        std.debug.assert(self.pattern_len > 0 and self.pattern_len <= pattern_cap);
        return self.pattern[@intCast(offset % self.pattern_len)];
    }

    pub fn tierAt(self: ModelRequestSource, offset: u64) u8 {
        std.debug.assert(self.pattern_len > 0 and self.pattern_len <= pattern_cap);
        return self.tiers[@intCast(offset % self.pattern_len)];
    }
};

pub fn fixtureKey(i: u64) u64 {
    return fixture_key_base + i;
}

/// Run id of the request at stream `offset`: `offset + 1`, so a result or an
/// audit record is correlated back to its offset.
pub fn runIdAt(offset: u64) u64 {
    return offset + 1;
}

/// Vector width, in f32 elements, an embedding tier serves for this shape.
pub fn embeddingDimensions(shape: Shape) u32 {
    return (shape.response_bytes + 3) / 4;
}

/// Index of the fixture a `valid_replay` request at `offset` resolves to.
pub fn fixtureIndexAt(offset: u64, shape: Shape) u64 {
    return offset % shape.fixtures;
}

/// Deterministic prompt bytes for fixture `i`.
pub fn fillPrompt(buf: []u8, i: u64) void {
    for (buf, 0..) |*b, n| b.* = @truncate((n *% 131) +% (i *% 17) +% 0x50);
}

/// Deterministic captured response for fixture `i` of tier class `class`, written
/// into `buf` (at least `shape.response_bytes + 64` bytes); returns its length.
pub fn fillResponse(buf: []u8, class: TierClass, i: u64, shape: Shape) usize {
    switch (class) {
        .classifier => {
            // Confidence cycles low/medium/high; the recommendation is `medium`.
            const levels = [_][]const u8{ "low", "medium", "high" };
            const text = std.fmt.bufPrint(buf, "{{\"confidence\":\"{s}\",\"recommended_tier\":\"medium\"}}", .{levels[@intCast(i % 3)]}) catch unreachable;
            return text.len;
        },
        .embedding => {
            // Whole f32 elements: round the shape up to a multiple of 4.
            const len = (@as(usize, shape.response_bytes) + 3) / 4 * 4;
            for (buf[0..len], 0..) |*b, n| b.* = @truncate((n *% 29) +% (i *% 13) +% 0x65);
            return len;
        },
        .llm => {
            const len: usize = shape.response_bytes;
            for (buf[0..len], 0..) |*b, n| b.* = @truncate((n *% 29) +% (i *% 13) +% 0x72);
            return len;
        },
    }
}

/// Captured result `i`: its key, the hash of the prompt it answers, and the hash
/// of its response, both computed from the actual bytes. `scratch` must hold the
/// larger of the prompt and the response.
pub fn fixtureEntry(i: u64, class: TierClass, shape: Shape, scratch: []u8) tkmodl.TkModlFixtureEntry {
    var e = std.mem.zeroes(tkmodl.TkModlFixtureEntry);
    e.key = fixtureKey(i);
    const prompt = scratch[0..shape.prompt_bytes];
    fillPrompt(prompt, i);
    e.prompt_hash = multipart.messageHash(prompt);
    const n = fillResponse(scratch, class, i, shape);
    e.response_hash = multipart.messageHash(scratch[0..n]);
    e.prompt_tokens = @intCast(100 + i);
    e.completion_tokens = @intCast(50 + i);
    e.total_tokens = e.prompt_tokens + e.completion_tokens;
    e.latency_ms = @intCast(10 + i);
    tkmodl.setField(&e.model_id, model_id) catch unreachable;
    return e;
}

/// A tkmodl runtime configuration paired with this source: `model_id`
/// allowlisted, a hard output limit, a live provider disabled, and
/// `shape.fixtures` captured results of `class`. The captured response bytes
/// themselves are `fillResponse(.., class, i, shape)` for each fixture `i`; they
/// are replay material kept outside this record.
pub fn fixtureConfig(class: TierClass, shape: Shape, scratch: []u8) tkmodl.TkModlRuntimeConfig {
    var cfg = std.mem.zeroes(tkmodl.TkModlRuntimeConfig);
    cfg.magic = tkmodl.config_magic;
    cfg.version = tkmodl.config_version;
    cfg.hard_max_output_tokens = hard_max_output_tokens;
    cfg.allowed_model_count = 1;
    tkmodl.setField(&cfg.allowed_model_ids[0], model_id) catch unreachable;
    if (class == .embedding) {
        // An embedding instance serves one model at one vector width.
        cfg.allowed_embedding_model_count = 1;
        tkmodl.setField(&cfg.allowed_embedding_model_ids[0], model_id) catch unreachable;
        cfg.allowed_embedding_dimension_count = 1;
        cfg.allowed_embedding_dimensions[0] = embeddingDimensions(shape);
    }
    cfg.fixture_count = shape.fixtures;
    var i: u64 = 0;
    while (i < shape.fixtures) : (i += 1) cfg.fixtures[@intCast(i)] = fixtureEntry(i, class, shape, scratch);
    return cfg;
}

/// Bytes a caller must provide as `scratch` to `fixtureConfig` / `fixtureEntry`.
pub fn scratchBytes(shape: Shape) usize {
    return @max(shape.prompt_bytes, shape.response_bytes) + 64;
}

/// The run's agent prompt table for `shape`: the prompt of each fixture, in
/// fixture order, allocated from `allocator` (an arena in practice). tkagnt
/// resolves every request's `prompt_ref` against these.
pub fn prompts(shape: Shape, allocator: std.mem.Allocator) ![]const []const u8 {
    const out = try allocator.alloc([]const u8, shape.fixtures);
    for (out, 0..) |*p, i| {
        const buf = try allocator.alloc(u8, shape.prompt_bytes);
        fillPrompt(buf, i);
        p.* = buf;
    }
    return out;
}

/// The reference a request for fixture `i` carries: the multipart message hash
/// and length of `fillPrompt(.., i)`. `scratch` must hold `shape.prompt_bytes`.
pub fn promptRef(i: u64, shape: Shape, scratch: []u8) audit_mod.TkPromptRef {
    const prompt = scratch[0..shape.prompt_bytes];
    fillPrompt(prompt, i);
    var r = std.mem.zeroes(audit_mod.TkPromptRef);
    r.prompt_hash = multipart.messageHash(prompt);
    r.prompt_len = shape.prompt_bytes;
    return r;
}

/// Builds the agent request for stream `offset`: its scope and the reference
/// to its fixture's prompt. `scratch` must hold `shape.prompt_bytes` (the
/// prompt is hashed, not carried).
pub fn buildAgentRequest(source: ModelRequestSource, offset: u64, scratch: []u8) audit_mod.TkAgentRequestMsg {
    const kind = source.kindAt(offset);
    const i = fixtureIndexAt(offset, source.shape);
    const tier = source.tierAt(offset);

    var h = std.mem.zeroes(audit_mod.TkAgentRequestMsg);
    h.version = audit_mod.TK_AGENT_WIRE_VERSION;
    h.request_type = if (classOf(tier) == .embedding) audit_mod.TK_AGENT_REQ_EMBEDDING else audit_mod.TK_AGENT_REQ_CHAT;
    h.requested_tier = tier;
    h.prompt_ref = promptRef(i, source.shape, scratch);

    var m = &h.scope;
    m.version = tkmodl.wire_version;
    m.replay_mode = 1;
    m.retry_limit = 1;
    m.run_id = runIdAt(offset);
    m.actor_id = 7;
    m.account_id = 42;
    m.policy_decision_id = 500 + offset;
    m.replay_substitution_id = fixtureKey(i);
    m.max_context_tokens = 2048;
    m.max_output_tokens = 512;
    m.timeout_ms = source.shape.timeout_ms;
    if (classOf(tier) == .embedding) m.embedding_dimensions = embeddingDimensions(source.shape);
    tkmodl.setField(&m.model_id, model_id) catch unreachable;
    tkmodl.setField(&m.actor_role, "ops_reviewer") catch unreachable;
    tkmodl.setField(&m.workflow, "trading_control") catch unreachable;
    tkmodl.setField(&m.capability, "trading_order.propose") catch unreachable;
    tkmodl.setField(&m.capability_envelope_id, "capenv.fixture") catch unreachable;
    tkmodl.setField(&m.policy_version, "v1") catch unreachable;
    tkmodl.setField(&m.budget_id, "budget.fixture") catch unreachable;

    switch (kind) {
        .valid_replay => {},
        .missing_budget => @memset(&m.budget_id, 0),
        .model_not_allowed => {
            @memset(&m.model_id, 0);
            tkmodl.setField(&m.model_id, other_model_id) catch unreachable;
        },
        .unknown_substitution => m.replay_substitution_id = unknown_substitution_id,
        .live_request => m.replay_mode = 0,
        .over_output_limit => m.max_output_tokens = hard_max_output_tokens + 1,
        .bad_embedding_dimension => if (classOf(tier) == .embedding) {
            m.embedding_dimensions += 1;
        },
    }
    return h;
}

test "valid_replay requests resolve to a fixture with the same key, prompt and model" {
    const shape = Shape{};
    var scratch: [512]u8 = undefined;
    const cfg = fixtureConfig(.llm, shape, &scratch);
    const src = ModelRequestSource{};
    var body: [1024]u8 = undefined;
    var offset: u64 = 0;
    while (offset < 20) : (offset += 1) {
        const hdr = buildAgentRequest(src, offset, &body);
        try std.testing.expect(tkmodl.requestWellFormed(&hdr.scope));
        try std.testing.expectEqual(@as(u8, 1), tkmodl.validate(&cfg, &hdr.scope, null)); // MODEL_ALLOW_REPLAY
        const entry = cfg.fixtures[@intCast(fixtureIndexAt(offset, shape))];
        try std.testing.expectEqual(entry.key, hdr.scope.replay_substitution_id);
        // The fixture was captured against exactly the prompt the reference names.
        try std.testing.expectEqual(entry.prompt_hash, hdr.prompt_ref.prompt_hash);
        try std.testing.expectEqual(shape.prompt_bytes, hdr.prompt_ref.prompt_len);
        try std.testing.expectEqual(runIdAt(offset), hdr.scope.run_id);
    }
}

test "each injected kind is denied for its own named reason" {
    const shape = Shape{};
    var scratch: [512]u8 = undefined;
    const cfg = fixtureConfig(.llm, shape, &scratch);
    const Expect = struct { kind: RequestKind, decision: u8 };
    // ModelDecision tags: 2 missing scope, 3 model not allowed, 6 output
    // limit, 8 live provider disabled. unknown_substitution passes the
    // validator (non-zero id); the tile denies it at fixture lookup.
    const table = [_]Expect{
        .{ .kind = .valid_replay, .decision = 1 },
        .{ .kind = .missing_budget, .decision = 2 },
        .{ .kind = .model_not_allowed, .decision = 3 },
        .{ .kind = .unknown_substitution, .decision = 1 },
        .{ .kind = .live_request, .decision = 8 },
        .{ .kind = .over_output_limit, .decision = 6 },
    };
    var body: [1024]u8 = undefined;
    for (table) |row| {
        var src = ModelRequestSource{};
        src.pattern[0] = row.kind;
        const hdr = buildAgentRequest(src, 0, &body);
        try std.testing.expect(tkmodl.requestWellFormed(&hdr.scope));
        try std.testing.expectEqual(row.decision, tkmodl.validate(&cfg, &hdr.scope, null));
    }
}

test "pattern selects kinds and tiers cyclically by offset" {
    var src = ModelRequestSource{ .pattern_len = 3 };
    src.pattern[0] = .valid_replay;
    src.pattern[1] = .missing_budget;
    src.pattern[2] = .live_request;
    src.tiers[1] = 9;
    try std.testing.expectEqual(RequestKind.valid_replay, src.kindAt(0));
    try std.testing.expectEqual(RequestKind.missing_budget, src.kindAt(1));
    try std.testing.expectEqual(RequestKind.live_request, src.kindAt(2));
    try std.testing.expectEqual(RequestKind.valid_replay, src.kindAt(3));
    try std.testing.expectEqual(default_tier, src.tierAt(0));
    try std.testing.expectEqual(@as(u8, 9), src.tierAt(1));
    try std.testing.expectEqual(@as(u8, 9), src.tierAt(4));
}

test "a classifier capture is the strict JSON the agent interprets; vectors are whole f32" {
    var buf: [256]u8 = undefined;
    const shape = Shape{ .response_bytes = 10 };
    const n = fillResponse(&buf, .classifier, 4, shape);
    try std.testing.expectEqualStrings("{\"confidence\":\"medium\",\"recommended_tier\":\"medium\"}", buf[0..n]);
    try std.testing.expectEqual(@as(usize, 12), fillResponse(&buf, .embedding, 0, shape));
    try std.testing.expectEqual(@as(usize, 10), fillResponse(&buf, .llm, 0, shape));
}

test "a prompt and a response can each exceed one fragment and the 16-bit fd size" {
    const big = Shape{ .prompt_bytes = 100_000, .response_bytes = 100_000 };
    try std.testing.expect(big.prompt_bytes > multipart.fd_sz_ceiling);
    try std.testing.expect(multipart.fragCount(big.prompt_bytes) > 1);
    try std.testing.expect(scratchBytes(big) >= big.response_bytes);
}

test "embedding governance: model and vector width are checked against the embedding allowlists" {
    const shape = Shape{ .response_bytes = 4096 }; // 1024 elements
    var scratch: [8192]u8 = undefined;
    const cfg = fixtureConfig(.embedding, shape, &scratch);
    var src = ModelRequestSource{ .shape = shape };
    src.tiers[0] = 5; // embedding
    var body: [1024]u8 = undefined;

    var hdr = buildAgentRequest(src, 0, &body);
    try std.testing.expectEqual(@as(u32, 1024), hdr.scope.embedding_dimensions);
    // ModelDecision tags: 1 allow_replay, 3 model not allowed, 10 embedding dimension.
    try std.testing.expectEqual(@as(u8, 1), tkmodl.validateEmbedding(&cfg, &hdr.scope, null));

    hdr.scope.embedding_dimensions = 1025;
    try std.testing.expectEqual(@as(u8, 10), tkmodl.validateEmbedding(&cfg, &hdr.scope, null));
    hdr.scope.embedding_dimensions = 0;
    try std.testing.expectEqual(@as(u8, 10), tkmodl.validateEmbedding(&cfg, &hdr.scope, null));

    hdr.scope.embedding_dimensions = 1024;
    @memset(&hdr.scope.model_id, 0);
    tkmodl.setField(&hdr.scope.model_id, other_model_id) catch unreachable;
    try std.testing.expectEqual(@as(u8, 3), tkmodl.validateEmbedding(&cfg, &hdr.scope, null));

    // The bad-width kind asks for a width the instance does not serve.
    src.pattern[0] = .bad_embedding_dimension;
    hdr = buildAgentRequest(src, 0, &body);
    try std.testing.expectEqual(@as(u32, 1025), hdr.scope.embedding_dimensions);
    try std.testing.expectEqual(@as(u8, 10), tkmodl.validateEmbedding(&cfg, &hdr.scope, null));
}

test "chat governance is unchanged by the embedding allowlists" {
    // The chat validator ignores the embedding allowlists and width entirely.
    var scratch: [512]u8 = undefined;
    var cfg = fixtureConfig(.llm, .{}, &scratch);
    cfg.allowed_embedding_model_count = 1;
    var src = ModelRequestSource{};
    var body: [1024]u8 = undefined;
    src.pattern[0] = .valid_replay;
    const hdr = buildAgentRequest(src, 0, &body);
    try std.testing.expectEqual(@as(u8, 1), tkmodl.validate(&cfg, &hdr.scope, null));
}

test "the prompt table holds exactly the prompts the requests reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const shape = Shape{ .fixtures = 3 };
    const table = try prompts(shape, arena.allocator());
    try std.testing.expectEqual(@as(usize, 3), table.len);
    var scratch: [256]u8 = undefined;
    var offset: u64 = 0;
    while (offset < 6) : (offset += 1) {
        const req = buildAgentRequest(.{ .shape = shape }, offset, &scratch);
        const p = table[@intCast(fixtureIndexAt(offset, shape))];
        try std.testing.expectEqual(multipart.messageHash(p), req.prompt_ref.prompt_hash);
        try std.testing.expectEqual(@as(u32, @intCast(p.len)), req.prompt_ref.prompt_len);
    }
}
