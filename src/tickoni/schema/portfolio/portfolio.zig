/// Test brokerage account schema and affordability checks
///
/// BrokerageAccount: account id, cash, buying power, currency, holdings,
/// open orders, day notional used, and month notional used (T1).
///
/// fixtures: five deterministic test accounts — cash_rich, low_cash,
/// technology_heavy, diversified, and restricted_account (T2).
///
/// checkAffordability(): derives cash available, buying power, remaining daily
/// notional, remaining monthly notional, and max affordable basket size, then
/// returns an AffordabilityResult with outcome and all computed limits (T3).
const std = @import("std");
const basket = @import("basket");

pub const portfolio_schema_version: u16 = 1;

// ---------------------------------------------------------------------------
// Capacity constants
// ---------------------------------------------------------------------------

/// Maximum concurrent holdings per account snapshot.
pub const max_holdings: usize = 32;
/// Maximum concurrent open orders per account snapshot.
pub const max_snapshot_open_orders: usize = 16;
/// Maximum bytes in a ticker symbol.
pub const max_ticker_len: usize = 8;

// ---------------------------------------------------------------------------
// Scale constants
// ---------------------------------------------------------------------------

pub const cents_per_dollar: i64 = 100;

// ---------------------------------------------------------------------------
// Types (T1)
// ---------------------------------------------------------------------------

pub const Currency = enum(u8) { usd };

pub const Side = enum(u8) { buy, sell };

/// A single open equity or ETF position held in the account.
pub const Holding = struct { ticker: [max_ticker_len]u8,
    ticker_len: u8,
    /// Whole shares currently held.
    share_count: u32,
    /// Latest mark-to-market value in cents.
    market_value_cents: i64,

    pub fn tickerSlice(self: *const Holding) []const u8 {
        return self.ticker[0..self.ticker_len]; }
};

/// A pending order that commits buying power until filled or cancelled.
pub const OpenOrder = struct { ticker: [max_ticker_len]u8,
    ticker_len: u8,
    side: Side,
    /// Committed notional in cents.
    notional_cents: i64,

    pub fn tickerSlice(self: *const OpenOrder) []const u8 {
        return self.ticker[0..self.ticker_len]; }
};

/// Test brokerage account snapshot (T1).
///
/// buying_power_cents is already net of open-order commitments and any pending
/// settlement holds as reported by the test account provider.  It is the
/// binding limit for a new paper or sandbox order.  cash_cents is the raw
/// balance before deductions; it may be higher than buying_power_cents when
/// open orders have committed part of the balance.
///
/// max_open_order_count: maximum concurrent open orders the account allows.
/// When 0, no slot check is performed.
pub const BrokerageAccount = struct { account_id: u32,
    currency: Currency,
    /// Raw cash balance in cents.
    cash_cents: i64,
    /// Net buying power in cents; binding limit for new orders.
    buying_power_cents: i64,
    holdings: [max_holdings]Holding,
    holding_count: u8,
    open_orders: [max_snapshot_open_orders]OpenOrder,
    open_order_count: u8,
    /// Hard cap on concurrent open orders; 0 means no slot check.
    max_open_order_count: u8,
    day_notional_used_cents: i64,
    day_notional_limit_cents: i64,
    month_notional_used_cents: i64,
    month_notional_limit_cents: i64, };

// ---------------------------------------------------------------------------
// Affordability check (T3)
// ---------------------------------------------------------------------------

/// Outcome of checkAffordability.
pub const AffordabilityOutcome = enum(u8) { allow = 0,
    deny_open_order_limit = 1,
    deny_insufficient_buying_power = 2,
    deny_day_limit_exceeded = 3,
    deny_month_limit_exceeded = 4,
    deny_invalid_notional = 5, };

