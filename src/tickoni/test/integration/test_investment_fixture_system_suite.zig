const std = @import("std");
const investment_fixture = @import("investment_fixture");
const support = @import("investment_support");

pub fn runSystemSuite(
    allocator: std.mem.Allocator,
    io: std.Io,
    live_config: investment_fixture.LiveConfig,
) !void {
    const input = support.operationsThesisInput();
    var live_result = if (live_config.use_fixture)
        try investment_fixture.runFixtureModel(allocator, input)
    else
        try investment_fixture.runLiveModel(allocator, io, live_config, input);
    std.debug.print("=== runSystemSuite: model path={s} ===\n", .{
        if (live_config.use_fixture) "fixture" else "live",
    });
    defer live_result.deinit(allocator);
    std.debug.print(
        "=== Live tkmodl ===\nendpoint={s}\nmodel={s}\nmatched_ticker={s}\nexcerpt={s}\n",
        .{ live_config.endpoint, live_result.model_id, live_result.matched_ticker, live_result.excerpt },
    );

    const allowed = try investment_fixture.runAllowedTradeScenario(allocator, io, input);
    std.debug.print(
        "=== Allowed USD 2,000 ===\naccount={d} ticket={s} cost_cents={d}\n",
        .{ allowed.ticket.account_id, allowed.ticket.ticketIdSlice(), allowed.ticket.estimated_cost_cents },
    );
    std.debug.print(
        "=== Replay ===\nmatch={s} external_effects_disabled={s}\n",
        .{
            if (allowed.replay_result.replay_match) "true" else "false",
            if (allowed.replay_result.external_effects_disabled) "true" else "false",
        },
    );
    const decision_payload_json = try investment_fixture.allocAllowedTradeInterfaceJson(allocator, &allowed);
    defer allocator.free(decision_payload_json);
    std.debug.print("=== Decision Payload ===\n{s}\n", .{decision_payload_json});

    const blocked = try investment_fixture.runOversizedTradeScenario(
        allocator,
        io,
        support.operationsThesisInputWithTarget(support.oversized_target_notional_cents),
    );
    std.debug.print(
        "=== Blocked USD 25,000 ===\nticket={s} reason={s} effective_max_cents={d}\n",
        .{
            blocked.ticket.ticketIdSlice(),
            blocked.ticket.blocked_reasons[0].code.label(),
            blocked.ticket.affordability_result.effective_max_paper_trade_cents,
        },
    );

    const restricted = try investment_fixture.runRestrictedScenario(allocator, io, support.operationsRestrictedTickerInput());
    std.debug.print(
        "=== Restricted Instrument ===\nrequested={s} replay_match={s}\n",
        .{
            restricted.requested_ticker,
            if (restricted.replay_result.replay_match) "true" else "false",
        },
    );
}

test "system fixture live: full investment suite via fixture" {
    const allocator = std.testing.allocator;

    const live_config = investment_fixture.LiveConfig{
        .endpoint = investment_fixture.default_endpoint,
        .model_id = investment_fixture.default_model_id,
        .use_fixture = true,
    };

    try runSystemSuite(allocator, std.testing.io, live_config);
}
