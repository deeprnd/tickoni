const std = @import("std");
const adapter = @import("adapter");
const model = @import("model");
const portfolio = @import("portfolio");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");
const support = @import("investment_support");
const tkagnt = @import("tkagnt");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");
const tkpoly = @import("tkpoly");

test "investment_allowed_trade_integration: tkcase tkdisp tkagnt build the allowed paper trade" {
    if (true) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);
    try std.testing.expect(support.basketRejects(&basket, "SOXL"));
    try std.testing.expect(support.basketRejects(&basket, "BULZ"));

    const run_id = tkcase.deriveSyntheticRunId(thesis_id);
    const work_item = tkdisp.dispatchInvestmentRun(run_id, input.account_id, input.target_notional_cents);

    var model_backend_impl = model.FixtureBackend{};
    var model_backend = model_backend_impl.asBackend();
    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    const agent_result = try tkagnt.runInvestmentAgent(
        allocator,
        work_item,
        &basket,
        &model_backend,
        &adapter_backend,
        support.policy_max_notional_per_order_cents,
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    try std.testing.expect(std.mem.indexOf(u8, agent_result.model_response.content, "SOXX") != null);
    try std.testing.expectEqual(@as(u32, 335), agent_result.model_response.token_usage.total_tokens);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, agent_result.affordability.outcome);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.allow, agent_result.ticket.policy_outcome);
    try std.testing.expectEqualStrings(support.expected_ticket_id, agent_result.ticket.ticketIdSlice());
    try std.testing.expectEqual(support.target_notional_cents, agent_result.ticket.estimated_cost_cents);
    try std.testing.expectEqual(@as(u8, 7), agent_result.ticket.line_item_count);

    const expected_lines = [_]support.ExpectedLine{
        .{ .ticker = "NVDA", .quantity_micros = 2_000_000, .price_cents = 12_500, .line_notional_cents = 25_000 },
        .{ .ticker = "AMD", .quantity_micros = 1_562_500, .price_cents = 16_000, .line_notional_cents = 25_000 },
        .{ .ticker = "AVGO", .quantity_micros = 1_000_000, .price_cents = 25_000, .line_notional_cents = 25_000 },
        .{ .ticker = "MSFT", .quantity_micros = 500_000, .price_cents = 50_000, .line_notional_cents = 25_000 },
        .{ .ticker = "AMZN", .quantity_micros = 1_250_000, .price_cents = 20_000, .line_notional_cents = 25_000 },
        .{ .ticker = "BOTZ", .quantity_micros = 12_500_000, .price_cents = 3_000, .line_notional_cents = 37_500 },
        .{ .ticker = "SOXX", .quantity_micros = 1_500_000, .price_cents = 25_000, .line_notional_cents = 37_500 },
    };
    for (expected_lines) |expected| {
        const line = support.findLineItem(&agent_result.ticket, expected.ticker) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqual(expected.quantity_micros, line.quantity_micros);
        try std.testing.expectEqual(expected.price_cents, line.price_cents);
        try std.testing.expectEqual(expected.line_notional_cents, line.line_notional_cents);
    }

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(trade_ticket.ExecutionStatus.filled, execution.status);
    try std.testing.expectEqual(support.target_notional_cents, execution.total_filled_cents);
    try std.testing.expectEqualStrings(support.expected_ticket_id, execution.ticketIdSlice());
    try std.testing.expectEqual(@as(i64, 4_800_000), execution.resulting_account_snapshot.cash_cents);
    try std.testing.expectEqual(@as(i64, 200_000), execution.resulting_account_snapshot.day_notional_used_cents);
}
