//! Zig-owned agent decisions for the tkagnt process tile: which model tier
//! serves a request, and what a returned model result means.
//!
//! The C fd_stem tile does bounded transport and correlation only; it applies
//! these decisions through the two hooks in `hooks` (tk_agent_hooks.h, the one
//! approved C->Zig call path). Every function here is pure over plain
//! fixed-size data: no allocator, no I/O, no clock, no publishing. The same
//! query always yields the same directive, which is what keeps replay
//! deterministic and keeps agent policy out of the C shim.
//!
//! One request, one model dispatch, one result. There is no cascade: the
//! topology defines which tiers exist and a request names the tier it needs
//! (owner decision, tkagnt fd_stem migration plan). A classifier result with
//! low confidence is reported as it is; nothing here dispatches a follow-up or
//! substitutes a tier the model did not recommend.

const std = @import("std");
const runtime = @import("runtime");
const audit_mod = @import("audit_mod");

const Tier = runtime.model_tier.TkAgntModelTier;

pub const RouteQuery = audit_mod.TkAgentRouteQuery;
pub const RouteDirective = audit_mod.TkAgentRouteDirective;
pub const InterpretQuery = audit_mod.TkAgentInterpretQuery;
pub const InterpretDirective = audit_mod.TkAgentInterpretDirective;
pub const Hooks = audit_mod.TkAgentHooks;

/// A classifier answers with a tiny structured object; anything larger is not
/// a classifier result.
pub const max_classifier_content_bytes: usize = 4096;

const tier_none: u8 = audit_mod.TK_AGENT_TIER_NONE;
const req_chat: u8 = audit_mod.TK_AGENT_REQ_CHAT;
const req_embedding: u8 = audit_mod.TK_AGENT_REQ_EMBEDDING;
const route_dispatch: u8 = audit_mod.TK_AGENT_ROUTE_DISPATCH;
const route_deny_absent: u8 = audit_mod.TK_AGENT_ROUTE_DENY_ABSENT_TIER;
const route_deny_invalid: u8 = audit_mod.TK_AGENT_ROUTE_DENY_INVALID;
const act_final: u8 = audit_mod.TK_AGENT_ACT_FINAL;
const act_fail: u8 = audit_mod.TK_AGENT_ACT_FAIL;
const why_none: u8 = audit_mod.TK_AGENT_WHY_NONE;
const why_model_denied: u8 = audit_mod.TK_AGENT_WHY_MODEL_DENIED;
const why_invalid_content: u8 = audit_mod.TK_AGENT_WHY_INVALID_CONTENT;
const why_invalid_tier: u8 = audit_mod.TK_AGENT_WHY_INVALID_TIER;
const why_too_large: u8 = audit_mod.TK_AGENT_WHY_CONTENT_TOO_LARGE;
const model_allow_live: u8 = audit_mod.MODEL_ALLOW_LIVE;
const model_allow_replay: u8 = audit_mod.MODEL_ALLOW_REPLAY;

const Confidence = enum(u8) {
    low = audit_mod.TK_AGENT_CONF_LOW,
    medium = audit_mod.TK_AGENT_CONF_MEDIUM,
    high = audit_mod.TK_AGENT_CONF_HIGH,
};

fn isConfigured(configured_mask: u16, tier: Tier) bool {
    const shift: u4 = @intCast(@backingInt(tier));
    return (configured_mask >> shift) & 1 == 1;
}

/// Validates the tier a request names and dispatches there. A chat request must
/// name a chat tier; an embedding request goes to the embedding tier (naming it
/// is optional, naming any other is contradictory). A tier that is not
/// configured is an explicit denial: the request is never rerouted to a
/// different model.
pub fn route(q: RouteQuery) RouteDirective {
    var d = std.mem.zeroes(RouteDirective);
    d.verdict = route_deny_invalid;
    d.tier = tier_none;

    const requested: ?Tier = if (q.requested_tier == tier_none)
        null
    else
        Tier.fromInt(q.requested_tier) orelse return d;

    const tier: Tier = switch (q.request_type) {
        req_embedding => blk: {
            if (requested) |r| if (r != .embedding) return d;
            break :blk .embedding;
        },
        req_chat => blk: {
            const r = requested orelse return d;
            if (r == .embedding) return d;
            break :blk r;
        },
        else => return d,
    };

    d.tier = @backingInt(tier);
    if (!isConfigured(q.configured_mask, tier)) {
        d.verdict = route_deny_absent;
        return d;
    }
    d.verdict = route_dispatch;
    return d;
}

