const std = @import("std");
const schema = @import("model_messages");

pub const TkModlConfig = schema.TkModlConfig;
pub const TkModlDecision = schema.TkModlDecision;
pub const TkModlRequest = schema.TkModlRequest;
pub const ProviderRequest = schema.ProviderRequest;

pub fn validateTkModlRequest(config: TkModlConfig, req: TkModlRequest) TkModlDecision {
    // Required scope fields — checked before all else.
    if (req.model_id.len == 0) return .{ .deny_missing_scope = "model_id" };
    if (req.budget_id.len == 0) return .{ .deny_missing_scope = "budget_id" };
    if (req.policy_version.len == 0) return .{ .deny_missing_scope = "policy_version" };
    if (req.capability_envelope_id.len == 0) return .{ .deny_missing_scope = "capability_envelope_id" };
    if (req.capability.len == 0) return .{ .deny_missing_scope = "capability" };
    if (req.actor_role.len == 0) return .{ .deny_missing_scope = "actor_role" };
    if (req.workflow.len == 0) return .{ .deny_missing_scope = "workflow" };

    // Model allowlist. count == 0 means no restriction.
    if (config.allowed_model_id_count > 0) {
        var allowed = false;
        for (config.allowed_model_ids[0..config.allowed_model_id_count]) |id| {
            if (std.mem.eql(u8, req.model_id, id)) {
                allowed = true;
                break;
            }
        }
        if (!allowed) return .deny_model_not_allowed;
    }

    // Hard output-token limit. 0 means no enforcement.
    if (config.hard_max_output_tokens > 0 and req.max_output_tokens > config.hard_max_output_tokens)
        return .deny_output_limit;

    // Hard context-token limit. 0 means no enforcement.
    if (config.hard_max_context_tokens > 0 and req.max_context_tokens > config.hard_max_context_tokens)
        return .deny_context_limit;

    // Hard retry limit. 0 means no enforcement.
    if (config.hard_max_retry_count > 0 and req.retry_limit > config.hard_max_retry_count)
        return .deny_retry_limit;

    // Per-run budget: a single request cannot exceed the entire run token budget.
    // 0 means no enforcement.
    if (config.per_run_token_budget > 0 and req.max_output_tokens > config.per_run_token_budget)
        return .deny_budget_exhausted;

    // Live provider must be explicitly enabled for live-mode requests.
    if (req.replay_mode == .live and !config.live_provider_enabled)
        return .deny_live_provider_disabled;

    // Replay mode requires a non-zero substitution id.
    if (req.replay_mode == .replay and req.replay_substitution_id == 0)
        return .deny_replay_substitution_missing;

    return if (req.replay_mode == .replay) .allow_replay else .allow_live;
}

// Build the transport-layer ProviderRequest from a governed TkModlRequest.
// Only valid when decision is .allow_live; returns error.NotAllowLive otherwise.
// Slices in the returned ProviderRequest alias req — no allocation.
pub fn buildProviderRequest(decision: TkModlDecision, req: TkModlRequest) error{NotAllowLive}!ProviderRequest {
    if (decision != .allow_live) return error.NotAllowLive;
    return .{
        .model_id = req.model_id,
        .messages = req.messages,
        .sampling = req.sampling,
        .budget_id = req.budget_id,
        .policy_version = req.policy_version,
        .capability_envelope_id = req.capability_envelope_id,
    };
}

// ---------------------------------------------------------------------------
// Tests — one per decision tag plus coverage for each missing-scope field.
// ---------------------------------------------------------------------------

fn baseConfig() TkModlConfig {
    var c = TkModlConfig{
        .live_provider_enabled = true,
        .hard_max_output_tokens = 1024,
        .hard_max_context_tokens = 4096,
        .hard_max_retry_count = 3,
        .hard_timeout_ms = 30_000,
        .per_run_token_budget = 2048,
    };
    c.allowed_model_ids[0] = "test-model";
    c.allowed_model_id_count = 1;
    return c;
}

fn baseLiveReq() TkModlRequest {
    return .{
        .model_id = "test-model",
        .messages = &.{},
        .actor_role = "trading_ops_reviewer",
        .workflow = "trading_control",
        .capability = "trading_order.propose",
        .capability_envelope_id = "capenv.fixture",
        .policy_version = "v1",
        .budget_id = "budget.fixture",
        .max_output_tokens = 512,
        .max_context_tokens = 2048,
        .retry_limit = 1,
        .replay_mode = .live,
    };
}

test "validateTkModlRequest allow_live: valid live request passes" {
    const d = validateTkModlRequest(baseConfig(), baseLiveReq());
    try std.testing.expectEqual(TkModlDecision.allow_live, d);
}

test "validateTkModlRequest allow_replay: valid replay request with substitution_id passes" {
    var req = baseLiveReq();
    req.replay_mode = .replay;
    req.replay_substitution_id = 0xDEADBEEF;
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.allow_replay, d);
}

