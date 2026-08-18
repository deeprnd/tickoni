const std = @import("std");
const builtin = @import("builtin");
const adapter = @import("adapter");
const audit = @import("audit_tile");
const demo = @import("investment_demo");
const investment_audit = @import("investment_audit");
const model = @import("model");
const replay = @import("replay");
const thesis = @import("thesis");
const support = @import("investment_support");
const tkagnt = @import("tkagnt");
const tkcase = @import("tkcase");
const tkdisp = @import("tkdisp");
const tkpoly = @import("tkpoly");

/// Helper to check if an env var is set, using the global environ.
/// On Windows, std.c.environ is not available (it's POSIX-only), so we
/// always return false (tests are fixture-based anyway).
fn hasEnv(key: []const u8) bool {
    if (builtin.os.tag == .windows) return false;
    const env = std.c.environ;
    var count: usize = 0;
    while (env[count] != null) : (count += 1) {}
    for (env[0..count]) |entry| {
        if (entry) |e| {
            const kv = std.mem.span(e);
            if (std.mem.startsWith(u8, kv, key) and kv.len > key.len and kv[key.len] == '=') {
                return true;
            }
        }
    }
    return false;
}

test "investment_replay_integration: succeeds with fixture substitutions and no live effects" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
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
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const allowed_result = try demo.runAllowedTradeScenario(allocator, std.testing.io, input);
    const replay_result = allowed_result.replay_result;
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 0), replay_result.divergence_count);
    try std.testing.expectEqualStrings("", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 0), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &allowed_result.drift_contract,
        &replay_result,
    );
    try std.testing.expectEqual(investment_audit.allowed_trade_event_count, audit_chain.slice().len);
    try std.testing.expectEqual(audit.RecordType.source_event, std.meta.activeTag(audit_chain.events[0].payload));
    try std.testing.expectEqual(audit.RecordType.deduplication, std.meta.activeTag(audit_chain.events[2].payload));
    try std.testing.expectEqual(audit.RecordType.case_creation, std.meta.activeTag(audit_chain.events[3].payload));
    try std.testing.expectEqual(audit.RecordType.proposal, std.meta.activeTag(audit_chain.events[11].payload));
    try std.testing.expectEqual(audit.RecordType.approval_required, std.meta.activeTag(audit_chain.events[12].payload));
    try std.testing.expectEqual(audit.RecordType.replay_result, std.meta.activeTag(audit_chain.events[14].payload));
    try std.testing.expectEqual(run_id, audit_chain.events[0].header.run_id);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[0].header.prev_hash);
    for (audit_chain.events[1..], 1..) |event, i| {
        try std.testing.expectEqual(audit_chain.events[i - 1].header.record_hash, event.header.prev_hash);
    }
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[14].payload.replay_result.divergences);
    try std.testing.expectEqual(@as(u64, 0), audit_chain.events[14].payload.replay_result.first_divergent_seq);
}

test "investment_replay_integration: allowed trade audit chain hashes are real and deterministic" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
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
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);
    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const allowed_result = try demo.runAllowedTradeScenario(allocator, std.testing.io, input);
    const no_divergence = allowed_result.replay_result;
    const chain = investment_audit.buildAllowedTradeChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &allowed_result.drift_contract,
        &no_divergence,
    );

    // Every record_hash must be a real computed value, not an unset zero.
    for (chain.events) |event| {
        try std.testing.expect(event.header.record_hash != 0);
        try std.testing.expectEqual(run_id, event.header.run_id);
    }

    // Tile ID at each sequence position must match the owning tile.
    const expected_tile_ids = [investment_audit.allowed_trade_event_count][]const u8{
        "tkings", "tknorm", "tkdedu", "tkcase", "tkpoly",
        "tkmodl", "tkadpt", "tkadpt", "tkagnt", "tkadpt",
        "tkpoly", "tkagnt", "tkpoly", "tkagnt", "tkrepl",
    };
    for (chain.events, expected_tile_ids) |event, expected| {
        try std.testing.expectEqualStrings(expected, std.mem.sliceTo(&event.header.tile_id, 0));
    }

    // Key payload hash fields must carry real content (non-zero).
    try std.testing.expect(chain.events[0].payload.source_event.raw_hash != 0);
    try std.testing.expect(chain.events[1].payload.normalization.normalized_hash != 0);
    try std.testing.expect(chain.events[2].payload.deduplication.idempotency_key != 0);
    try std.testing.expect(chain.events[3].payload.case_creation.basket_id != 0);
    try std.testing.expect(chain.events[5].payload.model_call.response_hash != 0);
    try std.testing.expect(chain.events[6].payload.financial_adapter_call.response_hash != 0);
    try std.testing.expect(chain.events[7].payload.financial_adapter_call.response_hash != 0);
    try std.testing.expect(chain.events[8].payload.proposal.proposal_hash != 0);
    try std.testing.expect(chain.events[9].payload.financial_adapter_call.response_hash != 0);
    try std.testing.expect(chain.events[10].payload.policy_decision.source_event_hash != 0);
    try std.testing.expect(chain.events[11].payload.proposal.proposal_hash != 0);
    try std.testing.expect(chain.events[12].payload.approval_required.proposal_hash != 0);
    try std.testing.expect(chain.events[13].payload.proposal.proposal_hash != 0);
    try std.testing.expect(chain.events[14].payload.replay_result.capsule_id != 0);

    // The chain is deterministic: identical inputs must produce identical record_hash values.
    const chain2 = investment_audit.buildAllowedTradeChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &allowed_result.drift_contract,
        &no_divergence,
    );
    for (chain.events, chain2.events) |e1, e2| {
        try std.testing.expectEqual(e1.header.record_hash, e2.header.record_hash);
    }
}