const Parsed = struct { confidence: Confidence, recommended: Tier };

/// Minimal, allocation-free reader for exactly
/// `{"confidence":"low|medium|high","recommended_tier":"<tier>"}` (either key
/// order, JSON whitespace allowed). Anything else is rejected: unknown or
/// duplicate keys, escapes, non-string values, trailing bytes.
const Reader = struct {
    s: []const u8,
    i: usize = 0,

    fn skipSpace(self: *Reader) void {
        while (self.i < self.s.len and (self.s[self.i] == ' ' or self.s[self.i] == '\t' or
            self.s[self.i] == '\n' or self.s[self.i] == '\r')) self.i += 1;
    }

    fn eat(self: *Reader, c: u8) bool {
        self.skipSpace();
        if (self.i < self.s.len and self.s[self.i] == c) {
            self.i += 1;
            return true;
        }
        return false;
    }

    /// A plain string: printable ASCII, no escapes.
    fn string(self: *Reader) ?[]const u8 {
        if (!self.eat('"')) return null;
        const start = self.i;
        while (self.i < self.s.len) : (self.i += 1) {
            const c = self.s[self.i];
            if (c == '"') {
                const out = self.s[start..self.i];
                self.i += 1;
                return out;
            }
            if (c == '\\' or c < 0x20 or c > 0x7e) return null;
        }
        return null;
    }

    fn atEnd(self: *Reader) bool {
        self.skipSpace();
        return self.i == self.s.len;
    }
};

fn tierFromName(name: []const u8) ?Tier {
    for (0..Tier.count) |i| {
        const t: Tier = @fromBackingInt(@intCast(i));
        if (std.mem.eql(u8, t.name(), name)) return t;
    }
    return null;
}

fn parseClassifier(content: []const u8) error{ InvalidContent, InvalidTier }!Parsed {
    var r = Reader{ .s = content };
    if (!r.eat('{')) return error.InvalidContent;

    var confidence: ?Confidence = null;
    var recommended: ?Tier = null;
    var pairs: usize = 0;
    while (true) {
        const key = r.string() orelse return error.InvalidContent;
        if (!r.eat(':')) return error.InvalidContent;
        const value = r.string() orelse return error.InvalidContent;
        if (std.mem.eql(u8, key, "confidence")) {
            if (confidence != null) return error.InvalidContent;
            confidence = if (std.mem.eql(u8, value, "low"))
                .low
            else if (std.mem.eql(u8, value, "medium"))
                .medium
            else if (std.mem.eql(u8, value, "high"))
                .high
            else
                return error.InvalidContent;
        } else if (std.mem.eql(u8, key, "recommended_tier")) {
            if (recommended != null) return error.InvalidContent;
            const t = tierFromName(value) orelse return error.InvalidTier;
            // A classifier recommends a chat tier; embedding is not one.
            if (t.isEmbedding()) return error.InvalidTier;
            recommended = t;
        } else return error.InvalidContent;
        pairs += 1;
        if (r.eat(',')) continue;
        if (r.eat('}')) break;
        return error.InvalidContent;
    }
    if (!r.atEnd() or pairs != 2) return error.InvalidContent;
    return .{
        .confidence = confidence orelse return error.InvalidContent,
        .recommended = recommended orelse return error.InvalidContent,
    };
}

fn failure(why: u8) InterpretDirective {
    var d = std.mem.zeroes(InterpretDirective);
    d.action = act_fail;
    d.why = why;
    d.recommended_tier = tier_none;
    return d;
}

/// Decides what a returned model result means. The run always ends with this
/// one result: either FINAL (carrying, for a classifier, the model's own
/// `confidence` and `recommended_tier`) or a terminal FAIL with the reason.
pub fn interpret(q: InterpretQuery) InterpretDirective {
    if (q.model_decision != model_allow_live and q.model_decision != model_allow_replay)
        return failure(why_model_denied);

    var d = std.mem.zeroes(InterpretDirective);
    d.action = act_final;
    d.why = why_none;
    d.recommended_tier = tier_none;

    switch (q.request_type) {
        req_embedding => {
            // Vector bytes: whole f32 elements, at least one.
            if (q.content_len == 0 or q.content_len % 4 != 0) return failure(why_invalid_content);
            return d;
        },
        req_chat => {},
        else => return failure(why_invalid_content),
    }

    const source = Tier.fromInt(q.source_tier) orelse return failure(why_invalid_tier);
    // Content from a non-classifier tier is the answer itself; the agent does
    // not parse it here.
    if (!source.isClassifier()) return d;

    if (q.content_len > max_classifier_content_bytes) return failure(why_too_large);
    if (q.content_len == 0 or q.content == null) return failure(why_invalid_content);
    const parsed = parseClassifier(q.content[0..q.content_len]) catch |e| return switch (e) {
        error.InvalidContent => failure(why_invalid_content),
        error.InvalidTier => failure(why_invalid_tier),
    };

    d.confidence = @backingInt(parsed.confidence);
    d.recommended_tier = @backingInt(parsed.recommended);
    return d;
}

