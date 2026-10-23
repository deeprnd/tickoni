const std = @import("std");
const basket_mod = @import("basket");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");

pub const operations_account_id: u32 = 2001;
pub const target_notional_cents: i64 = 200_000;
pub const oversized_target_notional_cents: i64 = 2_500_000;
pub const policy_max_notional_per_order_cents: i64 = 250_000;
pub const expected_ticket_id = "ticket_ai_infra_2000_market";
pub const expected_blocked_ticket_id = "ticket_ai_infra_25000_blocked";
pub const restricted_ticker = "SOXL";
pub const tampered_replay_capsule_path = "src/tickoni/test/fixtures/investment/scenarios/fixture_replay_capsule_tampered_paper_fill.json";

pub const ExpectedLine = struct {
    ticker: []const u8,
    quantity_micros: u64,
    price_cents: i64,
    line_notional_cents: i64,
};

pub fn operationsThesisInputWithTarget(target_notional_cents_arg: i64) thesis.ThesisInput {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = operations_account_id;
    input.target_notional_cents = target_notional_cents_arg;
    input.max_single_name_pct = 25;
    return input;
}

pub fn operationsThesisInput() thesis.ThesisInput {
    return operationsThesisInputWithTarget(target_notional_cents);
}

pub fn operationsRestrictedTickerInput() thesis.ThesisInput {
    var input = operationsThesisInput();
    const user_text = "Buy SOXL in the basket.";
    @memset(&input.user_text, 0);
    @memcpy(input.user_text[0..user_text.len], user_text);
    input.user_text_len = user_text.len;
    input.requested_ticker_count = 1;
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..restricted_ticker.len], restricted_ticker);
    return input;
}

pub fn findLineItem(ticket: *const trade_ticket.TradeTicket, ticker: []const u8) ?trade_ticket.TicketLineItem {
    for (ticket.line_items[0..ticket.line_item_count]) |line| {
        if (std.mem.eql(u8, line.tickerSlice(), ticker)) return line;
    }
    return null;
}

pub fn basketRejects(proposed_basket: *const basket_mod.Basket, ticker: []const u8) bool {
    for (proposed_basket.rejected[0..proposed_basket.rejected_count]) |candidate| {
        if (std.mem.eql(u8, candidate.tickerSlice(), ticker)) return true;
    }
    return false;
}

pub fn findRejectedCandidate(
    proposed_basket: *const basket_mod.Basket,
    ticker: []const u8,
) ?basket_mod.RejectedCandidate {
    for (proposed_basket.rejected[0..proposed_basket.rejected_count]) |candidate| {
        if (std.mem.eql(u8, candidate.tickerSlice(), ticker)) return candidate;
    }
    return null;
}
