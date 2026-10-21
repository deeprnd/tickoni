const std = @import("std");
const schema = @import("model_messages");
const validator = @import("validator.zig");
const backend_mod = @import("backend.zig");
const mock_model = @import("mock_model");

pub const TkModlResult = struct {
    outcome: schema.TkModlDecision,
    request_hash: u64,
    response_hash: u64,
    replay_substitution_id: u64,
    retry_count: u8,
    latency_ms: u64,
    token_usage: schema.TokenUsage,
    response: ?schema.ModelResponse,

    pub fn deinit(self: TkModlResult, allocator: std.mem.Allocator) void {
        if (self.response) |r| r.deinit(allocator);
    }
};

fn denyResult(decision: schema.TkModlDecision) TkModlResult {
    return .{
        .outcome = decision,
        .request_hash = 0,
        .response_hash = 0,
        .replay_substitution_id = 0,
        .retry_count = 0,
        .latency_ms = 0,
        .token_usage = .{ .prompt_tokens = 0, .completion_tokens = 0, .total_tokens = 0 },
        .response = null,
    };
}

pub fn runTkModlRequest(
    allocator: std.mem.Allocator,
    config: schema.TkModlConfig,
    backend: *backend_mod.Backend,
    req: schema.TkModlRequest,
) !TkModlResult {
    const decision = validator.validateTkModlRequest(config, req);

    switch (decision) {
        .allow_live => {
            // buildProviderRequest cannot return NotAllowLive here — decision is .allow_live.
            const provider_req = validator.buildProviderRequest(decision, req) catch unreachable;
            const request_hash = backend_mod.hashProviderRequest(provider_req);

            var attempt: u8 = 0;
            const response = retry: {
                while (attempt <= req.retry_limit) : (attempt += 1) {
                    const resp = backend.call(allocator, provider_req) catch |err| {
                        if (err == error.OutOfMemory) return err;
                        if (attempt < req.retry_limit) continue;
                        return err;
                    };
                    break :retry resp;
                }
                unreachable;
            };

            return .{
                .outcome = .allow_live,
                .request_hash = request_hash,
                .response_hash = backend_mod.hashResponseContent(response.content),
                .replay_substitution_id = 0,
                .retry_count = attempt,
                .latency_ms = response.latency_ms,
                .token_usage = response.token_usage,
                .response = response,
            };
        },
        .allow_replay => {
            const response = try backend.callById(allocator, req.replay_substitution_id);
            return .{
                .outcome = .allow_replay,
                .request_hash = 0,
                .response_hash = backend_mod.hashResponseContent(response.content),
                .replay_substitution_id = req.replay_substitution_id,
                .retry_count = 0,
                .latency_ms = response.latency_ms,
                .token_usage = response.token_usage,
                .response = response,
            };
        },
        else => return denyResult(decision),
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn baseConfig() schema.TkModlConfig {
    var c = schema.TkModlConfig{
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

fn baseLiveReq() schema.TkModlRequest {
    return .{
        .model_id = "test-model",
        .messages = &.{},
        .actor_role = "ops_reviewer",
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

test "runTkModlRequest allow_live: mock backend returns populated result" {
    const allocator = std.testing.allocator;
    var mock = mock_model.MockBackend{ .canned_content = "{\"ok\":true}", .canned_model_id = "test-model" };
    var backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock);

    const result = try runTkModlRequest(allocator, baseConfig(), &backend, baseLiveReq());
    defer result.deinit(allocator);

    try std.testing.expectEqual(schema.TkModlDecision.allow_live, result.outcome);
    try std.testing.expect(result.request_hash != 0);
    try std.testing.expect(result.response_hash != 0);
    try std.testing.expectEqual(@as(u64, 0), result.replay_substitution_id);
    try std.testing.expectEqual(@as(u8, 0), result.retry_count);
    try std.testing.expect(result.response != null);
    try std.testing.expectEqualStrings("{\"ok\":true}", result.response.?.content);
}

test "runTkModlRequest deny: governance failure returns deny result with no response" {
    const allocator = std.testing.allocator;
    var mock = mock_model.MockBackend{ .canned_content = "x" };
    var backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock);

    var req = baseLiveReq();
    req.model_id = "unknown-model"; // not on allowlist

    const result = try runTkModlRequest(allocator, baseConfig(), &backend, req);
    defer result.deinit(allocator);

    try std.testing.expectEqual(schema.TkModlDecision.deny_model_not_allowed, result.outcome);
    try std.testing.expectEqual(@as(u64, 0), result.request_hash);
    try std.testing.expectEqual(@as(u64, 0), result.response_hash);
    try std.testing.expect(result.response == null);
}

test "runTkModlRequest deny_missing_scope: empty budget_id" {
    const allocator = std.testing.allocator;
    var mock = mock_model.MockBackend{ .canned_content = "x" };
    var backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock);

    var req = baseLiveReq();
    req.budget_id = "";

    const result = try runTkModlRequest(allocator, baseConfig(), &backend, req);
    defer result.deinit(allocator);

    try std.testing.expectEqual(std.meta.Tag(schema.TkModlDecision).deny_missing_scope, std.meta.activeTag(result.outcome));
    try std.testing.expect(result.response == null);
}

test "runTkModlRequest allow_replay: calls ReplayBackend.callById" {
    const allocator = std.testing.allocator;

    var rb = backend_mod.ReplayBackend{};
    rb.entries[0] = blk: {
        var e = backend_mod.ReplayEntry{};
        e.substitution_id = 42;
        const content = "{\"ticker\":\"NVDA\"}";
        e.content_len = @intCast(content.len);
        @memcpy(e.content[0..content.len], content);
        const mid = "replay-model";
        e.model_id_len = mid.len;
        @memcpy(e.model_id[0..mid.len], mid);
        const fr = "stop";
        e.finish_reason_len = fr.len;
        @memcpy(e.finish_reason[0..fr.len], fr);
        e.latency_ms = 10;
        e.token_usage = .{ .prompt_tokens = 5, .completion_tokens = 5, .total_tokens = 10 };
        break :blk e;
    };
    rb.entry_count = 1;

    var backend = rb.asBackend();

    var req = baseLiveReq();
    req.replay_mode = .replay;
    req.replay_substitution_id = 42;

    const result = try runTkModlRequest(allocator, baseConfig(), &backend, req);
    defer result.deinit(allocator);

    try std.testing.expectEqual(schema.TkModlDecision.allow_replay, result.outcome);
    try std.testing.expectEqual(@as(u64, 42), result.replay_substitution_id);
    try std.testing.expectEqual(@as(u8, 0), result.retry_count);
    try std.testing.expectEqual(@as(u64, 10), result.latency_ms);
    try std.testing.expect(result.response != null);
    try std.testing.expectEqualStrings("{\"ticker\":\"NVDA\"}", result.response.?.content);
}

test "runTkModlRequest replay: wrong backend returns ReplayBackendRequired" {
    const allocator = std.testing.allocator;
    var mock = mock_model.MockBackend{ .canned_content = "x" };
    var backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock);

    var req = baseLiveReq();
    req.replay_mode = .replay;
    req.replay_substitution_id = 1;

    try std.testing.expectError(error.ReplayBackendRequired, runTkModlRequest(allocator, baseConfig(), &backend, req));
}

test "runTkModlRequest allow_live: response_hash is deterministic" {
    const allocator = std.testing.allocator;
    var mock = mock_model.MockBackend{ .canned_content = "same content" };
    var backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock);

    const r1 = try runTkModlRequest(allocator, baseConfig(), &backend, baseLiveReq());
    defer r1.deinit(allocator);
    const r2 = try runTkModlRequest(allocator, baseConfig(), &backend, baseLiveReq());
    defer r2.deinit(allocator);

    try std.testing.expectEqual(r1.response_hash, r2.response_hash);
    try std.testing.expectEqual(r1.request_hash, r2.request_hash);
}

test "TkModlResult.deinit: deny result with null response is safe" {
    const result = denyResult(.deny_model_not_allowed);
    result.deinit(std.testing.allocator); // must not crash
}

test "Backend.callById: non-replay backend returns ReplayBackendRequired" {
    var mock_backend = mock_model.MockBackend{ .canned_content = "x" };
    const backend = mock_model.MockBackend.asBackend(backend_mod.Backend, &mock_backend);
    try std.testing.expectError(error.ReplayBackendRequired, backend.callById(std.testing.allocator, 1));
}