fn routeC(q: [*c]const RouteQuery) callconv(.c) RouteDirective {
    if (q == null) {
        var d = std.mem.zeroes(RouteDirective);
        d.verdict = route_deny_invalid;
        d.tier = tier_none;
        return d;
    }
    return route(q.*);
}

fn interpretC(q: [*c]const InterpretQuery) callconv(.c) InterpretDirective {
    if (q == null) return failure(why_invalid_content);
    return interpret(q.*);
}

/// The function-pointer table the Zig child registers into the C stem.
pub const hooks: Hooks = .{ .route = routeC, .interpret = interpretC };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn maskOf(tiers: []const Tier) u16 {
    var m: u16 = 0;
    for (tiers) |t| m |= @as(u16, 1) << @as(u4, @intCast(@backingInt(t)));
    return m;
}

const all_tiers = blk: {
    var m: u16 = 0;
    for (0..Tier.count) |i| m |= @as(u16, 1) << @as(u4, @intCast(i));
    break :blk m;
};

fn routeQ(configured: u16, request_type: u8, requested: ?Tier) RouteQuery {
    var q = std.mem.zeroes(RouteQuery);
    q.configured_mask = configured;
    q.request_type = request_type;
    q.requested_tier = if (requested) |t| @backingInt(t) else tier_none;
    return q;
}

fn interpQ(source: Tier, content: []const u8) InterpretQuery {
    var q = std.mem.zeroes(InterpretQuery);
    q.content = content.ptr;
    q.content_len = @intCast(content.len);
    q.request_type = req_chat;
    q.source_tier = @backingInt(source);
    q.model_decision = model_allow_replay;
    return q;
}

test "route: a chat request is dispatched to the tier it names when configured" {
    for (0..Tier.count) |i| {
        const t: Tier = @fromBackingInt(@intCast(i));
        if (t.isEmbedding()) continue;
        const d = route(routeQ(all_tiers, req_chat, t));
        try std.testing.expectEqual(route_dispatch, d.verdict);
        try std.testing.expectEqual(@as(u8, @backingInt(t)), d.tier);
    }
}

test "route: a chat request that names no tier is invalid, never defaulted" {
    // The topology defines which tiers exist and the request names one; there
    // is no implicit start tier.
    const d = route(routeQ(all_tiers, req_chat, null));
    try std.testing.expectEqual(route_deny_invalid, d.verdict);
    try std.testing.expectEqual(tier_none, d.tier);
}

test "route: an embedding request goes to the embedding tier only" {
    var d = route(routeQ(all_tiers, req_embedding, null));
    try std.testing.expectEqual(route_dispatch, d.verdict);
    try std.testing.expectEqual(@as(u8, @backingInt(Tier.embedding)), d.tier);
    d = route(routeQ(all_tiers, req_embedding, .embedding));
    try std.testing.expectEqual(route_dispatch, d.verdict);
    // Naming a chat tier for an embedding request, or the embedding tier for
    // chat, is contradictory.
    try std.testing.expectEqual(route_deny_invalid, route(routeQ(all_tiers, req_embedding, .low)).verdict);
    try std.testing.expectEqual(route_deny_invalid, route(routeQ(all_tiers, req_chat, .embedding)).verdict);
}

test "route: an absent tier is denied explicitly, never rerouted" {
    // Only `low` is configured; a request for `high` or for embedding must be
    // denied, not sent to `low`.
    const only_low = maskOf(&.{.low});
    var d = route(routeQ(only_low, req_chat, .high));
    try std.testing.expectEqual(route_deny_absent, d.verdict);
    try std.testing.expectEqual(@as(u8, @backingInt(Tier.high)), d.tier);
    d = route(routeQ(only_low, req_embedding, null));
    try std.testing.expectEqual(route_deny_absent, d.verdict);
    try std.testing.expectEqual(@as(u8, @backingInt(Tier.embedding)), d.tier);
    // The configured tier still works, and nothing configured denies everything.
    try std.testing.expectEqual(route_dispatch, route(routeQ(only_low, req_chat, .low)).verdict);
    try std.testing.expectEqual(route_deny_absent, route(routeQ(0, req_chat, .low)).verdict);
}

