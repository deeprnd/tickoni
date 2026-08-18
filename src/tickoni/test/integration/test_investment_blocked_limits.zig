const std = @import("std");
const adapter = @import("adapter");
const audit = @import("audit_tile");
const investment_audit = @import("investment_audit");
const model = @import("model");
const portfolio = @import("portfolio");
const replay = @import("replay");
const thesis = @import("thesis");
const trade_ticket = @import("trade_ticket");
const support = @import("investment_support");
const tkagnt = @import("tkagnt");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");
const tkpoly = @import("tkpoly");

test "investment_blocked_limits_integration: oversized trade is blocked before paper execution" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInputWithTarget(support.oversized_target_notional_cents);
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
        support.expected_blocked_ticket_id,
    );
    defer agent_result.deinit(allocator);

    try std.testing.expectEqual(portfolio.AffordabilityOutcome.allow, agent_result.affordability.outcome);
    try std.testing.expectEqual(@as(i64, 2_500_000), agent_result.affordability.max_affordable_cents);
    try std.testing.expectEqual(trade_ticket.PolicyOutcome.deny, agent_result.ticket.policy_outcome);
    try std.testing.expectEqualStrings(support.expected_blocked_ticket_id, agent_result.ticket.ticketIdSlice());
    try std.testing.expectEqual(support.oversized_target_notional_cents, agent_result.ticket.estimated_cost_cents);
    try std.testing.expectEqual(@as(i64, 250_000), agent_result.ticket.affordability_result.effective_max_paper_trade_cents);
    try std.testing.expectEqual(@as(u8, 1), agent_result.ticket.blocked_reason_count);
    try std.testing.expectEqual(trade_ticket.BlockedReasonCode.per_order_notional_exceeded, agent_result.ticket.blocked_reasons[0].code);
    try std.testing.expectEqual(trade_ticket.FailedScopeDimension.per_order_notional, agent_result.ticket.blocked_reasons[0].failed_scope_dim);
    try std.testing.expectEqual(support.oversized_target_notional_cents, agent_result.ticket.blocked_reasons[0].requested_cents);
    try std.testing.expectEqual(@as(i64, 250_000), agent_result.ticket.blocked_reasons[0].limit_cents);
    try std.testing.expect(agent_result.paper_result == null);
}

test "investment_blocked_limits_integration: oversized trade replay and audit reproduce the deny" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInputWithTarget(support.oversized_target_notional_cents);
    const thesis_id = thesis.computeThesisInputHash(input);
    const intent = try thesis.normalize(input);
    const basket = try tkpoly.buildBasket(intent, thesis_id);

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
        support.expected_blocked_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const replay_result = try replay.verifyOversizedTradeBlock(
        allocator,
        std.testing.io,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildOversizedTradeBlockedChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &replay_result,
    );
    try std.testing.expectEqual(investment_audit.oversized_trade_blocked_event_count, audit_chain.slice().len);
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.policy_decision, std.meta.activeTag(audit_chain.events[4].payload));
    try std.testing.expectEqual(audit.RecordType.limit_check, std.meta.activeTag(audit_chain.events[9].payload));
    try std.testing.expectEqual(audit.RecordType.denial, std.meta.activeTag(audit_chain.events[10].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[11].payload));
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[4].payload.policy_decision.outcome);
    try std.testing.expectEqual(audit.PolicyOutcome.deny, audit_chain.events[9].payload.limit_check.outcome);
    try std.testing.expectEqual(
        @as(u32, @intFromEnum(trade_ticket.BlockedReasonCode.per_order_notional_exceeded)),
        audit_chain.events[10].payload.denial.reason_code,
    );
    try std.testing.expectEqual(@as(i64, 250_000), audit_chain.events[9].payload.limit_check.limit);
    try std.testing.expectEqual(support.oversized_target_notional_cents, audit_chain.events[9].payload.limit_check.value);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
}
