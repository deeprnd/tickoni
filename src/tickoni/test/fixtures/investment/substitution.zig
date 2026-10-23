const std = @import("std");
const diagnostic = @import("diagnostic");
const runner = @import("runner");

pub const Scenario = enum {
    allowed,
    oversized_blocked,
    restricted_instrument,
    tampered_replay,

    pub fn label(self: Scenario) []const u8 {
        return switch (self) {
            .allowed => "allowed",
            .oversized_blocked => "oversized_blocked",
            .restricted_instrument => "restricted_instrument",
            .tampered_replay => "tampered_replay",
        };
    }
};

const fixtures_root = "src/tickoni/test/fixtures/investment/scenarios";
const allowed_audit = fixtures_root ++ "/fixture_audit_allowed_2000.jsonl";
const allowed_replay = fixtures_root ++ "/fixture_replay_capsule.json";
const oversized_replay = fixtures_root ++ "/fixture_replay_capsule_oversized_25000.json";
const restricted_replay = fixtures_root ++ "/fixture_replay_capsule_restricted_soxl.json";
const tampered_replay = fixtures_root ++ "/fixture_replay_capsule_tampered_paper_fill.json";

pub fn backendForScenario(scenario: Scenario) runner.BackendResult {
    return switch (scenario) {
        .allowed => .{
            .fixture_set_id = "investment_sample",
            .scenario = scenario.label(),
            .policy_outcome = "allow",
            .proposal_material = "proposal_hash_ticket_ai_infra_2000_market",
            .normalized_event_material = "fixture_audit_allowed_2000",
            .audit_jsonl_path = allowed_audit,
            .replay_capsule_path = allowed_replay,
            .replay_result = .{ .replay_match = true, .divergence_count = 0 },
            .external_effects_disabled = true,
        },
        .oversized_blocked => .{
            .fixture_set_id = "investment_sample",
            .scenario = scenario.label(),
            .policy_outcome = "deny",
            .proposal_material = "proposal_hash_ticket_ai_infra_25000_blocked",
            .normalized_event_material = "fixture_replay_capsule_oversized_25000",
            .audit_jsonl_path = "",
            .replay_capsule_path = oversized_replay,
            .replay_result = .{ .replay_match = true, .divergence_count = 0 },
            .blocked_diagnostic = .{
                .code = .policy_denied,
                .message = "per-order notional guardrail denied the oversized trade",
                .field = "failed_scope_dim",
                .expected = "per_order_notional",
                .found = "per_order_notional",
            },
            .external_effects_disabled = true,
        },
        .restricted_instrument => .{
            .fixture_set_id = "investment_sample",
            .scenario = scenario.label(),
            .policy_outcome = "deny",
            .proposal_material = "",
            .normalized_event_material = "fixture_replay_capsule_restricted_soxl",
            .audit_jsonl_path = "",
            .replay_capsule_path = restricted_replay,
            .replay_result = .{ .replay_match = true, .divergence_count = 0 },
            .blocked_diagnostic = .{
                .code = .restricted_instrument,
                .message = "restricted leveraged ETF request was denied",
                .field = "requested_symbols",
                .expected = "US-listed large-cap equities and ETFs without restricted instruments",
                .found = "SOXL",
            },
            .external_effects_disabled = true,
        },
        .tampered_replay => .{
            .fixture_set_id = "investment_sample",
            .scenario = scenario.label(),
            .policy_outcome = "allow",
            .proposal_material = "proposal_hash_ticket_ai_infra_2000_market",
            .normalized_event_material = "fixture_replay_capsule_tampered_paper_fill",
            .audit_jsonl_path = allowed_audit,
            .replay_capsule_path = tampered_replay,
            .replay_result = .{ .replay_match = false, .divergence_count = 1, .first_divergent_seq = 9 },
            .blocked_diagnostic = .{
                .code = .tampered_replay_artifact,
                .message = "replay capsule fixture was tampered and must fail closed",
                .field = "replay_capsule_path",
                .expected = allowed_replay,
                .found = tampered_replay,
            },
            .external_effects_disabled = true,
        },
    };
}

test "all scenario backends point at existing replay fixtures" {
    const cwd = std.Io.Dir.cwd();
    for ([_]Scenario{ .allowed, .oversized_blocked, .restricted_instrument, .tampered_replay }) |scenario| {
        const backend = backendForScenario(scenario);
        try cwd.access(std.testing.io, backend.replay_capsule_path, .{});
    }
}

test "allowed scenario exposes audit evidence" {
    const backend = backendForScenario(.allowed);
    try std.testing.expectEqualStrings("allow", backend.policy_outcome);
    try std.testing.expect(backend.audit_jsonl_path.len > 0);
    try std.testing.expect(backend.blocked_diagnostic == null);
}

test "blocked scenarios carry stable diagnostics" {
    const oversized = backendForScenario(.oversized_blocked);
    try std.testing.expectEqual(diagnostic.Code.policy_denied, oversized.blocked_diagnostic.?.code);

    const restricted = backendForScenario(.restricted_instrument);
    try std.testing.expectEqual(diagnostic.Code.restricted_instrument, restricted.blocked_diagnostic.?.code);

    const tampered = backendForScenario(.tampered_replay);
    try std.testing.expectEqual(diagnostic.Code.tampered_replay_artifact, tampered.blocked_diagnostic.?.code);
    try std.testing.expect(!tampered.replay_result.replay_match);
}