test "route: a sparse topology serves exactly its configured tiers" {
    // classifier_fast + embedding + max, as a topology might configure them.
    const cfg = maskOf(&.{ .classifier_fast, .embedding, .max });
    try std.testing.expectEqual(route_dispatch, route(routeQ(cfg, req_chat, .classifier_fast)).verdict);
    try std.testing.expectEqual(route_dispatch, route(routeQ(cfg, req_chat, .max)).verdict);
    try std.testing.expectEqual(route_dispatch, route(routeQ(cfg, req_embedding, null)).verdict);
    for ([_]Tier{ .classifier_complex, .classifier_escalation, .classifier_hosted, .classifier_hosted_newer, .low, .medium, .high, .@"extra-high" }) |t| {
        try std.testing.expectEqual(route_deny_absent, route(routeQ(cfg, req_chat, t)).verdict);
    }
}

test "route: malformed requests are denied as invalid" {
    var q = routeQ(all_tiers, 0, .low);
    try std.testing.expectEqual(route_deny_invalid, route(q).verdict);
    q = routeQ(all_tiers, 9, .low);
    try std.testing.expectEqual(route_deny_invalid, route(q).verdict);
    q = routeQ(all_tiers, req_chat, .low);
    q.requested_tier = Tier.count; // out of range, not "none"
    try std.testing.expectEqual(route_deny_invalid, route(q).verdict);
    q.requested_tier = 200;
    try std.testing.expectEqual(route_deny_invalid, route(q).verdict);
}

test "interpret: a classifier result is final and reports the model's own confidence and recommendation" {
    inline for (.{
        .{ "{\"confidence\":\"high\",\"recommended_tier\":\"medium\"}", Confidence.high, Tier.medium },
        .{ "{\"confidence\":\"medium\",\"recommended_tier\":\"max\"}", Confidence.medium, Tier.max },
        .{ "{\"confidence\":\"low\",\"recommended_tier\":\"classifier_hosted_newer\"}", Confidence.low, Tier.classifier_hosted_newer },
    }) |c| {
        const d = interpret(interpQ(.classifier_fast, c[0]));
        try std.testing.expectEqual(act_final, d.action);
        try std.testing.expectEqual(@as(u8, @backingInt(c[1])), d.confidence);
        try std.testing.expectEqual(@as(u8, @backingInt(c[2])), d.recommended_tier);
    }
}

test "interpret: low confidence is reported as it is; nothing is escalated or substituted" {
    // The result ends the run for every classifier tier. The interpretation
    // has no field that could ask for another dispatch.
    const low = "{\"confidence\":\"low\",\"recommended_tier\":\"low\"}";
    for ([_]Tier{ .classifier_fast, .classifier_complex, .classifier_escalation, .classifier_hosted, .classifier_hosted_newer }) |t| {
        const d = interpret(interpQ(t, low));
        try std.testing.expectEqual(act_final, d.action);
        try std.testing.expectEqual(why_none, d.why);
        try std.testing.expectEqual(@as(u8, @backingInt(Confidence.low)), d.confidence);
        try std.testing.expectEqual(@as(u8, @backingInt(Tier.low)), d.recommended_tier);
    }
}

test "interpret: reordered keys and whitespace are accepted" {
    const d = interpret(interpQ(.classifier_fast, " {\n \"recommended_tier\" : \"max\" ,\t\"confidence\":\"medium\" } \n"));
    try std.testing.expectEqual(act_final, d.action);
    try std.testing.expectEqual(@as(u8, @backingInt(Tier.max)), d.recommended_tier);
    try std.testing.expectEqual(@as(u8, @backingInt(Confidence.medium)), d.confidence);
}

test "interpret: malformed classifier content fails closed" {
    const bad = [_][]const u8{
        "",
        "not json",
        "{}",
        "{\"confidence\":\"high\"}",
        "{\"recommended_tier\":\"low\"}",
        "{\"confidence\":\"high\",\"recommended_tier\":\"low\",\"extra\":\"x\"}",
        "{\"confidence\":\"high\",\"confidence\":\"low\",\"recommended_tier\":\"low\"}",
        "{\"confidence\":\"certain\",\"recommended_tier\":\"low\"}",
        "{\"confidence\":high,\"recommended_tier\":\"low\"}",
        "{\"confidence\":\"hi\\u0067h\",\"recommended_tier\":\"low\"}",
        "{\"confidence\":\"high\",\"recommended_tier\":\"low\"} trailing",
        "{\"confidence\":\"high\",\"recommended_tier\":\"low\"",
        "[\"confidence\",\"high\"]",
    };
    for (bad) |content| {
        const d = interpret(interpQ(.classifier_fast, content));
        if (d.action != act_fail) std.debug.print("accepted: {s}\n", .{content});
        try std.testing.expectEqual(act_fail, d.action);
        try std.testing.expectEqual(why_invalid_content, d.why);
    }
}

