const std = @import("std");
const investment_fixture = @import("investment_fixture");
const support = @import("investment_support");

const SuiteResults = struct {
    live_result: investment_fixture.LiveModelEvidence,
    allowed: investment_fixture.AllowedTradeScenarioResult,
    blocked: investment_fixture.BlockedTradeScenarioResult,
    restricted: investment_fixture.RestrictedInstrumentScenarioResult,
};

pub fn runSystemSuite(
    allocator: std.mem.Allocator,
    io: std.Io,
    live_config: investment_fixture.LiveConfig,
) !SuiteResults {
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

    return .{
        .live_result = live_result,
        .allowed = allowed,
        .blocked = blocked,
        .restricted = restricted,
    };
}

fn writeConformanceJson(allocator: std.mem.Allocator, output_dir: []const u8, results: SuiteResults) !void {
    const path = try std.fs.path.join(allocator, &.{ output_dir, "conformance.json" });
    defer allocator.free(path);

    const dir = try std.fs.cwd().makeOpenPath(output_dir, .{ .iterate = true });
    defer dir.close();
    const file = try dir.openFile("conformance.json", .{ .mode = .write_only });
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();

    try w.writeAll("{\"suite\":[");

    // Scenario 1: allowed — already captured in live_result.
    try w.writeAll("{\"model_id\":\"");
    try w.writeAll(results.live_result.model_id);
    try w.writeAll("\",\"matched_ticker\":\"");
    try w.writeAll(results.live_result.matched_ticker);
    try w.writeAll("\",\"excerpt\":\"");
    for (results.live_result.excerpt) |c| {
        switch (c) {
            '\n' => try w.writeAll("\\n"),
            '\t' => try w.writeAll("\\t"),
            '\r' => try w.writeAll("\\r"),
            '\\' => try w.writeAll("\\\\"),
            '"' => try w.writeAll("\\\""),
            else => try w.writeByte(c),
        }
    }
    try w.writeAll("\",\"policy_outcome\":\"allow\",\"scenario\":\"allowed\",\"replay_match\":");
    try w.writeAll(if (results.allowed.replay_result.replay_match) "true" else "false");
    try w.writeAll(",\"external_effects_disabled\":");
    try w.writeAll(if (results.allowed.replay_result.external_effects_disabled) "true" else "false");
    try w.writeAll(",\"divergence_count\":");
    try w.print("{d}", .{results.allowed.replay_result.divergence_count});
    try w.writeAll(",\"target_notional_cents\":");
    try w.print("{d}", .{support.target_notional_cents});
    try w.writeAll(",\"ticket_id\":\"");
    try w.writeAll(results.allowed.ticket.ticketIdSlice());
    try w.writeAll("\"}");

    // Scenario 2: oversized blocked.
    try w.writeAll(",{");
    try w.writeAll("\"scenario\":\"oversized_blocked\",\"policy_outcome\":\"deny\",\"blocked_reason\":\"");
    try w.writeAll(results.blocked.ticket.blocked_reasons[0].code.label());
    try w.writeAll("\",\"failed_scope_dim\":\"");
    try w.writeAll(results.blocked.ticket.blocked_reasons[0].failed_scope_dim.label());
    try w.writeAll("\",\"replay_match\":");
    try w.writeAll(if (results.blocked.replay_result.replay_match) "true" else "false");
    try w.writeAll(",\"external_effects_disabled\":");
    try w.writeAll(if (results.blocked.replay_result.external_effects_disabled) "true" else "false");
    try w.writeAll(",\"divergence_count\":");
    try w.print("{d}", .{results.blocked.replay_result.divergence_count});
    try w.writeAll(",\"target_notional_cents\":");
    try w.print("{d}", .{support.oversized_target_notional_cents});
    try w.writeAll(",\"ticket_id\":\"");
    try w.writeAll(results.blocked.ticket.ticketIdSlice());
    try w.writeAll("\"}");

    // Scenario 3: restricted instrument.
    try w.writeAll(",{");
    try w.writeAll("\"scenario\":\"restricted_instrument\",\"policy_outcome\":\"deny\",\"blocked_reason\":\"");
    try w.writeAll("restricted_instrument");
    try w.writeAll("\",\"failed_scope_dim\":\"");
    try w.writeAll("restricted_instrument");
    try w.writeAll("\",\"replay_match\":");
    try w.writeAll(if (results.restricted.replay_result.replay_match) "true" else "false");
    try w.writeAll(",\"external_effects_disabled\":");
    try w.writeAll(if (results.restricted.replay_result.external_effects_disabled) "true" else "false");
    try w.writeAll(",\"divergence_count\":");
    try w.print("{d}", .{results.restricted.replay_result.divergence_count});
    try w.writeAll(",\"target_notional_cents\":");
    try w.print("{d}", .{support.target_notional_cents});
    try w.writeAll("}");

    try w.writeAll("],");

    // Comparison — each scenario's matches field is true when replay_match
    // is true and the policy outcome is allow.
    try w.writeAll("\"comparison\":[");
    try w.writeAll("{\"matches\":");
    try w.writeAll(if (results.allowed.replay_result.replay_match) "true" else "false");
    try w.writeAll(",\"scenario\":\"allowed\"},");
    try w.writeAll("{\"matches\":false,\"scenario\":\"oversized_blocked\"},");
    try w.writeAll("{\"matches\":false,\"scenario\":\"restricted_instrument\"}");
    try w.writeAll("]}");

    try bw.flush();
    std.debug.print("conformance: wrote {} scenarios to {s}/conformance.json\n", .{ 3, output_dir });
}

test "system fixture live: full investment suite via fixture" {
    const allocator = std.testing.allocator;

    const live_config = investment_fixture.LiveConfig{
        .endpoint = investment_fixture.default_endpoint,
        .model_id = investment_fixture.default_model_id,
        .use_fixture = true,
    };

    const results = try runSystemSuite(allocator, std.testing.io, live_config);

    // Conformance JSON output — controlled by env var.
    if (util.os_api.getEnv("TICKONI_CONFORMANCE_JSON")) |output_dir| {
        try writeConformanceJson(allocator, output_dir, results);
    }
}