/// Result of checkAffordability (T3).
///
/// max_affordable_cents is the minimum of cash_available_cents,
/// buying_power_cents, remaining_daily_notional_cents, and
/// remaining_monthly_notional_cents.
/// On deny, it is the maximum the account can afford right now.
pub const AffordabilityResult = struct { outcome: AffordabilityOutcome,
    requested_notional_cents: i64,
    /// Effective ceiling: min(cash_available, buying_power, remaining_daily, remaining_monthly).
    max_affordable_cents: i64,
    /// Cash available for a new order after clamping invalid negatives and
    /// respecting the reported buying-power ceiling.
    cash_available_cents: i64,
    /// account.buying_power_cents (net limit for a new order).
    buying_power_cents: i64,
    remaining_daily_notional_cents: i64,
    remaining_monthly_notional_cents: i64, };

/// Audit record payload for an affordability check.
/// Emitted alongside the basket-construction audit record when the account
/// check is the binding gate on a proposed trade ticket.
pub const AffordabilityCheckPayload = struct { account_id: u32,
    requested_notional_cents: i64,
    outcome: AffordabilityOutcome,
    max_affordable_cents: i64, };

pub const BasketAffordabilityError = error{ AccountMismatch, };

/// Check whether account can afford requested_notional_cents for a new order.
///
/// Check order:
///   0. requested notional must be positive
///   1. open-order slot: open_order_count < max_open_order_count
///      (skipped when max_open_order_count == 0)
///   2. cash available: cash_available_cents >= requested_notional_cents
///   3. buying power: buying_power_cents >= requested_notional_cents
///   4. remaining daily notional >= requested_notional_cents
///   5. remaining monthly notional >= requested_notional_cents
///
/// remaining_daily  = max(0, day_notional_limit_cents  - day_notional_used_cents)
/// remaining_monthly = max(0, month_notional_limit_cents - month_notional_used_cents)
/// cash_available  = min(max(0, cash_cents), max(0, buying_power_cents))
/// max_affordable  = min(cash_available, buying_power, remaining_daily, remaining_monthly)
pub fn checkAffordability(
    account: *const BrokerageAccount,
    requested_notional_cents: i64,
) AffordabilityResult { const raw_cash_available = @max(@as(i64, 0), account.cash_cents);
    const buying_power = @max(@as(i64, 0), account.buying_power_cents);
    const cash_available = @min(raw_cash_available, buying_power);
    const remaining_daily = @max(
        @as(i64, 0),
        account.day_notional_limit_cents - account.day_notional_used_cents,
    );
    const remaining_monthly = @max(
        @as(i64, 0),
        account.month_notional_limit_cents - account.month_notional_used_cents,
    );
    const max_affordable = @min(cash_available, @min(buying_power, @min(remaining_daily, remaining_monthly)));

    const outcome: AffordabilityOutcome = blk: {
        if (requested_notional_cents <= 0)
            break :blk .deny_invalid_notional;
        if (account.max_open_order_count > 0 and
            account.open_order_count >= account.max_open_order_count)
            break :blk .deny_open_order_limit;
        if (requested_notional_cents > cash_available)
            break :blk .deny_insufficient_buying_power;
        if (requested_notional_cents > buying_power)
            break :blk .deny_insufficient_buying_power;
        if (requested_notional_cents > remaining_daily)
            break :blk .deny_day_limit_exceeded;
        if (requested_notional_cents > remaining_monthly)
            break :blk .deny_month_limit_exceeded;
        break :blk .allow; };

    return .{ .outcome = outcome,
        .requested_notional_cents = requested_notional_cents,
        .max_affordable_cents = max_affordable,
        .cash_available_cents = cash_available,
        .buying_power_cents = buying_power,
        .remaining_daily_notional_cents = remaining_daily,
        .remaining_monthly_notional_cents = remaining_monthly, };
}

/// Check affordability for a concrete basket and ensure the basket belongs to
/// the same test account fixture.
pub fn checkBasketAffordability(
    account: *const BrokerageAccount,
    proposed_basket: *const basket.Basket,
) BasketAffordabilityError!AffordabilityResult { if (account.account_id != proposed_basket.account_id)
        return error.AccountMismatch;

    const basket_notional = if (proposed_basket.total_allocated_cents > 0)
        proposed_basket.total_allocated_cents
    else
        proposed_basket.target_notional_cents;

    return checkAffordability(account, basket_notional); }

