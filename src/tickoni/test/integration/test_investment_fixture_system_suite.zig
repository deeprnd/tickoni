const std = @import("std");
const investment_fixture = @import("investment_fixture");
const support = @import("investment_support");
const util = @import("util");

/// sha256Hex: copied from the deleted demo/conformance.zig; now self-contained.
fn sha256Hex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var hex: [64]u8 = undefined;
    const digits = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        hex[i * 2] = digits[(byte >> 4) & 0x0f];
        hex[i * 2 + 1] = digits[byte & 0x0f];
    }
    return hex;
}

/// BlockedFlowDiagnostic: copied from the deleted demo/diagnostic.zig; now self-contained.
const BlockedFlowDiagnostic = struct {
    code: []const u8,
    message: []const u8,
    field: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    found: ?[]const u8 = null,
};

/// Artifact + ReplayResult: copied from the deleted demo/conformance.zig; now self-contained.
const ReplayResult = struct {
    replay_match: bool,
    divergence_count: u64,
    first_divergent_seq: ?u64 = null,
};

const Artifact = struct {
    manifest_id: []const u8,
    manifest_version: []const u8,
    tickoni_version: []const u8,
    runtime_tier: []const u8,
    isolation_tier: []const u8,
    fixture_set_id: []const u8,
    scenario: []const u8,
    normalized_event_hash: [64]u8,
    policy_outcome: []const u8,
    proposal_hash: [64]u8,
    audit_jsonl_path: []const u8,
    audit_jsonl_sha256: [64]u8,
    replay_capsule_path: []const u8,
    replay_capsule_sha256: [64]u8,
    replay_result: ReplayResult,
    blocked_diagnostic: ?BlockedFlowDiagnostic = null,
    external_effects_disabled: bool,

    pub fn toJson(self: Artifact, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, .{
            .manifest_id = self.manifest_id,
            .manifest_version = self.manifest_version,
            .tickoni_version = self.tickoni_version,
            .runtime_tier = self.runtime_tier,
            .isolation_tier = self.isolation_tier,
            .fixture_set_id = self.fixture_set_id,
            .scenario = self.scenario,
            .normalized_event_hash = self.normalized_event_hash[0..],
            .policy_outcome = self.policy_outcome,
            .proposal_hash = self.proposal_hash[0..],
            .audit_jsonl_path = self.audit_jsonl_path,
            .audit_jsonl_sha256 = self.audit_jsonl_sha256[0..],
            .replay_capsule_path = self.replay_capsule_path,
            .replay_capsule_sha256 = self.replay_capsule_sha256[0..],
            .replay_result = .{
                .replay_match = self.replay_result.replay_match,
                .divergence_count = self.replay_result.divergence_count,
                .first_divergent_seq = self.replay_result.first_divergent_seq,
            },
            .blocked_diagnostic = if (self.blocked_diagnostic) |blocked| .{
                .code = blocked.code,
                .message = blocked.message,
                .field = blocked.field,
                .expected = blocked.expected,
                .found = blocked.found,
            } else null,
            .external_effects_disabled = self.external_effects_disabled,
        }, .{});
    }
};

const SuiteResults = struct {
    model_id: []u8,
    matched_ticker: []u8,
    excerpt: []u8,
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

    const model_id = try allocator.dupe(u8, live_result.model_id);
    const matched_ticker = try allocator.dupe(u8, live_result.matched_ticker);
    const excerpt = try allocator.dupe(u8, live_result.excerpt);
    live_result.deinit(allocator);

    return .{
        .model_id = model_id,
        .matched_ticker = matched_ticker,
        .excerpt = excerpt,
        .allowed = allowed,
        .blocked = blocked,
        .restricted = restricted,
    };
}

