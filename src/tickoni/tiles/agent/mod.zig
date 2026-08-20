const std = @import("std");
const adapter = @import("adapter");
const mock_adapter = @import("mock_adapter");
const basket_mod = @import("basket");
const capability = @import("capability");
const disp = @import("disp");
const model = @import("model");
const mock_model = @import("mock_model");
const portfolio = @import("portfolio");
const tkpoly = @import("tkpoly");
const tool = @import("tool");
const trade_ticket = @import("trade_ticket");
const adapter_messages = @import("adapter_messages");

const investment_model_id = "fixture.ai_infra";
const investment_actor_role = capability.investment_actor_role;
const investment_workflow = capability.investment_workflow;
const investment_capability = capability.investment_capability;
const investment_capability_envelope_id = "capenv.trading_order.propose.demo";
const investment_policy_version = "v1";
const investment_budget_id = "budget.demo_paper";

/// Result of a normal investment agent run (allowed or oversized-denied).
/// Caller owns model_response; call deinit(allocator) when done.
pub const AgentResult = struct {
    run_id: u64,
    model_response: model.ModelResponse,
    affordability: portfolio.AffordabilityResult,
    quote_snapshot: trade_ticket.QuoteSnapshot,
    ticket: trade_ticket.TradeTicket,
    /// Non-null only when ticket.policy_outcome == .allow.
    paper_result: ?trade_ticket.PaperExecutionResult,

    pub fn deinit(self: AgentResult, allocator: std.mem.Allocator) void {
        self.model_response.deinit(allocator);
    }
};

/// Result of a restricted-instrument denial run.
pub const RestrictedBlockResult = struct {
    run_id: u64,
};

fn baseTkModlConfig(allowed_model_id: []const u8) model.TkModlConfig {
    var config = model.TkModlConfig{
        .live_provider_enabled = true,
        .hard_max_context_tokens = 4096,
        .hard_max_output_tokens = 1024,
        .hard_max_retry_count = 1,
        .hard_timeout_ms = 30_000,
        .per_run_token_budget = 2048,
    };
    config.allowed_model_ids[0] = allowed_model_id;
    config.allowed_model_id_count = 1;
    return config;
}

fn investmentTkModlRequest(work_item: disp.WorkItem) model.TkModlRequest {
    return .{
        .request_id = work_item.run_id,
        .run_id = work_item.run_id,
        .actor_id = work_item.account_id,
        .actor_role = investment_actor_role,
        .workflow = investment_workflow,
        .account_id = work_item.account_id,
        .capability = investment_capability,
        .capability_envelope_id = investment_capability_envelope_id,
        .policy_version = investment_policy_version,
        .policy_decision_id = 0,
        .budget_id = investment_budget_id,
        .model_id = investment_model_id,
        .messages = &.{.{ .role = "user", .content = "ai infrastructure" }},
        .sampling = .{
            .temperature = 0,
            .top_p = 1.0,
            .max_output_tokens = 512,
            .seed = 42,
        },
        .max_context_tokens = 2048,
        .max_output_tokens = 512,
        .retry_limit = 0,
        .timeout_ms = 30_000,
        .replay_mode = .live,
    };
}

fn runInvestmentTkModl(
    allocator: std.mem.Allocator,
    work_item: disp.WorkItem,
    model_backend: *model.Backend,
) !model.ModelResponse {
    var result = try model.runTkModlRequest(
        allocator,
        baseTkModlConfig(investment_model_id),
        model_backend,
        investmentTkModlRequest(work_item),
    );
    errdefer result.deinit(allocator);

    switch (result.outcome) {
        .allow_live, .allow_replay => {},
        else => return error.TkModlDenied,
    }

    const response = result.response orelse return error.TkModlMissingResponse;
    result.response = null;
    return response;
}

/// Bounded deterministic agent for normal investment flows (allowed or oversized).
/// Calls tkmodl (model_backend) then tktool/tkadpt (adapter_backend).
/// Invokes paper order only when ticket.policy_outcome == .allow.
pub fn runInvestmentAgent(
    allocator: std.mem.Allocator,
    work_item: disp.WorkItem,
    proposed_basket: *const basket_mod.Basket,
    model_backend: *model.Backend,
    adapter_backend: *adapter.Backend,
    policy_max_notional_per_order_cents: i64,
    ticket_id: []const u8,
) !AgentResult {
    const model_response = try runInvestmentTkModl(allocator, work_item, model_backend);
    errdefer model_response.deinit(allocator);

    // tktool -> tkadpt: portfolio snapshot
    const portfolio_result = try adapter_backend.call(
        tool.normalizePortfolioRead(work_item.account_id),
    );
    const account = switch (portfolio_result) {
        .portfolio_snapshot => |s| s,
        else => return error.UnexpectedAdapterResponse,
    };
    const affordability = try portfolio.checkBasketAffordability(&account, proposed_basket);

    // tktool -> tkadpt: quote snapshot
    const quote_result = try adapter_backend.call(
        tool.normalizeQuoteRead(proposed_basket),
    );
    const quote_snapshot = switch (quote_result) {
        .quote_snapshot => |s| s,
        else => return error.UnexpectedAdapterResponse,
    };

    var ticket = try trade_ticket.buildMarketBuyTicket(
        proposed_basket,
        &quote_snapshot,
        affordability,
        ticket_id,
    );
    tkpoly.applyTradeGuardrails(&ticket, affordability, policy_max_notional_per_order_cents);

    // tktool -> tkadpt: paper order (only when policy allows)
    var paper_result: ?trade_ticket.PaperExecutionResult = null;
    if (ticket.policy_outcome == .allow) {
        const paper_resp = try adapter_backend.call(tool.normalizePaperOrder(&ticket));
        paper_result = switch (paper_resp) {
            .paper_order => |r| r,
            else => return error.UnexpectedAdapterResponse,
        };
    }

    return .{
        .run_id = work_item.run_id,
        .model_response = model_response,
        .affordability = affordability,
        .quote_snapshot = quote_snapshot,
        .ticket = ticket,
        .paper_result = paper_result,
    };
}

