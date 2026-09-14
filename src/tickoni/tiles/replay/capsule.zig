/// Replay capsule wire format, version checking, and fixture-file loading.
/// Owns everything about the on-disk JSON artifact (capsule + substituted
/// model/adapter/paper-fill fixtures); mod.zig owns verification
/// orchestration over the loaded data — see finding 22 in
/// doc/strategy/roadmap/backlog/audits/tech_debt.md.
const std = @import("std");
const basket = @import("basket");
const trade_ticket = @import("trade_ticket");
const tkpoly = @import("tkpoly");
const hash = @import("hash.zig");
const fixture_paths = @import("fixture_paths");

/// Wire schema version of the replay capsule JSON format itself, distinct
/// from thesis/basket/catalog schema versions since the capsule is its own
/// artifact. Bump when the capsule's required-field shape changes.
pub const replay_capsule_schema_version: u16 = 1;

pub const ReplayCapsuleWire = struct {
    ticket_id: []const u8,
    // Compatibility fields: required (no default) so a capsule missing any
    // of these fails JSON parsing instead of silently defaulting. Checked
    // against the runtime's current versions in checkCapsuleVersions().
    schema_version: u16,
    catalog_schema_version: u16,
    taxonomy_version: u16,
    policy_version: []const u8,
    // T9 metadata: build/tier/manifest identity carried through replay so
    // replay output can be traced back to the exact build that produced it.
    version: ?[]const u8 = null,
    platform_tier: ?[]const u8 = null,
    isolation_tier: ?[]const u8 = null,
    release_digest: ?[]const u8 = null,
    demo_manifest_id: ?[]const u8 = null,
    expected_basket_id: ?u64 = null,
    expected_proposal_hash: ?u64 = null,
    expected_rebalance_hash: ?u64 = null,
    expected_payment_update_hash: ?u64 = null,
    model_substitutions: []const struct {
        request_hash: u64,
        response_hash: u64,
        fixture_file: []const u8,
    },
    adapter_substitutions: []const struct {
        adapter_id: []const u8,
        operation: []const u8,
        request_hash: u64,
        response_hash: u64,
        fixture_file: []const u8,
    },
    replay_assertions: struct {
        no_live_model_call: bool,
        no_live_adapter_call: bool,
        no_paper_fill_emitted: bool,
        affordability_outcome_matches: []const u8,
        policy_outcome_matches: []const u8,
        rebalance_requires_user_action: ?bool = null,
        payment_update_requires_user_action: ?bool = null,
        max_affordable_cents: ?i64 = null,
        effective_max_paper_trade_cents: ?i64 = null,
        blocked_reason_code_matches: ?[]const u8 = null,
        failed_scope_dim_matches: ?[]const u8 = null,
    },
};

pub const DivergenceTracker = struct {
    count: u64 = 0,
    first_field: []const u8 = "",
    first_seq: u64 = 0,

    pub fn note(self: *DivergenceTracker, field: []const u8, seq: u64) void {
        self.count += 1;
        if (self.first_seq == 0) {
            self.first_field = field;
            self.first_seq = seq;
        }
    }
};

pub const LoadedReplayCapsule = struct {
    raw: []u8,
    parsed: std.json.Parsed(ReplayCapsuleWire),

    pub fn deinit(self: *LoadedReplayCapsule, allocator: std.mem.Allocator) void {
        self.parsed.deinit();
        allocator.free(self.raw);
    }
};

