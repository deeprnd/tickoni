/// Deterministic test fixtures and all behavioral tests for portfolio.zig.
///
/// Imports portfolio.zig for types and functions; does not export them.
/// Consumers that need BrokerageAccount etc. import portfolio directly.
const std = @import("std");
const portfolio = @import("portfolio");
const basket_mod = @import("basket");

const BrokerageAccount = portfolio.BrokerageAccount;
const Holding = portfolio.Holding;
const OpenOrder = portfolio.OpenOrder;
const Side = portfolio.Side;
const AffordabilityOutcome = portfolio.AffordabilityOutcome;
const AffordabilityCheckPayload = portfolio.AffordabilityCheckPayload;
const max_holdings = portfolio.max_holdings;
const max_snapshot_open_orders = portfolio.max_snapshot_open_orders;
const max_ticker_len = portfolio.max_ticker_len;

fn tickerBuf(comptime s: []const u8) [max_ticker_len]u8 { if (s.len > max_ticker_len) @compileError("ticker exceeds max_ticker_len");
    var buf: [max_ticker_len]u8 = std.mem.zeroes([max_ticker_len]u8);
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

fn mkHolding(comptime ticker_s: []const u8, mv_cents: i64) Holding { return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .share_count = 0,
        .market_value_cents = mv_cents, };
}

fn mkOpenOrder(comptime ticker_s: []const u8, side: Side, notional_cents: i64) OpenOrder { return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .side = side,
        .notional_cents = notional_cents, };
}