test "investment_replay_integration: tamper detection reports first divergent hash and sequence" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
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
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);

    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;

    const allowed_result = try demo.runAllowedTradeScenario(allocator, std.testing.io, input);
    const replay_result = try replay.verifyAllowedTradeWithCapsulePath(
        allocator,
        std.testing.io,
        support.tampered_replay_capsule_path,
        &model_backend,
        &adapter_backend,
        &basket,
        &agent_result.ticket,
        &allowed_result.drift_contract,
    );
    try std.testing.expect(replay_result.external_effects_disabled);
    try std.testing.expect(!replay_result.replay_match);
    try std.testing.expectEqual(@as(u64, 1), replay_result.divergence_count);
    try std.testing.expectEqualStrings("adapter_response_hash", replay_result.first_divergent_field);
    try std.testing.expectEqual(@as(u64, 7), replay_result.first_divergent_seq);

    const audit_chain = investment_audit.buildAllowedTradeChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &allowed_result.drift_contract,
        &replay_result,
    );
    try std.testing.expectEqual(@as(u64, 1), audit_chain.events[14].payload.replay_result.divergences);
    try std.testing.expectEqual(@as(u64, 7), audit_chain.events[14].payload.replay_result.first_divergent_seq);
}

test "gen audit allowed trade jsonl" {
    if (hasEnv("TK_GEN_FIXTURES") == false) return error.SkipZigTest;
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
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
        support.expected_ticket_id,
    );
    defer agent_result.deinit(allocator);
    const execution = agent_result.paper_result orelse return error.TestUnexpectedResult;
    const allowed_result = try demo.runAllowedTradeScenario(allocator, std.testing.io, input);
    const no_divergence = allowed_result.replay_result;
    const chain = investment_audit.buildAllowedTradeChain(
        run_id,
        "ops_reviewer",
        "trading_control",
        &input,
        &basket,
        &agent_result.quote_snapshot,
        agent_result.affordability,
        &agent_result.model_response,
        &agent_result.ticket,
        &execution,
        &allowed_result.drift_contract,
        &no_divergence,
    );

    const path = "src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl";
    const file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{ .truncate = true });
    defer std.Io.File.close(file, std.testing.io);

    var write_buf: [4096]u8 = undefined;
    var w = std.Io.File.Writer.init(file, std.testing.io, &write_buf);
    defer w.interface.flush() catch {};

    for (chain.events) |event| {
        var line_buf: [4096]u8 = undefined;
        var lw = std.Io.Writer.fixed(&line_buf);
        try audit.formatJsonLine(event, &lw);
        try w.interface.writeAll(lw.buffered());
    }
}

test "investment_replay_integration: audit jsonl hash chain is consistent" {
    const allocator = std.testing.allocator;
    const input = support.operationsThesisInput();
    const thesis_id = thesis.computeThesisInputHash(input);
    const run_id = tkcase.deriveSyntheticRunId(thesis_id);

    const raw = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios/fixture_audit_allowed_2000.jsonl",
        allocator,
        .limited(64 * 1024),
    );
    defer allocator.free(raw);

    const AuditLine = struct { run_id: u64, tile_id: []const u8, prev_hash: u64, record_hash: u64 };

    const expected_tile_ids = [investment_audit.allowed_trade_event_count][]const u8{
        "tkings", "tknorm", "tkdedu", "tkcase", "tkpoly",
        "tkmodl", "tkadpt", "tkadpt", "tkagnt", "tkadpt",
        "tkpoly", "tkagnt", "tkpoly", "tkagnt", "tkrepl",
    };

    var lines = std.mem.tokenizeScalar(u8, raw, '\n');
    var idx: usize = 0;
    var prev_record_hash: u64 = 0;
    while (lines.next()) |line| {
        const parsed = try std.json.parseFromSlice(AuditLine, allocator, line, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        try std.testing.expectEqual(run_id, parsed.value.run_id);
        try std.testing.expectEqual(prev_record_hash, parsed.value.prev_hash);
        try std.testing.expectEqualStrings(expected_tile_ids[idx], parsed.value.tile_id);
        prev_record_hash = parsed.value.record_hash;
        idx += 1;
    }
    try std.testing.expectEqual(investment_audit.allowed_trade_event_count, idx);
}