/// Return the held position for ticker, or null when the account does not own it.
pub fn findHolding(
    account: *const BrokerageAccount,
    ticker: []const u8,
) ?*const Holding { for (account.holdings[0..account.holding_count]) |*holding| {
        if (std.mem.eql(u8, holding.tickerSlice(), ticker)) return holding; }
    return null;
}

// ---------------------------------------------------------------------------
// Comptime helpers
// ---------------------------------------------------------------------------

fn tickerBuf(comptime s: []const u8) [max_ticker_len]u8 { if (s.len > max_ticker_len) @compileError("ticker exceeds max_ticker_len");
    var buf = [_]u8{ 0 }**max_ticker_len;
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

fn mkHoldingWithShares(comptime ticker_s: []const u8, share_count: u32, mv_cents: i64) Holding { return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .share_count = share_count,
        .market_value_cents = mv_cents, };
}

fn mkOpenOrder(comptime ticker_s: []const u8, side: Side, notional_cents: i64) OpenOrder { return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .side = side,
        .notional_cents = notional_cents, };
}

// ---------------------------------------------------------------------------
// Demo fixtures (T2)
// ---------------------------------------------------------------------------

/// Deterministic demo fixtures for the five canonical account scenarios.
pub const fixtures = struct {
    /// cash_rich: USD 50,000 cash/buying power, no holdings, no open orders.
    /// USD 25,000/day and USD 100,000/month notional limits.  The canonical
    /// demo account for the USD 2,000 AI infrastructure paper trade.
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
    /// for USD 1,000 committed). Seven technology/AI positions concentrated in
    /// the AI infrastructure thesis universe. USD 20,000/day (USD 5,000 used)
    /// and USD 80,000/month (USD 15,000 used) limits.
    pub const technology_heavy: BrokerageAccount = blk: { var a = std.mem.zeroes(BrokerageAccount);
        a.account_id = 2003;
        a.currency = .usd;
        a.cash_cents = 1_000_000;
        a.buying_power_cents = 900_000;
        a.holdings[0] = mkHoldingWithShares("NVDA", 115, 1_495_000);
        a.holdings[1] = mkHoldingWithShares("AMD", 48, 792_000);
        a.holdings[2] = mkHoldingWithShares("AVGO", 20, 360_000);
        a.holdings[3] = mkHoldingWithShares("MSFT", 28, 1_176_000);
        a.holdings[4] = mkHoldingWithShares("SOXX", 43, 989_000);
        a.holdings[5] = mkHoldingWithShares("AMZN", 18, 351_000);
        a.holdings[6] = mkHoldingWithShares("BOTZ", 156, 499_200);
        a.holding_count = 7;
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
        a.holdings[0] = mkHoldingWithShares("SPY", 8, 456_000);
        a.holdings[1] = mkHoldingWithShares("VYM", 23, 299_000);
        a.holdings[2] = mkHoldingWithShares("PANW", 11, 192_500);
        a.holdings[3] = mkHoldingWithShares("AVGO", 11, 198_000);
        a.holdings[4] = mkHoldingWithShares("BIL", 43, 393_450);
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
// Tests (T4)
// ---------------------------------------------------------------------------

test "portfolio_schema_version is 1" { try std.testing.expectEqual(@as(u16, 1), portfolio_schema_version); }

// --- Acceptance: sufficient cash → allow (T4) ---

test "checkAffordability: cash_rich affords AI thesis notional" { // AI infrastructure thesis target: USD 2,000 = 200,000 cents.
    const result = checkAffordability(&fixtures.cash_rich, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 200_000), result.requested_notional_cents); }

test "checkAffordability: cash_rich max_affordable is min(cash, buying_power, daily, monthly)" { // min(5_000_000, 5_000_000, 2_500_000, 10_000_000) = 2_500_000
    const result = checkAffordability(&fixtures.cash_rich, 200_000);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.max_affordable_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), result.buying_power_cents);
    try std.testing.expectEqual(@as(i64, 2_500_000), result.remaining_daily_notional_cents);
    try std.testing.expectEqual(@as(i64, 10_000_000), result.remaining_monthly_notional_cents); }

