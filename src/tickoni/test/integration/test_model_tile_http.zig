// Integration tests for tkmodl HTTP transport against a local OpenAI-compatible
// mock server. These are deterministic transport proofs and do not require
// llama.cpp or any live model endpoint.

const std = @import("std");
const model = @import("model");
const http_support = @import("mock_http_support");
const openai_mock = @import("mock_openai_server");

const mock_model_id = "mock-http-model";

const system_prompt =
    "You are a structured financial research assistant. " ++
    "Your task is to analyze an investor thesis and recommend a basket of US-listed equities and ETFs. " ++
    "Respond with a JSON object containing: thesis_summary (string), recommended_tickers (array of strings), " ++
    "rationale (object mapping ticker to rationale string). " ++
    "Only recommend instruments appropriate for the given sector theme. " ++
    "Do not recommend leveraged ETFs, inverse ETFs, options, futures, or crypto.";

const user_prompt =
    "Thesis: I want to invest USD 2,000 in sector, but avoid single-name concentration " ++
    "and keep it to US-listed ETFs or large-cap equities.\n" ++
    "Target notional: USD 2,000\n" ++
    "Asset classes: equity, etf\n" ++
    "Market: US\n" ++
    "Sector theme: ai_infrastructure\n" ++
    "Risk preference: moderate\n" ++
    "Max single-name weight: 25%";

const restricted_tickers = [_][]const u8{
    "SOXL", "SOXS", "TQQQ", "SQQQ", "UPRO", "SPXS",
    "UVXY", "SVXY", "LABU", "LABD", "FAS",  "FAZ",
};

const mock_model_content =
    "{\"thesis_summary\":\"USD 2,000 into AI infrastructure via diversified US-listed large-cap equities and ETFs.\"," ++
    "\"recommended_tickers\":[\"NVDA\",\"AMD\",\"AVGO\",\"MSFT\",\"AMZN\",\"BOTZ\",\"SOXX\"]," ++
    "\"rationale\":{\"NVDA\":\"AI compute leader\",\"AMD\":\"AI accelerator challenger\",\"AVGO\":\"Networking and custom silicon\",\"MSFT\":\"Cloud AI platform\",\"AMZN\":\"Cloud infrastructure exposure\",\"BOTZ\":\"Diversified robotics and AI ETF\",\"SOXX\":\"Semiconductor ETF diversification\"}}";

fn makeAiInfraRequest(model_id: []const u8) model.ProviderRequest {
    return .{
        .model_id = model_id,
        .messages = &.{
            .{ .role = "system", .content = system_prompt },
            .{ .role = "user", .content = user_prompt },
        },
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 2048,
            .seed = 42,
        },
        .budget_id = "budget.demo_paper",
        .policy_version = "v1",
        .capability_envelope_id = "capenv.trading_order.propose.demo",
    };
}

fn requireMockServerOrSkip(io: std.Io) !void {
    var probe = openai_mock.Server.init(io, .{}) catch return error.SkipZigTest;
    probe.listener.deinit(io);
}

fn withMockBackend(
    allocator: std.mem.Allocator,
    test_fn: fn (allocator: std.mem.Allocator, backend: *model.Backend, server: *openai_mock.Server) anyerror!void,
) !void {
    var runtime = http_support.TestRuntime.init();
    defer runtime.deinit();
    try requireMockServerOrSkip(runtime.io());

    var server = try openai_mock.Server.init(runtime.io(), .{
        .model_id = mock_model_id,
        .content = mock_model_content,
        .prompt_tokens = 148,
        .completion_tokens = 187,
        .total_tokens = 335,
    });
    try server.start();
    defer server.stop();

    const endpoint = try server.endpointAlloc(allocator);
    defer allocator.free(endpoint);

    var http_backend = model.HttpBackend{ .endpoint = endpoint, .io = runtime.io() };
    var backend = http_backend.asBackend();
    try test_fn(allocator, &backend, &server);
}

test "model tile http: hello round-trip via mock server" {
    try withMockBackend(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator, backend: *model.Backend, server: *openai_mock.Server) !void {
            const req = model.ProviderRequest{
                .model_id = mock_model_id,
                .messages = &.{.{ .role = "user", .content = "Reply with the single word: hello" }},
                .sampling = .{ .temperature = 0, .max_output_tokens = 256, .seed = 1 },
                .budget_id = "budget.demo_paper",
                .policy_version = "v1",
                .capability_envelope_id = "capenv.trading_order.propose.demo",
            };
            const resp = try backend.call(allocator, req);
            defer resp.deinit(allocator);

            try std.testing.expect(resp.content.len > 0);
            try std.testing.expect(resp.token_usage.total_tokens > 0);
            try std.testing.expectEqual(@as(u32, 1), server.requestCount());
        }
    }.run);
}

