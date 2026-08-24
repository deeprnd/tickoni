const std = @import("std");
const broker_mock = @import("mock_broker_market_server");
const http_support = @import("mock_http_support");
const openai_mock = @import("mock_openai_server");

fn fetchText(allocator: std.mem.Allocator, io: std.Io, url: []const u8, method: std.http.Method, payload: ?[]const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var response_writer: std.Io.Writer.Allocating = .init(allocator);
    defer response_writer.deinit();

    _ = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .extra_headers = if (payload != null) &.{.{ .name = "Content-Type", .value = "application/json" }} else &.{},
        .payload = payload,
        .response_writer = &response_writer.writer,
    });
    return allocator.dupe(u8, response_writer.written());
}

test "integration mock openai server config defaults are stable" {
    const config = openai_mock.Config{};
    try std.testing.expectEqualStrings("mock-openai-model", config.model_id);
    try std.testing.expectEqualStrings("stop", config.finish_reason);
    try std.testing.expectEqual(@as(u32, 28), config.total_tokens);
}

test "integration mock broker server config defaults are stable" {
    const config = broker_mock.Config{};
    try std.testing.expectEqualStrings("ok", config.health_body);
    try std.testing.expect(std.mem.indexOf(u8, config.portfolio_json, "\"account_id\":2001") != null);
    try std.testing.expect(std.mem.indexOf(u8, config.paper_order_json, "\"paper_order_id\":\"mock-paper-order-1\"") != null);
}

test "integration mock openai server serves health and chat completions" {
    const allocator = std.testing.allocator;
    var runtime = http_support.TestRuntime.init();
    defer runtime.deinit();

    var server = try openai_mock.Server.init(runtime.io(), .{
        .model_id = "mock-http-model",
        .content = "{\"thesis_summary\":\"from mock\",\"recommended_tickers\":[\"NVDA\",\"AMD\"]}",
        .prompt_tokens = 12,
        .completion_tokens = 18,
        .total_tokens = 30,
    });
    try server.start();
    defer server.stop();

    const endpoint = try server.endpointAlloc(allocator);
    defer allocator.free(endpoint);
    const health_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{server.listener.socket.address.getPort()});
    defer allocator.free(health_url);
    const completions_url = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{endpoint});
    defer allocator.free(completions_url);

    const health = try fetchText(allocator, runtime.io(), health_url, .GET, null);
    defer allocator.free(health);
    try std.testing.expectEqualStrings("ok", health);

    const response = try fetchText(
        allocator,
        runtime.io(),
        completions_url,
        .POST,
        "{\"model\":\"mock-http-model\",\"messages\":[{\"role\":\"user\",\"content\":\"hello mock\"}],\"temperature\":0,\"top_p\":1,\"max_tokens\":32,\"seed\":1,\"stream\":false}",
    );
    defer allocator.free(response);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"model\":\"mock-http-model\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, response, "\"total_tokens\":30") != null);

    const last = server.lastRequest() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("POST", last.methodSlice());
    try std.testing.expectEqualStrings("/v1/chat/completions", last.pathSlice());
    try std.testing.expect(std.mem.indexOf(u8, last.bodySlice(), "\"model\":\"mock-http-model\"") != null);
}

test "integration mock broker server serves health and broker endpoints" {
    const allocator = std.testing.allocator;
    var runtime = http_support.TestRuntime.init();
    defer runtime.deinit();

    var server = try broker_mock.Server.init(runtime.io(), .{});
    try server.start();
    defer server.stop();

    const base_url = try server.baseUrlAlloc(allocator);
    defer allocator.free(base_url);

    const health_url = try std.fmt.allocPrint(allocator, "{s}/health", .{base_url});
    defer allocator.free(health_url);
    const portfolio_url = try std.fmt.allocPrint(allocator, "{s}/accounts/2001/portfolio", .{base_url});
    defer allocator.free(portfolio_url);
    const quotes_url = try std.fmt.allocPrint(allocator, "{s}/quotes", .{base_url});
    defer allocator.free(quotes_url);
    const paper_orders_url = try std.fmt.allocPrint(allocator, "{s}/paper-orders", .{base_url});
    defer allocator.free(paper_orders_url);

    const health = try fetchText(allocator, runtime.io(), health_url, .GET, null);
    defer allocator.free(health);
    try std.testing.expectEqualStrings("ok", health);

    const portfolio_json = try fetchText(allocator, runtime.io(), portfolio_url, .GET, null);
    defer allocator.free(portfolio_json);
    try std.testing.expect(std.mem.indexOf(u8, portfolio_json, "\"account_id\":2001") != null);

    const quotes_json = try fetchText(allocator, runtime.io(), quotes_url, .POST, "{\"tickers\":[\"NVDA\"]}");
    defer allocator.free(quotes_json);
    try std.testing.expect(std.mem.indexOf(u8, quotes_json, "\"ticker\":\"NVDA\"") != null);

    const paper_order_json = try fetchText(allocator, runtime.io(), paper_orders_url, .POST, "{\"ticket_id\":\"ticket-1\"}");
    defer allocator.free(paper_order_json);
    try std.testing.expect(std.mem.indexOf(u8, paper_order_json, "\"paper_order_id\":\"mock-paper-order-1\"") != null);

    const last = server.lastRequest() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("POST", last.methodSlice());
    try std.testing.expectEqualStrings("/paper-orders", last.pathSlice());
    try std.testing.expect(std.mem.indexOf(u8, last.bodySlice(), "\"ticket_id\":\"ticket-1\"") != null);
}