test "checkAffordability: technology_heavy affords USD 2,000 basket" { // buying_power = 900_000 (USD 9,000); USD 2,000 < USD 9,000 → allow.
    const result = checkAffordability(&fixtures.technology_heavy, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

test "checkAffordability: diversified affords USD 2,000 basket" { const result = checkAffordability(&fixtures.diversified, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

// --- Acceptance: insufficient cash → deny (T4) ---

test "checkAffordability: low_cash denied for USD 200 request" { // buying_power = 15_000 (USD 150) < 20_000 (USD 200).
    const result = checkAffordability(&fixtures.low_cash, 20_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome); }

test "checkAffordability: low_cash max_affordable equals buying_power" { const result = checkAffordability(&fixtures.low_cash, 20_000);
    // max_affordable = min(15_000, 15_000, 2_500_000, 10_000_000) = 15_000
    try std.testing.expectEqual(@as(i64, 15_000), result.max_affordable_cents); }

test "checkAffordability: deny_insufficient_buying_power when buying_power is zero" { var a = fixtures.cash_rich;
    a.buying_power_cents = 0;
    const result = checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: deny_invalid_notional when request is zero or negative" { try std.testing.expectEqual(
        AffordabilityOutcome.deny_invalid_notional,
        checkAffordability(&fixtures.cash_rich, 0).outcome,
    );
    try std.testing.expectEqual(
        AffordabilityOutcome.deny_invalid_notional,
        checkAffordability(&fixtures.cash_rich, -1).outcome,
    ); }

test "checkAffordability: cash is a hard ceiling even when buying power is higher" { var a = fixtures.cash_rich;
    a.cash_cents = 50_000;
    a.buying_power_cents = 100_000;
    const result = checkAffordability(&a, 75_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 50_000), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 50_000), result.max_affordable_cents); }

test "checkAffordability: negative cash fails closed" { var a = fixtures.cash_rich;
    a.cash_cents = -1;
    const result = checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_insufficient_buying_power, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.cash_available_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

// --- Acceptance: day-limit exceeded → deny (T4) ---

test "checkAffordability: day limit exhausted denies any positive request" { var a = fixtures.cash_rich;
    a.day_notional_used_cents = a.day_notional_limit_cents;
    const result = checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_day_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.remaining_daily_notional_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: day limit exceeded by large request" { // cash_rich day limit is USD 25,000 = 2_500_000 cents; request USD 30,000.
    const result = checkAffordability(&fixtures.cash_rich, 3_000_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_day_limit_exceeded, result.outcome);
    // max_affordable = min(5_000_000, 5_000_000, 2_500_000, 10_000_000) = 2_500_000
    try std.testing.expectEqual(@as(i64, 2_500_000), result.max_affordable_cents); }

test "checkAffordability: allow when request equals remaining daily notional exactly" { var a = fixtures.cash_rich;
    // remaining daily = 2_500_000; buying_power = 5_000_000.
    const result = checkAffordability(&a, 2_500_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

// --- Acceptance: month-limit exceeded → deny (T4) ---

test "checkAffordability: month limit exhausted denies any positive request" { var a = fixtures.cash_rich;
    a.month_notional_used_cents = a.month_notional_limit_cents;
    const result = checkAffordability(&a, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_month_limit_exceeded, result.outcome);
    try std.testing.expectEqual(@as(i64, 0), result.remaining_monthly_notional_cents);
    try std.testing.expectEqual(@as(i64, 0), result.max_affordable_cents); }

test "checkAffordability: month limit binding when day limit is not" { // Set day_limit high but month_limit low so month is the binding constraint.
    var a = fixtures.cash_rich;
    a.day_notional_limit_cents = 50_000_000; // USD 500,000/day
    a.month_notional_limit_cents = 300_000; // USD 3,000/month
    a.month_notional_used_cents = 200_000; // USD 2,000 used → USD 1,000 remaining
    // Request USD 2,000 > remaining monthly USD 1,000.
    const result = checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_month_limit_exceeded, result.outcome);
    // max_affordable = min(5_000_000, 5_000_000, 50_000_000, 100_000) = 100_000
    try std.testing.expectEqual(@as(i64, 100_000), result.max_affordable_cents); }

test "checkAffordability: allow when request equals remaining monthly notional exactly" { var a = fixtures.cash_rich;
    a.month_notional_used_cents = a.month_notional_limit_cents - 200_000;
    const result = checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

// --- Acceptance: open-order limit → deny (T4) ---

test "checkAffordability: restricted_account denied due to open-order limit" { const result = checkAffordability(&fixtures.restricted_account, 1);
    try std.testing.expectEqual(AffordabilityOutcome.deny_open_order_limit, result.outcome); }

test "checkAffordability: open-order limit check fires before buying-power check" { // Arrange an account with sufficient cash but no open-order slot.
    var a = fixtures.cash_rich;
    a.open_order_count = 8;
    a.max_open_order_count = 8;
    const result = checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.deny_open_order_limit, result.outcome); }

test "checkBasketAffordability: uses basket total_allocated_cents for the request" { var proposed_basket = std.mem.zeroes(basket.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;
    proposed_basket.total_allocated_cents = 150_000;

    const result = try checkBasketAffordability(&fixtures.cash_rich, &proposed_basket);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 150_000), result.requested_notional_cents); }

test "checkBasketAffordability: falls back to target_notional_cents when total_allocated is zero" { var proposed_basket = std.mem.zeroes(basket.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;

    const result = try checkBasketAffordability(&fixtures.cash_rich, &proposed_basket);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome);
    try std.testing.expectEqual(@as(i64, 200_000), result.requested_notional_cents); }

test "checkBasketAffordability: rejects account mismatch" { var proposed_basket = std.mem.zeroes(basket.Basket);
    proposed_basket.account_id = fixtures.cash_rich.account_id;
    proposed_basket.target_notional_cents = 200_000;

    try std.testing.expectError(
        BasketAffordabilityError.AccountMismatch,
        checkBasketAffordability(&fixtures.low_cash, &proposed_basket),
    ); }

test "checkAffordability: open-order limit not triggered when max_open_order_count is 0" { // max_open_order_count == 0 means no slot check; even with open_order_count > 0.
    var a = fixtures.cash_rich;
    a.open_order_count = 255;
    a.max_open_order_count = 0;
    const result = checkAffordability(&a, 200_000);
    try std.testing.expectEqual(AffordabilityOutcome.allow, result.outcome); }

// --- Fixture integrity tests ---

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
        &fixtures.restricted_account, }) |a| { try std.testing.expectEqual(Currency.usd, a.currency); }
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