test "interpret: an unknown or non-chat recommended tier is an invalid tier" {
    for ([_][]const u8{
        "{\"confidence\":\"high\",\"recommended_tier\":\"gpt-9\"}",
        "{\"confidence\":\"high\",\"recommended_tier\":\"embedding\"}",
        "{\"confidence\":\"high\",\"recommended_tier\":\"\"}",
    }) |content| {
        const d = interpret(interpQ(.classifier_fast, content));
        try std.testing.expectEqual(act_fail, d.action);
        try std.testing.expectEqual(why_invalid_tier, d.why);
    }
}

test "interpret: oversize classifier content is rejected before parsing" {
    var big: [max_classifier_content_bytes + 1]u8 = undefined;
    @memset(&big, ' ');
    const d = interpret(interpQ(.classifier_fast, &big));
    try std.testing.expectEqual(act_fail, d.action);
    try std.testing.expectEqual(why_too_large, d.why);
}

test "interpret: a denied model call is a terminal failure" {
    var q = interpQ(.low, "answer");
    q.model_decision = audit_mod.MODEL_DENY_MODEL_NOT_ALLOWED;
    const d = interpret(q);
    try std.testing.expectEqual(act_fail, d.action);
    try std.testing.expectEqual(why_model_denied, d.why);
}

test "interpret: content from an LLM tier is the answer and is not parsed" {
    const d = interpret(interpQ(.high, "free text, not json"));
    try std.testing.expectEqual(act_final, d.action);
    try std.testing.expectEqual(@as(u8, 0), d.confidence);
    try std.testing.expectEqual(tier_none, d.recommended_tier);
}

test "interpret: embedding vectors must be whole f32 elements" {
    var q = interpQ(.embedding, "0123456789ab");
    q.request_type = req_embedding;
    try std.testing.expectEqual(act_final, interpret(q).action); // 12 bytes = 3 floats
    q.content_len = 11;
    try std.testing.expectEqual(act_fail, interpret(q).action);
    q.content_len = 0;
    try std.testing.expectEqual(act_fail, interpret(q).action);
}

test "interpret: an unknown source tier or request type fails closed" {
    var q = interpQ(.low, "x");
    q.source_tier = 200;
    try std.testing.expectEqual(why_invalid_tier, interpret(q).why);
    q = interpQ(.low, "x");
    q.request_type = 0;
    try std.testing.expectEqual(why_invalid_content, interpret(q).why);
}

test "decisions are deterministic: the same query always yields the same directive" {
    const q = interpQ(.classifier_complex, "{\"confidence\":\"low\",\"recommended_tier\":\"high\"}");
    const a = interpret(q);
    const b = interpret(q);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
    const r = routeQ(all_tiers, req_chat, .max);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&route(r)), std.mem.asBytes(&route(r)));
}

test "the C hook table dispatches to the same decisions and tolerates a null query" {
    const route_fn = hooks.route.?;
    const interpret_fn = hooks.interpret.?;

    const rq = routeQ(all_tiers, req_chat, .low);
    const rd = route_fn(&rq);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&route(rq)), std.mem.asBytes(&rd));

    const iq = interpQ(.classifier_fast, "{\"confidence\":\"high\",\"recommended_tier\":\"low\"}");
    const id = interpret_fn(&iq);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&interpret(iq)), std.mem.asBytes(&id));

    try std.testing.expectEqual(route_deny_invalid, route_fn(null).verdict);
    try std.testing.expectEqual(act_fail, interpret_fn(null).action);
}

test "hooks and decisions carry no direct adapter, model, or paper-order authority" {
    // The decision surface takes and returns plain data only: no allocator,
    // backend, or callback parameters (contrast runInvestmentAgent).
    inline for (.{ route, interpret }) |f| {
        const info = @typeInfo(@TypeOf(f)).@"fn";
        inline for (info.param_types) |maybe_t| {
            const T = maybe_t.?;
            try std.testing.expect(T == RouteQuery or T == InterpretQuery);
        }
    }
}