test "validateTkModlRequest deny_missing_scope: model_id" {
    var req = baseLiveReq();
    req.model_id = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("model_id", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: budget_id" {
    var req = baseLiveReq();
    req.budget_id = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("budget_id", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: policy_version" {
    var req = baseLiveReq();
    req.policy_version = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("policy_version", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: capability_envelope_id" {
    var req = baseLiveReq();
    req.capability_envelope_id = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("capability_envelope_id", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: capability" {
    var req = baseLiveReq();
    req.capability = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("capability", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: actor_role" {
    var req = baseLiveReq();
    req.actor_role = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("actor_role", d.deny_missing_scope);
}

test "validateTkModlRequest deny_missing_scope: workflow" {
    var req = baseLiveReq();
    req.workflow = "";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(std.meta.Tag(TkModlDecision).deny_missing_scope, std.meta.activeTag(d));
    try std.testing.expectEqualStrings("workflow", d.deny_missing_scope);
}

test "validateTkModlRequest deny_model_not_allowed: model absent from allowlist" {
    var req = baseLiveReq();
    req.model_id = "unknown-model";
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.deny_model_not_allowed, d);
}

test "validateTkModlRequest deny_model_not_allowed: empty allowlist allows any model" {
    var config = baseConfig();
    config.allowed_model_id_count = 0;
    var req = baseLiveReq();
    req.model_id = "any-model";
    const d = validateTkModlRequest(config, req);
    try std.testing.expectEqual(TkModlDecision.allow_live, d);
}

test "validateTkModlRequest deny_output_limit: max_output_tokens exceeds hard limit" {
    var req = baseLiveReq();
    req.max_output_tokens = 2048; // hard_max_output_tokens = 1024
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.deny_output_limit, d);
}

test "validateTkModlRequest deny_output_limit: zero hard limit means no enforcement" {
    var config = baseConfig();
    config.hard_max_output_tokens = 0;
    config.per_run_token_budget = 0; // also disable budget so only the hard limit is under test
    var req = baseLiveReq();
    req.max_output_tokens = 99_999;
    const d = validateTkModlRequest(config, req);
    try std.testing.expectEqual(TkModlDecision.allow_live, d);
}

test "validateTkModlRequest deny_context_limit: max_context_tokens exceeds hard limit" {
    var req = baseLiveReq();
    req.max_context_tokens = 8192; // hard_max_context_tokens = 4096
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.deny_context_limit, d);
}

test "validateTkModlRequest deny_retry_limit: retry_limit exceeds hard limit" {
    var req = baseLiveReq();
    req.retry_limit = 10; // hard_max_retry_count = 3
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.deny_retry_limit, d);
}

test "validateTkModlRequest deny_budget_exhausted: output tokens exceed per-run budget" {
    var config = baseConfig();
    config.hard_max_output_tokens = 0; // disable hard output limit
    config.per_run_token_budget = 200;
    var req = baseLiveReq();
    req.max_output_tokens = 512; // within hard limit (disabled) but exceeds budget of 200
    const d = validateTkModlRequest(config, req);
    try std.testing.expectEqual(TkModlDecision.deny_budget_exhausted, d);
}

test "validateTkModlRequest deny_live_provider_disabled: live request when provider is disabled" {
    var config = baseConfig();
    config.live_provider_enabled = false;
    const d = validateTkModlRequest(config, baseLiveReq());
    try std.testing.expectEqual(TkModlDecision.deny_live_provider_disabled, d);
}

test "validateTkModlRequest deny_live_provider_disabled: replay request succeeds when provider disabled" {
    var config = baseConfig();
    config.live_provider_enabled = false;
    var req = baseLiveReq();
    req.replay_mode = .replay;
    req.replay_substitution_id = 42;
    const d = validateTkModlRequest(config, req);
    try std.testing.expectEqual(TkModlDecision.allow_replay, d);
}

test "validateTkModlRequest deny_replay_substitution_missing: replay with zero substitution_id" {
    var req = baseLiveReq();
    req.replay_mode = .replay;
    req.replay_substitution_id = 0;
    const d = validateTkModlRequest(baseConfig(), req);
    try std.testing.expectEqual(TkModlDecision.deny_replay_substitution_missing, d);
}

// ---------------------------------------------------------------------------
// buildProviderRequest tests
// ---------------------------------------------------------------------------

test "buildProviderRequest: allow_live decision returns mapped ProviderRequest" {
    const req = baseLiveReq();
    const pr = try buildProviderRequest(.allow_live, req);
    try std.testing.expectEqualStrings("test-model", pr.model_id);
    try std.testing.expectEqualStrings("v1", pr.policy_version);
    try std.testing.expectEqualStrings("budget.fixture", pr.budget_id);
    try std.testing.expectEqualStrings("capenv.fixture", pr.capability_envelope_id);
    try std.testing.expectEqual(@as(usize, 0), pr.messages.len);
    try std.testing.expectEqual(@as(u32, 512), pr.sampling.max_output_tokens);
}

test "buildProviderRequest: allow_replay decision returns NotAllowLive" {
    const req = baseLiveReq();
    try std.testing.expectError(error.NotAllowLive, buildProviderRequest(.allow_replay, req));
}

test "buildProviderRequest: deny decision returns NotAllowLive" {
    const req = baseLiveReq();
    try std.testing.expectError(error.NotAllowLive, buildProviderRequest(.deny_model_not_allowed, req));
}

test "buildProviderRequest: deny_missing_scope returns NotAllowLive" {
    const req = baseLiveReq();
    try std.testing.expectError(error.NotAllowLive, buildProviderRequest(.{ .deny_missing_scope = "budget_id" }, req));
}
