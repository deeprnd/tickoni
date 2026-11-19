//! Test-build synthetic model-request source for the tkmodl fixture/replay
//! topologies, and the fixture table it is paired with.
//!
//! The tkings process emits these records in place of payment events when its
//! config carries a `ModelRequestSource`. The same module builds the matching
//! tkmodl runtime configuration, so the request stream and the fixture table
//! share one definition: a "valid replay" request always resolves, and each
//! injected kind fails for exactly one named reason.
//!
//! Gated on `runtime.test_build.enabled` by the caller; this file carries no
//! gate of its own and has no effect unless a process is handed a source.
const std = @import("std");
const c_abi = @import("c_abi");

const tkmodl = c_abi.tkmodl;

pub const model_id = "fixture.model";
pub const other_model_id = "other.model";
pub const run_id: u64 = 1;
pub const fixture_count: u8 = 8;
pub const fixture_key_base: u64 = 1000;
/// A substitution id that is deliberately absent from the fixture table.
pub const unknown_substitution_id: u64 = 9999;
/// Hard limits applied by `runtimeConfig`. `over_output_limit` requests
/// exceed `hard_max_output_tokens` by one.
pub const hard_max_output_tokens: u32 = 1024;
pub const pattern_cap = 8;

/// What one synthetic request is built to trigger.
pub const RequestKind = enum(u8) {
    valid_replay,
    missing_budget,
    model_not_allowed,
    unknown_substitution,
    live_request,
    over_output_limit,
};

/// The request stream: `pattern[offset % pattern_len]` selects each kind.
pub const ModelRequestSource = struct {
    pattern: [pattern_cap]RequestKind = @splat(.valid_replay),
    pattern_len: u8 = 1,

    pub fn kindAt(self: ModelRequestSource, offset: u64) RequestKind {
        std.debug.assert(self.pattern_len > 0 and self.pattern_len <= pattern_cap);
        return self.pattern[@intCast(offset % self.pattern_len)];
    }
};

pub fn fixtureKey(i: u64) u64 {
    return fixture_key_base + i;
}

pub fn promptHash(i: u64) u64 {
    return 0x5052_4F4D_0000 + i * 17;
}

pub fn responseHash(i: u64) u64 {
    return 0x5245_5350_0000 + i * 31;
}

/// Captured result `i` of the shared fixture table.
pub fn fixtureEntry(i: u64) tkmodl.TkModlFixtureEntry {
    var e = std.mem.zeroes(tkmodl.TkModlFixtureEntry);
    e.key = fixtureKey(i);
    e.prompt_hash = promptHash(i);
    e.response_hash = responseHash(i);
    e.prompt_tokens = @intCast(100 + i);
    e.completion_tokens = @intCast(50 + i);
    e.total_tokens = e.prompt_tokens + e.completion_tokens;
    e.latency_ms = @intCast(10 + i);
    tkmodl.setField(&e.model_id, model_id) catch unreachable;
    return e;
}

/// The tkmodl runtime configuration paired with this source: `model_id`
/// allowlisted, a hard output limit, a live provider disabled, and
/// `fixture_count` captured results.
pub fn runtimeConfig() tkmodl.TkModlRuntimeConfig {
    var cfg = std.mem.zeroes(tkmodl.TkModlRuntimeConfig);
    cfg.magic = tkmodl.config_magic;
    cfg.version = tkmodl.config_version;
    cfg.hard_max_output_tokens = hard_max_output_tokens;
    cfg.allowed_model_count = 1;
    tkmodl.setField(&cfg.allowed_model_ids[0], model_id) catch unreachable;
    cfg.fixture_count = fixture_count;
    var i: u64 = 0;
    while (i < fixture_count) : (i += 1) cfg.fixtures[@intCast(i)] = fixtureEntry(i);
    return cfg;
}

/// Index of the fixture a `valid_replay` request at `offset` resolves to.
pub fn fixtureIndexAt(offset: u64) u64 {
    return offset % fixture_count;
}

/// Builds the request for stream `offset`. `request_id` is `offset + 1`, so a
/// result or audit record is correlated back to its offset.
pub fn buildRequest(source: ModelRequestSource, offset: u64) tkmodl.ModelRequestMsg {
    const kind = source.kindAt(offset);
    const i = fixtureIndexAt(offset);

    var m = std.mem.zeroes(tkmodl.ModelRequestMsg);
    m.version = tkmodl.wire_version;
    m.replay_mode = 1;
    m.retry_limit = 1;
    m.request_id = offset + 1;
    m.run_id = run_id;
    m.actor_id = 7;
    m.account_id = 42;
    m.policy_decision_id = 500 + offset;
    m.replay_substitution_id = fixtureKey(i);
    m.prompt_hash = promptHash(i);
    m.max_context_tokens = 2048;
    m.max_output_tokens = 512;
    m.timeout_ms = 30_000;
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
    }
    return m;
}

test "valid_replay requests resolve to a fixture with the same key, prompt and model" {
    const cfg = runtimeConfig();
    const src = ModelRequestSource{};
    var offset: u64 = 0;
    while (offset < 20) : (offset += 1) {
        const req = buildRequest(src, offset);
        try std.testing.expect(tkmodl.requestWellFormed(&req));
        try std.testing.expectEqual(@as(u8, 1), tkmodl.validate(&cfg, &req, null)); // MODEL_ALLOW_REPLAY
        const entry = cfg.fixtures[@intCast(fixtureIndexAt(offset))];
        try std.testing.expectEqual(entry.key, req.replay_substitution_id);
        try std.testing.expectEqual(entry.prompt_hash, req.prompt_hash);
    }
}

test "each injected kind is denied for its own named reason" {
    const cfg = runtimeConfig();
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
    for (table) |row| {
        var src = ModelRequestSource{};
        src.pattern[0] = row.kind;
        const req = buildRequest(src, 0);
        try std.testing.expect(tkmodl.requestWellFormed(&req));
        try std.testing.expectEqual(row.decision, tkmodl.validate(&cfg, &req, null));
    }
}

test "pattern selects kinds cyclically by offset" {
    var src = ModelRequestSource{ .pattern_len = 3 };
    src.pattern[0] = .valid_replay;
    src.pattern[1] = .missing_budget;
    src.pattern[2] = .live_request;
    try std.testing.expectEqual(RequestKind.valid_replay, src.kindAt(0));
    try std.testing.expectEqual(RequestKind.missing_budget, src.kindAt(1));
    try std.testing.expectEqual(RequestKind.live_request, src.kindAt(2));
    try std.testing.expectEqual(RequestKind.valid_replay, src.kindAt(3));
}
