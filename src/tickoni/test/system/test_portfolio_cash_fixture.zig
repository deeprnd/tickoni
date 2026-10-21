/// V1.3.S4: Portfolio and cash fixture.
///
/// Offline, deterministic proof of the combined investment (V1.1) and payment
/// (V1.2) decision payload: before/after cash and portfolio impact, saved
/// thesis and money proposal cards, deterministic drift/rebalance signals,
/// and the no-execution state for the pending payout and rebalance
/// suggestion. This exercises the same fixture-backed paths as
/// `investment_fixture_test` and `test_investment_decision_cards.zig`; it is a
/// separate root so the combined portfolio/cash contract has one dedicated,
/// clearly named proof, and so it never depends on the live-model system
/// lane (`test_investment_fixture_live.zig` / `zig build system-test`). No live
/// model, broker, payment processor, trading API, TigerBeetle, or autonomous
/// execution is involved.
const investment_fixture = @import("investment_fixture");
const drift = investment_fixture.drift;
const support = @import("investment_support");
const std = @import("std");

fn hasThesisDriftCondition(
    result: *const drift.ThesisDriftResult,
    condition: drift.ThesisDriftCondition,
) bool {
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == condition) return true;
    }
    return false;
}

fn hasPaymentDriftCondition(
    result: *const drift.PaymentDriftResult,
    condition: drift.PaymentDriftCondition,
) bool {
    for (result.active_conditions[0..result.condition_count]) |c| {
        if (c == condition) return true;
    }
    return false;
}

test "portfolio cash fixture: combined investment and payment decision payload is deterministic and replayable" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();

    const result = try investment_fixture.runAllowedTradeScenario(allocator, std.testing.io, input);

    // Before/after portfolio and cash state for the trade (V1.3.S4.T2).
    const impact = result.portfolio_impact;
    try std.testing.expect(impact.cash_before_cents > impact.cash_after_cents);
    try std.testing.expectEqual(
        impact.cash_before_cents - impact.cash_after_cents,
        result.ticket.estimated_cost_cents,
    );
    try std.testing.expect(impact.thesis_after_bp > impact.thesis_before_bp);
    try std.testing.expect(impact.ticker_concentration_count > 0);
    try std.testing.expect(impact.explanation_count > 0);

    // The V1.2 supplier payout rides in the same decision payload as a
    // pending obligation and stays approval-required and unexecuted
    // (V1.3.S4.T3).
    try std.testing.expect(impact.pending_obligations_after_cents > 0);
    try std.testing.expect(impact.any_approval_required);
    try std.testing.expectEqual(investment_fixture.cards.ApprovalState.pending, result.decision_cards.money_proposal_card.approval_state);

    // Thesis and money proposal cards were saved with rationale and evidence
    // links (V1.3.S4.T4).
    try std.testing.expect(result.decision_cards.thesis_card.linked_position_count > 0);
    for (result.decision_cards.thesis_card.linked_positions[0..result.decision_cards.thesis_card.linked_position_count]) |*position| {
        try std.testing.expect(position.evidence_hash != 0);
        try std.testing.expect(position.rationaleSlice().len > 0);
    }
    try std.testing.expect(result.decision_cards.money_proposal_card.evidence_hash != 0);

    // Deterministic drift fixtures trigger thesis drift, cash-buffer alert,
    // approval expiry, a payment proposal update, and a previewable
    // rebalance suggestion, with no autonomous execution (V1.3.S4.T5).
    try std.testing.expect(result.drift_contract.thesis_drift.has_drift);
    try std.testing.expect(hasThesisDriftCondition(&result.drift_contract.thesis_drift, .sector_exposure_breach));
    try std.testing.expect(hasThesisDriftCondition(&result.drift_contract.thesis_drift, .concentration_breach));

    try std.testing.expect(result.drift_contract.payment_drift.has_drift);
    try std.testing.expect(hasPaymentDriftCondition(&result.drift_contract.payment_drift, .approval_expired));
    try std.testing.expect(hasPaymentDriftCondition(&result.drift_contract.payment_drift, .cash_buffer_breached));

    try std.testing.expectEqual(drift.RebalanceSuggestionStatus.proposed, result.drift_contract.rebalance_suggestion.status);
    try std.testing.expect(result.drift_contract.rebalance_suggestion.requires_user_action);
    try std.testing.expect(result.drift_contract.payment_proposal_update.requires_user_action);
    try std.testing.expect(result.drift_contract.payment_proposal_update.suggested_status != .no_change);

    // Replay reproduces the same decision from captured inputs with no live
    // model, adapter, or execution call (V1.3.S4.T6, evidence gate).
    try std.testing.expect(result.replay_result.replay_match);
    try std.testing.expect(result.replay_result.external_effects_disabled);

    // One combined, UI-ready decision payload for a future CaseOps client
    // (V1.3.S4.T6, acceptance).
    const json = try investment_fixture.allocAllowedTradeInterfaceJson(allocator, &result);
    defer allocator.free(json);
    std.debug.print("=== V1.3.S4 Portfolio And Cash Decision Payload ===\n{s}\n", .{json});

    for ([_][]const u8{
        "\"portfolio_impact\"",
        "\"cash_before_cents\"",
        "\"cash_after_cents\"",
        "\"sector_exposures\"",
        "\"ticker_concentrations\"",
        "\"explanations\"",
        "\"decision_cards\"",
        "\"thesis_card\"",
        "\"money_proposal_card\"",
        "\"drift_contract\"",
        "\"rebalance_suggestion\"",
        "\"payment_proposal_update\"",
        "\"requires_user_action\":true",
        "\"replay_summary\"",
    }) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, json, needle) != null);
    }
}