test "fixtures: technology_heavy has 7 holdings" { try std.testing.expectEqual(@as(u8, 7), fixtures.technology_heavy.holding_count);
    try std.testing.expectEqualStrings("NVDA", fixtures.technology_heavy.holdings[0].tickerSlice());
    try std.testing.expectEqualStrings("BOTZ", fixtures.technology_heavy.holdings[6].tickerSlice());
    try std.testing.expect(fixtures.technology_heavy.holdings[0].share_count > 0); }

test "fixtures: diversified has 5 holdings across different sectors" { try std.testing.expectEqual(@as(u8, 5), fixtures.diversified.holding_count);
    try std.testing.expectEqualStrings("SPY", fixtures.diversified.holdings[0].tickerSlice());
    try std.testing.expectEqualStrings("BIL", fixtures.diversified.holdings[4].tickerSlice());
    try std.testing.expect(fixtures.diversified.holdings[0].share_count > 0); }

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

test "findHolding: returns the owned position when present" { const holding = findHolding(&fixtures.technology_heavy, "NVDA").?;
    try std.testing.expectEqual(@as(u32, 115), holding.share_count); }

test "findHolding: returns null when the account does not own the ticker" { try std.testing.expect(findHolding(&fixtures.cash_rich, "NVDA") == null); }

// --- AffordabilityCheckPayload audit record construction ---

test "AffordabilityCheckPayload: fields populate from result correctly" { const result = checkAffordability(&fixtures.cash_rich, 200_000);
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