pub fn loadReplayCapsule(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !LoadedReplayCapsule {
    const resolved = try fixture_paths.resolveFixtureFile(allocator, io, "", path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(
        io,
        resolved,
        allocator,
        .limited(16 * 1024),
    );
    allocator.free(resolved);
    errdefer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(ReplayCapsuleWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    return .{
        .raw = raw,
        .parsed = parsed,
    };
}

pub const CapsuleVersionError = error{UnsupportedCapsuleSchemaVersion};

/// Validate a loaded capsule's compatibility fields against the runtime's
/// current schema/catalog/taxonomy/policy versions.
///
/// schema_version identifies the capsule wire format itself; a mismatch means
/// the runtime cannot reliably interpret the capsule's other fields, so it is
/// a hard reject. catalog_schema_version, taxonomy_version, and policy_version
/// identify the classification/policy inputs that produced the capsule; a
/// mismatch there is real, reportable drift (the capsule is still parseable),
/// so it is recorded as a soft divergence like basket_id/proposal_hash
/// mismatches already are.
pub fn checkCapsuleVersions(capsule: ReplayCapsuleWire, divergences: *DivergenceTracker) CapsuleVersionError!void {
    if (capsule.schema_version != replay_capsule_schema_version) {
        return CapsuleVersionError.UnsupportedCapsuleSchemaVersion;
    }
    if (capsule.catalog_schema_version != basket.catalog.catalog_schema_version) {
        divergences.note("catalog_schema_version", 1);
    }
    if (capsule.taxonomy_version != basket.catalog.sector_taxonomy_version or
        capsule.taxonomy_version != basket.catalog.industry_taxonomy_version)
    {
        divergences.note("taxonomy_version", 1);
    }
    if (!std.mem.eql(u8, capsule.policy_version, tkpoly.trade_policy_version)) {
        divergences.note("policy_version", 1);
    }
}

pub fn hasAdapterOperation(capsule: ReplayCapsuleWire, operation: []const u8) bool {
    for (capsule.adapter_substitutions) |substitution| {
        if (std.mem.eql(u8, substitution.operation, operation)) return true;
    }
    return false;
}

pub fn findAdapterSubstitution(
    capsule: ReplayCapsuleWire,
    operation: []const u8,
) ?@TypeOf(capsule.adapter_substitutions[0]) {
    for (capsule.adapter_substitutions) |substitution| {
        if (std.mem.eql(u8, substitution.operation, operation)) return substitution;
    }
    return null;
}

pub fn fixtureDir(capsule_path: []const u8) []const u8 {
    const last_slash = std.mem.lastIndexOfScalar(u8, capsule_path, '/') orelse return ".";
    return capsule_path[0..last_slash];
}

const ModelFixtureContentWire = struct {
    content: std.json.Value,
};

pub const ModelFixtureContent = struct {
    len: usize,
    hash: u64,
};

pub fn loadModelFixtureContent(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
) !ModelFixtureContent {
    const resolved = try fixture_paths.resolveFixtureFile(allocator, io, fixture_dir, filename);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, resolved, allocator, .limited(32 * 1024));
    defer allocator.free(resolved);
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(ModelFixtureContentWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const content_json = try std.json.Stringify.valueAlloc(allocator, parsed.value.content, .{});
    defer allocator.free(content_json);
    return .{ .len = content_json.len, .hash = hash.hashBytes(content_json) };
}

fn parseQuantityMicros(s: []const u8) !u64 {
    const dot_pos = std.mem.indexOfScalar(u8, s, '.') orelse {
        const whole = try std.fmt.parseInt(u64, s, 10);
        return whole * 1_000_000;
    };
    const whole = try std.fmt.parseInt(u64, s[0..dot_pos], 10);
    const frac_str = s[dot_pos + 1 ..];
    var frac: u64 = 0;
    var multiplier: u64 = 100_000;
    for (frac_str) |c| {
        if (c < '0' or c > '9') return error.InvalidQuantity;
        frac += (c - '0') * multiplier;
        multiplier /= 10;
        if (multiplier == 0) break;
    }
    return whole * 1_000_000 + frac;
}

const PaperFillFixtureWire = struct {
    ticker: []const u8,
    quantity: []const u8,
    fill_price_cents: i64,
    filled_notional_cents: i64,
};

const PaperFixtureWire = struct {
    paper_order_id: []const u8,
    ticket_id: []const u8,
    total_filled_cents: i64,
    fills: []const PaperFillFixtureWire,
    resulting_account_snapshot: struct {
        cash_cents: i64,
        buying_power_cents: i64,
        day_notional_used_cents: i64,
        month_notional_used_cents: i64,
    },
};

pub fn loadPaperFixture(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
    account_id: u32,
) !trade_ticket.PaperExecutionResult {
    const resolved = try fixture_paths.resolveFixtureFile(allocator, io, fixture_dir, filename);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, resolved, allocator, .limited(32 * 1024));
    defer allocator.free(resolved);
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(PaperFixtureWire, allocator, raw, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const w = parsed.value;
    if (w.fills.len > basket.max_basket_instruments) return error.TooManyFills;
    var result: trade_ticket.PaperExecutionResult = std.mem.zeroes(trade_ticket.PaperExecutionResult);
    if (w.paper_order_id.len > trade_ticket.max_paper_order_id_len) return error.PaperOrderIdTooLong;
    result.paper_order_id_len = @intCast(w.paper_order_id.len);
    @memcpy(result.paper_order_id[0..result.paper_order_id_len], w.paper_order_id);
    if (w.ticket_id.len > trade_ticket.max_ticket_id_len) return error.TicketIdTooLong;
    result.ticket_id_len = @intCast(w.ticket_id.len);
    @memcpy(result.ticket_id[0..result.ticket_id_len], w.ticket_id);
    result.account_id = account_id;
    result.status = .filled;
    result.total_filled_cents = w.total_filled_cents;
    result.fill_count = @intCast(w.fills.len);
    for (w.fills, 0..) |wf, i| {
        if (wf.ticker.len > trade_ticket.max_ticker_len) return error.TickerTooLong;
        result.fills[i].ticker = std.mem.zeroes([trade_ticket.max_ticker_len]u8);
        @memcpy(result.fills[i].ticker[0..wf.ticker.len], wf.ticker);
        result.fills[i].ticker_len = @intCast(wf.ticker.len);
        result.fills[i].quantity_micros = try parseQuantityMicros(wf.quantity);
        result.fills[i].fill_price_cents = wf.fill_price_cents;
        result.fills[i].filled_notional_cents = wf.filled_notional_cents;
    }
    result.resulting_account_snapshot = .{
        .cash_cents = w.resulting_account_snapshot.cash_cents,
        .buying_power_cents = w.resulting_account_snapshot.buying_power_cents,
        .day_notional_used_cents = w.resulting_account_snapshot.day_notional_used_cents,
        .month_notional_used_cents = w.resulting_account_snapshot.month_notional_used_cents,
    };
    return result;
}