/// Deterministic test accounts for the five canonical account scenarios.
pub const fixtures = struct {
    /// cash_rich: USD 50,000 cash/buying power, no holdings, no open orders.
    /// USD 25,000/day and USD 100,000/month notional limits.  The canonical
    /// test account for the USD 2,000 paper trade.
    pub const cash_rich: BrokerageAccount = .{
        .account_id = 2001,
        .currency = .usd,
        .cash_cents = 5_000_000,
        .buying_power_cents = 5_000_000,
        .holdings = std.mem.zeroes([max_holdings]Holding),
        .holding_count = 0,
        .open_orders = std.mem.zeroes([max_snapshot_open_orders]OpenOrder),
        .open_order_count = 0,
        .max_open_order_count = 8,
        .day_notional_used_cents = 0,
        .day_notional_limit_cents = 2_500_000,
        .month_notional_used_cents = 0,
        .month_notional_limit_cents = 10_000_000, };

    /// low_cash: USD 150 cash/buying power — below the USD 200 AI thesis cost.
    /// USD 25,000/day and USD 100,000/month limits.  Forces insufficient-cash deny.
    pub const low_cash: BrokerageAccount = .{ .account_id = 2002,
        .currency = .usd,
        .cash_cents = 15_000,
        .buying_power_cents = 15_000,
        .holdings = std.mem.zeroes([max_holdings]Holding),
        .holding_count = 0,
        .open_orders = std.mem.zeroes([max_snapshot_open_orders]OpenOrder),
        .open_order_count = 0,
        .max_open_order_count = 8,
        .day_notional_used_cents = 0,
        .day_notional_limit_cents = 2_500_000,
        .month_notional_used_cents = 0,
        .month_notional_limit_cents = 10_000_000, };

    /// technology_heavy: USD 10,000 cash; USD 9,000 buying power (one open order
    /// for USD 1,000 committed).  Five technology/AI positions totalling USD 50,000.
    /// USD 20,000/day (USD 5,000 used) and USD 80,000/month (USD 15,000 used) limits.
    pub const technology_heavy: BrokerageAccount = blk: { var a = std.mem.zeroes(BrokerageAccount);
        a.account_id = 2003;
        a.currency = .usd;
        a.cash_cents = 1_000_000;
        a.buying_power_cents = 900_000;
        a.holdings[0] = mkHolding("NVDA", 1_500_000);
        a.holdings[1] = mkHolding("AMD", 800_000);
        a.holdings[2] = mkHolding("MSFT", 1_200_000);
        a.holdings[3] = mkHolding("SOXX", 1_000_000);
        a.holdings[4] = mkHolding("BOTZ", 500_000);
        a.holding_count = 5;
        a.open_orders[0] = mkOpenOrder("NVDA", .buy, 100_000);
        a.open_order_count = 1;
        a.max_open_order_count = 8;
        a.day_notional_used_cents = 500_000;
        a.day_notional_limit_cents = 2_000_000;
        a.month_notional_used_cents = 1_500_000;
        a.month_notional_limit_cents = 8_000_000;
        break :blk a; };

    /// diversified: USD 8,000 cash/buying power.  Five positions spanning broad
    /// market, dividends, cyber security, semiconductors, and cash-like sectors.
    /// USD 15,000/day and USD 60,000/month limits with no prior notional used.
    pub const diversified: BrokerageAccount = blk: { var a = std.mem.zeroes(BrokerageAccount);
        a.account_id = 2004;
        a.currency = .usd;
        a.cash_cents = 800_000;
        a.buying_power_cents = 800_000;
        a.holdings[0] = mkHolding("SPY", 500_000);
        a.holdings[1] = mkHolding("VYM", 300_000);
        a.holdings[2] = mkHolding("PANW", 200_000);
        a.holdings[3] = mkHolding("AVGO", 200_000);
        a.holdings[4] = mkHolding("BIL", 400_000);
        a.holding_count = 5;
        a.max_open_order_count = 8;
        a.day_notional_limit_cents = 1_500_000;
        a.month_notional_limit_cents = 6_000_000;
        break :blk a; };

    /// restricted_account: USD 5,000 cash; day notional limit fully used and
    /// open-order slot at capacity (4 of 4 used).  Forces both day-limit and
    /// open-order-limit deny paths.
    pub const restricted_account: BrokerageAccount = blk: { var a = std.mem.zeroes(BrokerageAccount);
        a.account_id = 2005;
        a.currency = .usd;
        a.cash_cents = 500_000;
        a.buying_power_cents = 500_000;
        a.open_orders[0] = mkOpenOrder("SPY", .buy, 50_000);
        a.open_orders[1] = mkOpenOrder("IVV", .buy, 50_000);
        a.open_orders[2] = mkOpenOrder("VOO", .buy, 50_000);
        a.open_orders[3] = mkOpenOrder("VTI", .buy, 50_000);
        a.open_order_count = 4;
        a.max_open_order_count = 4;
        a.day_notional_used_cents = 1_000_000;
        a.day_notional_limit_cents = 1_000_000;
        a.month_notional_limit_cents = 5_000_000;
        break :blk a; };
};

// ---------------------------------------------------------------------------
// Tests: schema version and fixture integrity
// ---------------------------------------------------------------------------

test "portfolio_schema_version is 1" { try std.testing.expectEqual(@as(u16, 1), portfolio.portfolio_schema_version); }

test "fixtures: all account_ids are distinct" { const ids = [_]u32{
        fixtures.cash_rich.account_id,
        fixtures.low_cash.account_id,
        fixtures.technology_heavy.account_id,
        fixtures.diversified.account_id,
        fixtures.restricted_account.account_id, };
    for (ids, 0..) |a, i| { for (ids, 0..) |b, j| {
            if (i != j) try std.testing.expect(a != b); }
    }
}

test "fixtures: all accounts use usd currency" { for ([_]*const BrokerageAccount{
        &fixtures.cash_rich,
        &fixtures.low_cash,
        &fixtures.technology_heavy,
        &fixtures.diversified,
        &fixtures.restricted_account, }) |a| { try std.testing.expectEqual(portfolio.Currency.usd, a.currency); }
}

test "fixtures: holding_count and open_order_count are in bounds" { for ([_]*const BrokerageAccount{
        &fixtures.cash_rich,
        &fixtures.low_cash,
        &fixtures.technology_heavy,
        &fixtures.diversified,
        &fixtures.restricted_account, }) |a| { try std.testing.expect(a.holding_count <= max_holdings);
        try std.testing.expect(a.open_order_count <= max_snapshot_open_orders); }
}

