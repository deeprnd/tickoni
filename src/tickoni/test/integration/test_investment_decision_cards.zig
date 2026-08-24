const demo = @import("investment_demo");
const support = @import("investment_support");
const std = @import("std");

test "investment_decision_cards_integration: allowed demo exposes decision cards and drift contract" {
    const result = try demo.runAllowedTradeScenario(std.testing.allocator, std.testing.io, support.operationsThesisInput());

    try std.testing.expectEqual(result.basket.basket_id, result.decision_cards.thesis_card.basket_id);
    try std.testing.expect(result.decision_cards.thesis_card.linked_position_count > 0);
    try std.testing.expect(result.decision_cards.thesis_card.linked_positions[0].evidence_hash != 0);
    try std.testing.expectEqualStrings("supplier_acme_us", result.decision_cards.money_proposal_card.beneficiarySlice());
    try std.testing.expectEqualStrings("payment_failed", result.decision_cards.money_proposal_card.sourceEventSlice());
    try std.testing.expectEqualStrings("USD", result.decision_cards.money_proposal_card.currencySlice());
    try std.testing.expect(result.decision_cards.money_proposal_card.evidence_hash != 0);
    try std.testing.expect(result.drift_contract.thesis_drift.has_drift);
    try std.testing.expect(result.drift_contract.payment_drift.has_drift);
    try std.testing.expect(result.drift_contract.rebalance_suggestion.requires_user_action);
    try std.testing.expect(result.drift_contract.payment_proposal_update.requires_user_action);

    const json = try demo.allocAllowedTradeInterfaceJson(std.testing.allocator, &result);
    defer std.testing.allocator.free(json);

    const ContractWire = struct {
        schema_version: u16,
        decision_cards: struct {
            thesis_card: struct {
                linked_positions: []const struct {
                    ticker: []const u8,
                    rationale: []const u8,
                    evidence_hash: u64,
                    allocation_cents: i64,
                },
                current_exposure_bp: u32,
            },
            money_proposal_card: struct {
                beneficiary: []const u8,
                source_event: []const u8,
                rail: []const u8,
                approval_state: []const u8,
                evidence_hash: u64,
            },
        },
        drift_contract: struct {
            rebalance_suggestion: struct {
                status: []const u8,
                requires_user_action: bool,
                adjustments: []const struct {
                    ticker: []const u8,
                    direction: []const u8,
                    current_weight_bp: u32,
                    target_weight_bp: u32,
                },
            },
            payment_proposal_update: struct {
                suggested_status: []const u8,
                action_class: []const u8,
                approval_path: []const u8,
                policy_version: []const u8,
                requires_user_action: bool,
            },
        },
        replay_summary: struct {
            replay_match: bool,
            external_effects_disabled: bool,
        },
    };

    const parsed = try std.json.parseFromSlice(ContractWire, std.testing.allocator, json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u16, 1), parsed.value.schema_version);
    try std.testing.expectEqual(@as(usize, result.decision_cards.thesis_card.linked_position_count), parsed.value.decision_cards.thesis_card.linked_positions.len);
    try std.testing.expectEqualStrings("supplier_acme_us", parsed.value.decision_cards.money_proposal_card.beneficiary);
    try std.testing.expectEqualStrings("payment_failed", parsed.value.decision_cards.money_proposal_card.source_event);
    try std.testing.expectEqualStrings("ach", parsed.value.decision_cards.money_proposal_card.rail);
    try std.testing.expectEqualStrings("pending", parsed.value.decision_cards.money_proposal_card.approval_state);
    try std.testing.expectEqualStrings("proposed", parsed.value.drift_contract.rebalance_suggestion.status);
    try std.testing.expect(parsed.value.drift_contract.rebalance_suggestion.adjustments.len > 0);
    try std.testing.expectEqualStrings("payment_retry.propose", parsed.value.drift_contract.payment_proposal_update.action_class);
    try std.testing.expectEqualStrings("maker_checker", parsed.value.drift_contract.payment_proposal_update.approval_path);
    try std.testing.expectEqualStrings("tickoni.v1", parsed.value.drift_contract.payment_proposal_update.policy_version);
    try std.testing.expect(parsed.value.replay_summary.replay_match);
    try std.testing.expect(parsed.value.replay_summary.external_effects_disabled);
}