test "model tile http: thesis returns valid structured content from mock server" {
    try withMockBackend(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator, backend: *model.Backend, server: *openai_mock.Server) !void {
            const req = makeAiInfraRequest(mock_model_id);
            const resp = try backend.call(allocator, req);
            defer resp.deinit(allocator);

            try std.testing.expectEqualStrings(mock_model_id, resp.model_id);
            try std.testing.expectEqualStrings("stop", resp.finish_reason);
            try std.testing.expectEqual(@as(u32, 148), resp.token_usage.prompt_tokens);
            try std.testing.expectEqual(@as(u32, 187), resp.token_usage.completion_tokens);
            try std.testing.expectEqual(@as(u32, 335), resp.token_usage.total_tokens);

            const last = server.lastRequest() orelse return error.TestUnexpectedResult;
            try std.testing.expectEqualStrings("POST", last.methodSlice());
            try std.testing.expectEqualStrings("/v1/chat/completions", last.pathSlice());
            try std.testing.expect(std.mem.indexOf(u8, last.bodySlice(), "\"model\":\"mock-http-model\"") != null);
            try std.testing.expect(std.mem.indexOf(u8, last.bodySlice(), "\"stream\":false") != null);

            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.content, .{});
            defer parsed.deinit();
            const root = switch (parsed.value) {
                .object => |o| o,
                else => return error.TestUnexpectedResult,
            };
            const summary_v = root.get("thesis_summary") orelse return error.TestUnexpectedResult;
            const summary = switch (summary_v) {
                .string => |s| s,
                else => return error.TestUnexpectedResult,
            };
            try std.testing.expect(summary.len > 0);

            const tickers_v = root.get("recommended_tickers") orelse return error.TestUnexpectedResult;
            const tickers = switch (tickers_v) {
                .array => |a| a,
                else => return error.TestUnexpectedResult,
            };
            try std.testing.expect(tickers.items.len > 0);

            const rationale_v = root.get("rationale") orelse return error.TestUnexpectedResult;
            const rationale = switch (rationale_v) {
                .object => |o| o,
                else => return error.TestUnexpectedResult,
            };
            try std.testing.expect(rationale.count() > 0);

            for (tickers.items) |item| {
                const ticker = switch (item) {
                    .string => |s| s,
                    else => return error.TestUnexpectedResult,
                };
                try std.testing.expect(rationale.contains(ticker));
                for (restricted_tickers) |r| {
                    try std.testing.expect(!std.mem.eql(u8, ticker, r));
                }
            }
        }
    }.run);
}

test "model tile http: two sequential calls both succeed against mock server" {
    try withMockBackend(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator, backend: *model.Backend, server: *openai_mock.Server) !void {
            const req = makeAiInfraRequest(mock_model_id);
            const r1 = try backend.call(allocator, req);
            defer r1.deinit(allocator);
            const r2 = try backend.call(allocator, req);
            defer r2.deinit(allocator);

            try std.testing.expect(r1.content.len > 0);
            try std.testing.expect(r2.content.len > 0);
            try std.testing.expectEqual(@as(u32, 2), server.requestCount());
        }
    }.run);
}

test "model tile http: wrong endpoint fails closed with HttpStatusError" {
    const allocator = std.testing.allocator;
    var runtime = http_support.TestRuntime.init();
    defer runtime.deinit();
    try requireMockServerOrSkip(runtime.io());

    var server = try openai_mock.Server.init(runtime.io(), .{
        .model_id = mock_model_id,
        .content = mock_model_content,
    });
    try server.start();
    defer server.stop();

    const wrong_endpoint = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{server.listener.socket.address.getPort()});
    defer allocator.free(wrong_endpoint);

    var http_backend = model.HttpBackend{ .endpoint = wrong_endpoint, .io = runtime.io() };
    var backend = http_backend.asBackend();
    try std.testing.expectError(error.HttpStatusError, backend.call(allocator, makeAiInfraRequest(mock_model_id)));
}