test "fixtures: day_notional_used_cents <= day_notional_limit_cents" { for ([_]*const BrokerageAccount{
        &fixtures.cash_rich,
        &fixtures.low_cash,
        &fixtures.technology_heavy,
        &fixtures.diversified,
        &fixtures.restricted_account, }) |a| { try std.testing.expect(a.day_notional_used_cents <= a.day_notional_limit_cents);
        try std.testing.expect(a.month_notional_used_cents <= a.month_notional_limit_cents); }
}

test "fixtures: technology_heavy has 5 holdings" { try std.testing.expectEqual(@as(u8, 5), fixtures.technology_heavy.holding_count);
    try std.testing.expectEqualStrings("NVDA", fixtures.technology_heavy.holdings[0].tickerSlice());
    try std.testing.expectEqualStrings("BOTZ", fixtures.technology_heavy.holdings[4].tickerSlice()); }

test "fixtures: diversified has 5 holdings across different sectors" { try std.testing.expectEqual(@as(u8, 5), fixtures.diversified.holding_count);
    try std.testing.expectEqualStrings("SPY", fixtures.diversified.holdings[0].tickerSlice());
    try std.testing.expectEqualStrings("BIL", fixtures.diversified.holdings[4].tickerSlice()); }

test "fixtures: restricted_account open_order_count equals max_open_order_count" { try std.testing.expectEqual(
        fixtures.restricted_account.max_open_order_count,
        fixtures.restricted_account.open_order_count,
    ); }

test "fixtures: restricted_account day notional is fully used" { try std.testing.expectEqual(
        fixtures.restricted_account.day_notional_limit_cents,
        fixtures.restricted_account.day_notional_used_cents,
    ); }

test "fixtures: cash_rich buying_power covers the USD 2,000 AI thesis target" { try std.testing.expect(fixtures.cash_rich.buying_power_cents >= 200_000); }

test "fixtures: low_cash buying_power is below USD 200 threshold" { try std.testing.expect(fixtures.low_cash.buying_power_cents < 20_000); }

// ---------------------------------------------------------------------------
// Tests: checkAffordability logic
// ---------------------------------------------------------------------------

test "checkAffordability: cash_rich affords AI thesis notional" { const result = portfolio.checkAffordability(&fixtures.cash_rich, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 200_000), result.requested_notional_cents); }

test "checkAffordability: cash_rich max_affordable is min(cash, buying_power, daily, monthly)" { const result = portfolio.checkAffordability(&fixtures.cash_rich, 200_000);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.max_affordable_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.buying_power_cents);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.remaining_daily_notional_cents);
    try std.testing.expectEqual(@as(i64, 10_000_000), result.remaining_monthly_notional_cents); }

test "checkAffordability: technology_heavy affords USD 2,000 basket" { const result = portfolio.checkAffordability(&fixtures.technology_heavy, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkAffordability: diversified affords USD 2,000 basket" { const result = portfolio.checkAffordability(&fixtures.diversified, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkAffordability: low_cash denied for USD 200 request" { const result = portfolio.checkAffordability(&fixtures.low_cash, 20_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome); }

test "checkAffordability: low_cash max_affordable equals buying_power" { const result = portfolio.checkAffordability(&fixtures.low_cash, 20_000);
    try std.testing.expectEqual(@as(i64, 15_000), result.max_affordable_cents); }

test "checkAffordability: deny_insufficient_buying_power when buying_power is zero" { var a = fixtures.cash_rich;
    a.buying_power_cents = 0;
    const result = portfolio.checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: deny_invalid_notional when request is zero or negative" { try std.testing.expectEqual(
        AffordabilityOutcome.deny_invalid_notional,
        portfolio.checkAffordability(&fixtures.cash_rich, 0).outcome,
    );
    try std.testing.expectEqual(
        AffordabilityOutcome.deny_invalid_notional,
        portfolio.checkAffordability(&fixtures.cash_rich, -1).outcome,
    ); }

test "checkAffordability: cash is a hard ceiling even when buying power is higher" { var a = fixtures.cash_rich;
    a.cash_cents = 50_000;
    a.buying_power_cents = 100_000;
    const result = portfolio.checkAffordability(&a, 75_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 50_000), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 50_000), result.max_affordable_cents); }

