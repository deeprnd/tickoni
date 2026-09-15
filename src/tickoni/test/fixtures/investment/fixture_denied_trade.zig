const std = @import("std");
const thesis = @import("thesis");
const fixture_paths = @import("fixture_paths");

const operations_account_id: u32 = 2001;

const RestrictedTicketWire = struct {
    ticket_id: []const u8,
    requested_symbols: []const []const u8,
    recognized_symbols: []const []const u8,
    policy_outcome: []const u8,
    approval_state: []const u8,
    blocked_reasons: []const struct {
        code: []const u8,
        failed_scope_dim: []const u8,
        user_message: []const u8,
    },
    paper_execution: ?std.json.Value = null,
};

const LoadedRestrictedTicketFixture = struct {
    raw: []u8,
    parsed: std.json.Parsed(RestrictedTicketWire),

    fn deinit(self: *LoadedRestrictedTicketFixture, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.raw);
    }
};

fn operationsThesisInputWithTarget(target_notional_cents: i64) thesis.ThesisInput {
    var input = thesis.fixtures.ai_infrastructure;
    input.account_id = operations_account_id;
    input.target_notional_cents = target_notional_cents;
    input.max_single_name_pct = 25;
    return input;
}

fn loadRestrictedTicketFixture(allocator: std.mem.Allocator, io: std.Io) !LoadedRestrictedTicketFixture {
    const raw = try fixture_paths.readFixtureFile(
        allocator,
        io,
        fixture_paths.investment_scenarios,
        "fixture_ticket_restricted_instrument_blocked.json",
        16 * 1024,
    );
    errdefer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(RestrictedTicketWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    return .{
        .raw = raw,
        .parsed = parsed,
    };
}

test "denied_trade: malformed thesis without target amount fails closed" {
    const input = operationsThesisInputWithTarget(0);
    try std.testing.expectError(thesis.ThesisError.MissingTargetAmount, thesis.normalize(input));
}

test "denied_trade: malformed thesis with unsupported-only asset classes fails closed" {
    var input = operationsThesisInputWithTarget(200_000);
    input.instrument_type_prefs = thesis.instrumentTypeList(.{.option});
    try std.testing.expectError(thesis.ThesisError.NoEligibleInstrumentType, thesis.normalize(input));
}

test "denied_trade: restricted ticket fixture stays explicit and not placeable" {
    var loaded = try loadRestrictedTicketFixture(std.testing.allocator, std.testing.io);
    defer loaded.deinit(std.testing.allocator);

    const ticket = loaded.parsed.value;
    try std.testing.expectEqual(@as(usize, 0), ticket.ticket_id.len);
    try std.testing.expectEqualStrings("deny", ticket.policy_outcome);
    try std.testing.expectEqualStrings("not_placeable", ticket.approval_state);
    try std.testing.expectEqual(@as(usize, 1), ticket.requested_symbols.len);
    try std.testing.expectEqualStrings("SOXL", ticket.requested_symbols[0]);
    try std.testing.expectEqual(@as(usize, 0), ticket.recognized_symbols.len);
    try std.testing.expectEqual(@as(usize, 1), ticket.blocked_reasons.len);
    try std.testing.expectEqualStrings("restricted_instrument", ticket.blocked_reasons[0].code);
    try std.testing.expectEqualStrings("restricted_instrument", ticket.blocked_reasons[0].failed_scope_dim);
    try std.testing.expect(std.mem.indexOf(u8, ticket.blocked_reasons[0].user_message, "leveraged ETF") != null);
    try std.testing.expect(ticket.paper_execution == null);
}