/// Bounded agent for restricted-instrument denial flows.
/// Denial happens before model, adapter, proposal, and paper-execution work.
pub fn runRestrictedInstrumentDenialAgent(
    work_item: disp.WorkItem,
) !RestrictedBlockResult {
    return .{
        .run_id = work_item.run_id,
    };
}

test "runInvestmentAgent blocks oversized trade and skips paper execution" {
    var proposed_basket: basket_mod.Basket = std.mem.zeroes(basket_mod.Basket);
    proposed_basket.account_id = 2001;
    proposed_basket.target_notional_cents = 2_500_000;
    proposed_basket.total_allocated_cents = 2_500_000;
    proposed_basket.instrument_count = 1;
    proposed_basket.instruments[0].ticker_len = 4;
    @memcpy(proposed_basket.instruments[0].ticker[0..4], "NVDA");
    proposed_basket.instruments[0].asset_class = .equity;
    proposed_basket.instruments[0].allocation_cents = 2_500_000;
    proposed_basket.instruments[0].weight_bp = 10_000;
    const work_item = disp.dispatchInvestmentRun(77, proposed_basket.account_id, proposed_basket.target_notional_cents);

    var quote_snapshot: trade_ticket.QuoteSnapshot = std.mem.zeroes(trade_ticket.QuoteSnapshot);
    quote_snapshot.quote_count = 1;
    quote_snapshot.quotes[0].ticker_len = 4;
    @memcpy(quote_snapshot.quotes[0].ticker[0..4], "NVDA");
    quote_snapshot.quotes[0].venue = .nasdaq;
    quote_snapshot.quotes[0].bid_cents = 10_000;
    quote_snapshot.quotes[0].ask_cents = 10_000;
    quote_snapshot.quotes[0].last_cents = 10_000;

    var account: portfolio.BrokerageAccount = std.mem.zeroes(portfolio.BrokerageAccount);
    account.account_id = proposed_basket.account_id;
    account.currency = .usd;
    account.cash_cents = 5_000_000;
    account.buying_power_cents = 5_000_000;
    account.day_notional_limit_cents = 5_000_000;
    account.month_notional_limit_cents = 10_000_000;

    var model_trace = mock_model.MockBackend.CallTrace{};
    var adapter_trace = mock_adapter.MockBackend.CallTrace{};
    var model_mock = mock_model.MockBackend{
        .canned_content = "{\"recommended_tickers\":[\"NVDA\"]}",
        .trace = &model_trace,
    };
    var adapter_mock = mock_adapter.MockBackend{
        .portfolio_snapshot = account,
        .quote_snapshot = quote_snapshot,
        .trace = &adapter_trace,
    };
    var model_backend = mock_model.MockBackend.asBackend(model.Backend, &model_mock);
    var adapter_backend = mock_adapter.MockBackend.asBackend(adapter.Backend, &adapter_mock);
    const result = try runInvestmentAgent(
        std.testing.allocator,
        work_item,
        &proposed_basket,
        &model_backend,
        &adapter_backend,
        250_000,
        "ticket_ai_infra_25000_blocked",
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(work_item.run_id, result.run_id);
    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, result.affordability.outcome);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, result.ticket.policy_outcome);
    try std.testing.expectEqual(@as(u8, 1), result.ticket.blocked_reason_count);
    try std.testing.expectEqual(trade_ticket.BlockedReasonCode.per_order_notional_exceeded, result.ticket.blocked_reasons[0].code);
    try std.testing.expect(result.paper_result == null);
    try std.testing.expectEqual(@as(usize, 1), model_trace.call_count);
    try std.testing.expectEqual(@as(usize, 1), adapter_trace.portfolio_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 1), adapter_trace.quote_snapshot_calls);
    try std.testing.expectEqual(@as(usize, 0), adapter_trace.paper_order_calls);
}

test "runRestrictedInstrumentDenialAgent has no model or adapter boundary" {
    const fn_info = @typeInfo(@TypeOf(runRestrictedInstrumentDenialAgent)).@"fn";
    inline for (fn_info.param_types) |param| {
        if (param) |pt| {
            try std.testing.expect(pt != *adapter.Backend);
            try std.testing.expect(pt != std.mem.Allocator);
            try std.testing.expect(pt != *model.Backend);
        }
    }
    const work_item = disp.dispatchInvestmentRun(88, 2001, 200_000);
    const result = try runRestrictedInstrumentDenialAgent(work_item);

    try std.testing.expectEqual(work_item.run_id, result.run_id);
}