test "checkAffordability: negative cash fails closed" { var a = fixtures.cash_rich;
    a.cash_cents = -1;
    const result = portfolio.checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: day limit exhausted denies any positive request" { var a = fixtures.cash_rich;
    a.day_notional_used_cents = a.day_notional_limit_cents;
    const result = portfolio.checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_day_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.remaining_daily_notional_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: day limit exceeded by large request" { const result = portfolio.checkAffordability(&fixtures.cash_rich, 3_000_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_day_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.max_affordable_cents); }

test "checkAffordability: allow when request equals remaining daily notional exactly" { const result = portfolio.checkAffordability(&fixtures.cash_rich, 2_500_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkAffordability: month limit exhausted denies any positive request" { var a = fixtures.cash_rich;
    a.month_notional_used_cents = a.month_notional_limit_cents;
    const result = portfolio.checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_month_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.remaining_monthly_notional_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: month limit binding when day limit is not" { var a = fixtures.cash_rich;
    a.day_notional_limit_cents = 50_000_000;
    a.month_notional_limit_cents = 300_000;
    a.month_notional_used_cents = 200_000;
    const result = portfolio.checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_month_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 100_000), result.max_affordable_cents); }

test "checkAffordability: allow when request equals remaining monthly notional exactly" { var a = fixtures.cash_rich;
    a.month_notional_used_cents = a.month_notional_limit_cents - 200_000;
    const result = portfolio.checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkAffordability: restricted_account denied due to open-order limit" { const result = portfolio.checkAffordability(&fixtures.restricted_account, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_open_order_limit, result.outcome); }

test "checkAffordability: open-order limit check fires before buying-power check" { var a = fixtures.cash_rich;
    a.open_order_count = 8;
    a.max_open_order_count = 8;
    const result = portfolio.checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_open_order_limit, result.outcome); }

test "checkAffordability: open-order limit not triggered when max_open_order_count is 0" { var a = fixtures.cash_rich;
    a.open_order_count = 255;
    a.max_open_order_count = 0;
    const result = portfolio.checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkBasketAffordability: uses basket total_allocated_cents for the request" { var proposed_basket = std.mem.zeroes(basket_mod.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;
    proposed_basket.total_allocated_cents = 150_000;

    const result = try portfolio.checkBasketAffordability(&fixtures.cash_rich, &proposed_basket);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 150_000), result.requested_notional_cents); }

test "checkBasketAffordability: falls back to target_notional_cents when total_allocated is zero" { var proposed_basket = std.mem.zeroes(basket_mod.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;

    const result = try portfolio.checkBasketAffordability(&fixtures.cash_rich, &proposed_basket);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 200_000), result.requested_notional_cents); }

test "checkBasketAffordability: rejects account mismatch" { var proposed_basket = std.mem.zeroes(basket_mod.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;

    try std.testing.expectError(
        portfolio.BasketAffordabilityError.AccountMismatch,
        portfolio.checkBasketAffordability(&fixtures.low_cash, &proposed_basket),
    ); }

test "AffordabilityCheckPayload: fields populate from result correctly" { const result = portfolio.checkAffordability(&fixtures.cash_rich, 200_000);
    const payload = AffordabilityCheckPayload{
        .account_id = fixtures.cash_rich.account_id,
        .requested_notional_cents = result.requested_notional_cents,
        .outcome = result.outcome,
        .max_affordable_cents = result.max_affordable_cents, };
    try std.testing.expectEqual(AffordabilityOutcome.allow, payload.outcome);
    try std.testing.expectEqual(@as(u32, 2001), payload.account_id);
    try std.testing.expectEqual(@as(i64, 200_000), payload.requested_notional_cents);
    try std.testing.expectEqual(@as(i64, 2_500_000), payload.max_affordable_cents);
}
