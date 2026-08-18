const std = @import("std");

pub const SamplingParams = struct {
    temperature: f32 = 0,
    top_p: f32 = 1.0,
    max_output_tokens: u32 = 512,
    seed: u64 = 42,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const ProviderRequest = struct {
    model_id: []const u8,
    messages: []const Message,
    sampling: SamplingParams = .{},
    budget_id: []const u8 = "",
    policy_version: []const u8 = "",
    capability_envelope_id: []const u8 = "",
};

pub const ReplayMode = enum(u8) {
    live,
    replay,
};

pub const TkModlRequest = struct {
    request_id: u64 = 0,
    run_id: u64 = 0,
    actor_id: u64 = 0,
    actor_role: []const u8 = "",
    workflow: []const u8 = "",
    account_id: u64 = 0,
    capability: []const u8 = "",
    capability_envelope_id: []const u8 = "",
    policy_version: []const u8 = "",
    policy_decision_id: u64 = 0,
    budget_id: []const u8 = "",
    model_id: []const u8,
    messages: []const Message,
    sampling: SamplingParams = .{},
    max_context_tokens: u32 = 0,
    max_output_tokens: u32 = 512,
    retry_limit: u8 = 1,
    timeout_ms: u32 = 0,
    replay_mode: ReplayMode = .live,
    replay_substitution_id: u64 = 0,
};

pub const max_allowed_model_ids: usize = 16;

pub const TkModlConfig = struct {
    allowed_model_ids: [max_allowed_model_ids][]const u8 = undefined,
    allowed_model_id_count: u8 = 0,
    live_provider_enabled: bool = false,
    hard_max_context_tokens: u32 = 0,
    hard_max_output_tokens: u32 = 0,
    hard_max_retry_count: u8 = 0,
    hard_timeout_ms: u32 = 0,
    per_run_token_budget: u32 = 0,
    provider_endpoint: [256]u8 = std.mem.zeroes([256]u8),
};

pub const TkModlDecision = union(enum) {
    allow_live,
    allow_replay,
    deny_missing_scope: []const u8,
    deny_model_not_allowed,
    deny_budget_exhausted,
    deny_context_limit,
    deny_output_limit,
    deny_retry_limit,
    deny_live_provider_disabled,
    deny_replay_substitution_missing,
};

pub const TokenUsage = struct {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
};

// Caller owns all slice fields; call deinit(allocator) when done.
pub const ModelResponse = struct {
    model_id: []const u8,
    content: []const u8,
    finish_reason: []const u8,
    token_usage: TokenUsage,
    latency_ms: u64,

    pub fn deinit(self: ModelResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.model_id);
        allocator.free(self.content);
        allocator.free(self.finish_reason);
    }
};

test "TkModlRequest required fields compile and replay_mode defaults to live" {
    const req = TkModlRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
    };
    try std.testing.expectEqualStrings("fixture.ai_infra", req.model_id);
    try std.testing.expectEqual(ReplayMode.live, req.replay_mode);
    try std.testing.expectEqual(@as(u8, 1), req.retry_limit);
    try std.testing.expectEqual(@as(u32, 512), req.max_output_tokens);
}

test "ModelResponse deinit frees all fields" {
    const allocator = std.testing.allocator;
    const resp = ModelResponse{
        .model_id = try allocator.dupe(u8, "test-model"),
        .content = try allocator.dupe(u8, "hello"),
        .finish_reason = try allocator.dupe(u8, "stop"),
        .token_usage = .{ .prompt_tokens = 10, .completion_tokens = 5, .total_tokens = 15 },
        .latency_ms = 100,
    };
    resp.deinit(allocator);
}
