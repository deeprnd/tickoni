const std = @import("std");
const adapter = @import("adapter");
const portfolio = @import("portfolio");
const thesis = @import("thesis");
const tkpoly = @import("tkpoly");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");
const support = @import("investment_support");

test "investment_input_policy_denials_integration: malformed thesis input is rejected before dispatch" {
    if (true) return error.SkipZigTest;
    const missing_target = support.operationsThesisInputWithTarget(0);
    try std.testing.expectError(thesis.ThesisError.MissingTargetAmount, thesis.normalize(missing_target));

    var unsupported_only = support.operationsThesisInput();
    unsupported_only.instrument_type_prefs = thesis.instrumentTypeList(.{.option});
    try std.testing.expectError(thesis.ThesisError.NoEligibleInstrumentType, thesis.normalize(unsupported_only));
}

test "investment_input_policy_denials_integration: direct trading_order.place bypass is denied at tktool tkadpt boundary" {
    if (true) return error.SkipZigTest;
    const input = support.operationsThesisInputWithTarget(support.oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);

    var adapter_backend_impl = adapter.FixtureBackend{};
    var adapter_backend = adapter_backend_impl.asBackend();
    const portfolio_result = try adapter_backend.call(tool.normalizePortfolioRead(input.account_id));
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, &basket);
    const quote_result = try adapter_backend.call(tool.normalizeQuoteRead(&basket));
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |snapshot| snapshot,
        else => return error.TestUnexpectedResult,
    };

    var ticket = try trade_ticket.buildMarketBuyTicket(
        &basket,
        &quote_snapshot,
        affordability,
        support.expected_blocked_ticket_id,
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, support.policy_max_notional_per_order_cents);

    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, affordability.outcome);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, ticket.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), ticket.blocked_reason_count);
    try std.testing.expectEqual(
        trade_ticket.BlockedReasonCode.per_order_notional_exceeded,
        ticket.blocked_reasons[0].code,
    );

    try std.testing.expectError(error.PolicyBlocked, adapter_backend.call(tool.normalizePaperOrder(&ticket)));
}
