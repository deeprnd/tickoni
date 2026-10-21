const std = @import("std");
const model_messages = @import("model_messages");

const ProviderRequest = model_messages.ProviderRequest;
const ModelResponse = model_messages.ModelResponse;

// MockBackend returns a pre-set canned response. Used in unit tests.
pub const MockBackend = struct {
    pub const CallTrace = struct {
        call_count: usize = 0,
        last_model_id: []const u8 = "",
        last_budget_id: []const u8 = "",
        last_policy_version: []const u8 = "",
        last_capability_envelope_id: []const u8 = "",
    };

    canned_content: []const u8,
    canned_model_id: []const u8 = "mock",
    canned_finish_reason: []const u8 = "stop",
    trace: ?*CallTrace = null,

    pub fn call(self: MockBackend, allocator: std.mem.Allocator, req: ProviderRequest) error{OutOfMemory}!ModelResponse {
        if (self.trace) |trace| {
            trace.call_count += 1;
            trace.last_model_id = req.model_id;
            trace.last_budget_id = req.budget_id;
            trace.last_policy_version = req.policy_version;
            trace.last_capability_envelope_id = req.capability_envelope_id;
        }
        return .{
            .model_id = try allocator.dupe(u8, self.canned_model_id),
            .content = try allocator.dupe(u8, self.canned_content),
            .finish_reason = try allocator.dupe(u8, self.canned_finish_reason),
            .token_usage = .{ .prompt_tokens = 0, .completion_tokens = 0, .total_tokens = 0 },
            .latency_ms = 0,
        };
    }

    /// Builds `BackendType` (production tiles' model.Backend vtable
    /// interface) from this mock, via BackendType's own `from()`
    /// constructor. Generic over BackendType instead of importing model's
    /// Backend type directly, so this test double never pulls a specific
    /// production module instance into its own module graph.
    pub fn asBackend(comptime BackendType: type, self: *MockBackend) BackendType {
        return BackendType.from(MockBackend, true, self);
    }
};

test "MockBackend returns canned response" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{
        .canned_content = "test response",
        .canned_model_id = "mock-v1",
    };
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("test response", resp.content);
    try std.testing.expectEqualStrings("mock-v1", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
    try std.testing.expectEqual(@as(u64, 0), resp.latency_ms);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.total_tokens);
}

test "MockBackend default model_id and finish_reason" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "hello" };
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("mock", resp.model_id);
    try std.testing.expectEqualStrings("stop", resp.finish_reason);
}

test "MockBackend is deterministic across calls" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "deterministic output" };
    const req = ProviderRequest{ .model_id = "x", .messages = &.{} };

    const r1 = try mock.call(allocator, req);
    defer r1.deinit(allocator);
    const r2 = try mock.call(allocator, req);
    defer r2.deinit(allocator);

    try std.testing.expectEqualStrings(r1.content, r2.content);
    try std.testing.expectEqualStrings(r1.model_id, r2.model_id);
    try std.testing.expectEqualStrings(r1.finish_reason, r2.finish_reason);
    try std.testing.expectEqual(r1.token_usage.total_tokens, r2.token_usage.total_tokens);
}

test "MockBackend ignores request model_id and messages" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "fixed" };
    const messages = [_]model_messages.Message{
        .{ .role = "user", .content = "hello" },
    };
    const req = ProviderRequest{
        .model_id = "gpt-999",
        .messages = &messages,
        .sampling = .{ .temperature = 0.8, .max_output_tokens = 1024 },
    };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqualStrings("fixed", resp.content);
}

test "MockBackend traces the model request scope fields" {
    const allocator = std.testing.allocator;
    var trace = MockBackend.CallTrace{};
    const mock = MockBackend{
        .canned_content = "fixed",
        .trace = &trace,
    };
    const req = ProviderRequest{
        .model_id = "fixture.ai_infra",
        .messages = &.{},
        .budget_id = "budget.fixture_paper",
        .policy_version = "v1",
        .capability_envelope_id = "capenv.trading_order.propose.fixture",
    };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), trace.call_count);
    try std.testing.expectEqualStrings("fixture.ai_infra", trace.last_model_id);
    try std.testing.expectEqualStrings("budget.fixture_paper", trace.last_budget_id);
    try std.testing.expectEqualStrings("v1", trace.last_policy_version);
    try std.testing.expectEqualStrings("capenv.trading_order.propose.fixture", trace.last_capability_envelope_id);
}

test "MockBackend response token_usage defaults to zero" {
    const allocator = std.testing.allocator;
    const mock = MockBackend{ .canned_content = "x" };
    const req = ProviderRequest{ .model_id = "any", .messages = &.{} };
    const resp = try mock.call(allocator, req);
    defer resp.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.prompt_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.completion_tokens);
    try std.testing.expectEqual(@as(u32, 0), resp.token_usage.total_tokens);
}