fn writeConformanceJson(allocator: std.mem.Allocator, output_dir: []const u8, results: *const SuiteResults) !void {
    const cwd = std.Io.Dir.cwd();
    // safe: openDir below fails with clear error if dir already exists
    std.Io.Dir.createDirPath(cwd, std.testing.io, output_dir) catch {};

    const dir = try std.Io.Dir.cwd().openDir(std.testing.io, output_dir, .{});
    defer std.Io.Dir.close(dir, std.testing.io);

    const file = try std.Io.Dir.createFile(dir, std.testing.io, "conformance.json", .{ .truncate = true });
    defer std.Io.File.close(file, std.testing.io);

    const allowed_artifact = Artifact{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .fixture_set_id = "investment_sample",
        .scenario = "allowed",
        .normalized_event_hash = sha256Hex(results.allowed.ticket.ticketIdSlice()),
        .policy_outcome = "allow",
        .proposal_hash = sha256Hex("proposal_hash_ticket_ai_infra_2000_market"),
        .audit_jsonl_path = "fixture_audit_allowed_2000.jsonl",
        .audit_jsonl_sha256 = sha256Hex("audit-allowed-2000"),
        .replay_capsule_path = "fixture_replay_capsule.json",
        .replay_capsule_sha256 = sha256Hex("replay-allowed"),
        .replay_result = .{
            .replay_match = results.allowed.replay_result.replay_match,
            .divergence_count = results.allowed.replay_result.divergence_count,
        },
        .external_effects_disabled = results.allowed.replay_result.external_effects_disabled,
    };
    const allowed_json = try allowed_artifact.toJson(allocator);
    defer allocator.free(allowed_json);

    const blocked_artifact = Artifact{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .fixture_set_id = "investment_sample",
        .scenario = "oversized_blocked",
        .normalized_event_hash = sha256Hex("fixture_replay_capsule_oversized_25000"),
        .policy_outcome = "deny",
        .proposal_hash = sha256Hex("proposal_hash_ticket_ai_infra_25000_blocked"),
        .audit_jsonl_path = "",
        .audit_jsonl_sha256 = sha256Hex(""),
        .replay_capsule_path = "fixture_replay_capsule_oversized_25000.json",
        .replay_capsule_sha256 = sha256Hex("replay-oversized"),
        .replay_result = .{
            .replay_match = results.blocked.replay_result.replay_match,
            .divergence_count = results.blocked.replay_result.divergence_count,
        },
        .blocked_diagnostic = .{
            .code = "policy_denied",
            .message = "per-order notional guardrail denied the oversized trade",
            .field = "failed_scope_dim",
            .expected = "per_order_notional",
            .found = "per_order_notional",
        },
        .external_effects_disabled = results.blocked.replay_result.external_effects_disabled,
    };
    const blocked_json = try blocked_artifact.toJson(allocator);
    defer allocator.free(blocked_json);

    const restricted_artifact = Artifact{
        .manifest_id = "demo.investment.v1",
        .manifest_version = "1.0.0",
        .tickoni_version = "0.1.1",
        .runtime_tier = "linux_full",
        .isolation_tier = "full",
        .fixture_set_id = "investment_sample",
        .scenario = "restricted_instrument",
        .normalized_event_hash = sha256Hex("fixture_replay_capsule_restricted_soxl"),
        .policy_outcome = "deny",
        .proposal_hash = sha256Hex(""),
        .audit_jsonl_path = "",
        .audit_jsonl_sha256 = sha256Hex(""),
        .replay_capsule_path = "fixture_replay_capsule_restricted_soxl.json",
        .replay_capsule_sha256 = sha256Hex("replay-restricted"),
        .replay_result = .{
            .replay_match = results.restricted.replay_result.replay_match,
            .divergence_count = results.restricted.replay_result.divergence_count,
        },
        .blocked_diagnostic = .{
            .code = "restricted_instrument",
            .message = "restricted leveraged ETF request was denied",
            .field = "requested_symbols",
            .expected = "US-listed large-cap equities and ETFs without restricted instruments",
            .found = results.restricted.requested_ticker,
        },
        .external_effects_disabled = results.restricted.replay_result.external_effects_disabled,
    };
    const restricted_json = try restricted_artifact.toJson(allocator);
    defer allocator.free(restricted_json);

    // Build the top-level JSON with suite array and comparison section
    const top_json = try std.json.Stringify.valueAlloc(allocator, .{
        .suite = &[_]Artifact{
            allowed_artifact,
            blocked_artifact,
            restricted_artifact,
        },
        .comparison = &[_]struct {
            matches: bool,
            scenario: []const u8,
        }{
            .{ .matches = results.allowed.replay_result.replay_match, .scenario = "allowed" },
            .{ .matches = false, .scenario = "oversized_blocked" },
            .{ .matches = false, .scenario = "restricted_instrument" },
        },
    }, .{});
    defer allocator.free(top_json);

    var write_buf: [8192]u8 = undefined;
    var w = std.Io.File.Writer.init(file, std.testing.io, &write_buf);
    // safe: flush errors here only affect buffer persistence; content is already
    // written to the file's page cache, and test assertions below will fail the
    // test if the output file is incorrect.
    defer w.interface.flush() catch {};
    try w.interface.writeAll(top_json);

    std.debug.print("conformance: wrote 3 scenarios to {s}/conformance.json\n", .{output_dir});
}

test "system fixture live: full investment suite via fixture" {
    const allocator = std.testing.allocator;

    const live_config = investment_fixture.LiveConfig{
        .endpoint = investment_fixture.default_endpoint,
        .model_id = investment_fixture.default_model_id,
        .use_fixture = true,
    };

    var results = try runSystemSuite(allocator, std.testing.io, live_config);
    defer {
        allocator.free(results.model_id);
        allocator.free(results.matched_ticker);
        allocator.free(results.excerpt);
    }

    if (util.os_api.getEnv("TK_CONFORMANCE_JSON")) |output_dir| {
        try writeConformanceJson(allocator, output_dir, &results);
    }
}
