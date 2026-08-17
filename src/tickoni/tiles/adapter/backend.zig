const std = @import("std");
const basket = @import("basket");
const portfolio = @import("portfolio");
const fixture_portfolio = @import("fixture_portfolio");
const trade_ticket = @import("trade_ticket");
const schema = @import("adapter_messages");

fn tickerBuf(comptime s: []const u8) [portfolio.max_ticker_len]u8 { var buf = std.mem.zeroes([portfolio.max_ticker_len]u8);
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

const fixture_quotes = [_]trade_ticket.Quote{ .{ .ticker = tickerBuf("NVDA"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 12_495, .ask_cents = 12_500, .last_cents = 12_498 },
    .{ .ticker = tickerBuf("AMD"), .ticker_len = 3, .venue = .nasdaq, .bid_cents = 15_990, .ask_cents = 16_000, .last_cents = 15_995 },
    .{ .ticker = tickerBuf("AVGO"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 24_990, .ask_cents = 25_000, .last_cents = 24_995 },
    .{ .ticker = tickerBuf("MSFT"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 49_990, .ask_cents = 50_000, .last_cents = 49_995 },
    .{ .ticker = tickerBuf("AMZN"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 19_990, .ask_cents = 20_000, .last_cents = 19_995 },
    .{ .ticker = tickerBuf("BOTZ"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 2_995, .ask_cents = 3_000, .last_cents = 2_998 },
    .{ .ticker = tickerBuf("SOXX"), .ticker_len = 4, .venue = .nasdaq, .bid_cents = 24_990, .ask_cents = 25_000, .last_cents = 24_995 },
};

// Comptime default for QuoteLoader.quotes — padded to max_basket_instruments.
const default_quotes: [basket.max_basket_instruments]trade_ticket.Quote = blk: { var arr = std.mem.zeroes([basket.max_basket_instruments]trade_ticket.Quote);
    for (fixture_quotes, 0..) |q, i| arr[i] = q;
    break :blk arr; };

pub const QuoteLoader = struct { // Inline storage allows initFromDir to populate without heap allocation.
    quotes: [basket.max_basket_instruments]trade_ticket.Quote = default_quotes,
    quote_count: u8 = fixture_quotes.len,
    as_of_ns: u64 = 1_765_792_800_000_000_000,

    pub fn load(self: QuoteLoader, ticker: []const u8) ?trade_ticket.Quote {
        for (self.quotes[0..self.quote_count]) |quote| {
            if (std.mem.eql(u8, quote.tickerSlice(), ticker)) return quote; }
        return null;
    }

    pub fn loadSnapshot(self: QuoteLoader, req: schema.AdapterRequest) schema.BackendError!trade_ticket.QuoteSnapshot { var snapshot: trade_ticket.QuoteSnapshot = std.mem.zeroes(trade_ticket.QuoteSnapshot);
        snapshot.as_of_ns = self.as_of_ns;
        snapshot.quote_count = req.ticker_count;
        for (req.tickers[0..req.ticker_count], 0..) |ticker_buf, i| {
            const ticker = std.mem.sliceTo(&ticker_buf, 0);
            snapshot.quotes[i] = self.load(ticker) orelse return error.UnsupportedTicker; }
        return snapshot;
    }
};

// ---------------------------------------------------------------------------
// Wire types for JSON fixture loading
// ---------------------------------------------------------------------------

const AccountOpsWire = struct { account: struct {
        numeric_account_id: u32,
        cash_cents: i64,
        buying_power_cents: i64,
        day_notional_used_cents: i64 = 0,
        day_notional_limit_cents: i64,
        month_notional_used_cents: i64 = 0,
        month_notional_limit_cents: i64,
        open_order_count: u8 = 0,
        max_open_order_count: u8, },
};

const QuoteWireEntry = struct { ticker: []const u8,
    venue: []const u8 = "NASDAQ",
    bid_cents: i64,
    ask_cents: i64,
    last_cents: i64, };

const QuotesFileWire = struct { as_of_ns: u64,
    quotes: []const QuoteWireEntry, };

const PaperFillWire = struct { ticker: []const u8,
    quantity: []const u8,
    fill_price_cents: i64,
    filled_notional_cents: i64, };

const PaperExecutionFileWire = struct { paper_order_id: []const u8,
    ticket_id: []const u8,
    status: []const u8,
    total_filled_cents: i64,
    fills: []const PaperFillWire,
    resulting_account_snapshot: struct {
        cash_cents: i64,
        buying_power_cents: i64,
        day_notional_used_cents: i64,
        month_notional_used_cents: i64, },
};

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

// Parses "2.000000" → 2_000_000 micros (6 decimal places).
fn parseQuantityMicros(s: []const u8) !u64 { const dot_pos = std.mem.indexOfScalar(u8, s, '.') orelse {
        const whole = try std.fmt.parseInt(u64, s, 10);
        return whole * 1_000_000; };
    const whole = try std.fmt.parseInt(u64, s[0..dot_pos], 10);
    const frac_str = s[dot_pos + 1 ..];
    var frac: u64 = 0;
    var multiplier: u64 = 100_000;
    for (frac_str) |c| { if (c < '0' or c > '9') return error.InvalidQuantity;
        frac += (c - '0') * multiplier;
        multiplier /= 10;
        if (multiplier == 0) break; }
    return whole * 1_000_000 + frac;
}

fn parseVenue(s: []const u8) !@FieldType(trade_ticket.Quote, "venue") { if (std.mem.eql(u8, s, "NASDAQ")) return .nasdaq;
    if (std.mem.eql(u8, s, "NYSE")) return .nyse;
    return error.UnknownVenue; }

fn readFixtureFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
) ![]u8 {
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ fixture_dir, filename });
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(32 * 1024));
}

fn loadAccountFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
) !portfolio.BrokerageAccount { const raw = try readFixtureFile(allocator, io, fixture_dir, "fixture_account_ops.json");
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(AccountOpsWire, allocator, raw, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const w = parsed.value.account;
    return portfolio.BrokerageAccount{ .account_id = w.numeric_account_id,
        .currency = .usd,
        .cash_cents = w.cash_cents,
        .buying_power_cents = w.buying_power_cents,
        .holdings = std.mem.zeroes([portfolio.max_holdings]portfolio.Holding),
        .holding_count = 0,
        .open_orders = std.mem.zeroes([portfolio.max_snapshot_open_orders]portfolio.OpenOrder),
        .open_order_count = w.open_order_count,
        .max_open_order_count = w.max_open_order_count,
        .day_notional_used_cents = w.day_notional_used_cents,
        .day_notional_limit_cents = w.day_notional_limit_cents,
        .month_notional_used_cents = w.month_notional_used_cents,
        .month_notional_limit_cents = w.month_notional_limit_cents, };
}

fn loadQuoteLoaderFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
) !QuoteLoader { const raw = try readFixtureFile(allocator, io, fixture_dir, "fixture_quotes.json");
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(QuotesFileWire, allocator, raw, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const wire = parsed.value;
    if (wire.quotes.len > basket.max_basket_instruments) return error.TooManyQuotes;
    var loader = QuoteLoader{ .as_of_ns = wire.as_of_ns,
        .quote_count = @intCast(wire.quotes.len),
        .quotes = std.mem.zeroes([basket.max_basket_instruments]trade_ticket.Quote), };
    for (wire.quotes, 0..) |wq, i| { if (wq.ticker.len > portfolio.max_ticker_len) return error.TickerTooLong;
        loader.quotes[i].ticker = std.mem.zeroes([portfolio.max_ticker_len]u8);
        @memcpy(loader.quotes[i].ticker[0..wq.ticker.len], wq.ticker);
        loader.quotes[i].ticker_len = @intCast(wq.ticker.len);
        loader.quotes[i].venue = try parseVenue(wq.venue);
        loader.quotes[i].bid_cents = wq.bid_cents;
        loader.quotes[i].ask_cents = wq.ask_cents;
        loader.quotes[i].last_cents = wq.last_cents; }
    return loader;
}

fn loadPaperExecutionFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
) !trade_ticket.PaperExecutionResult { const raw = try readFixtureFile(allocator, io, fixture_dir, "fixture_paper_execution_allowed_2000.json");
    defer allocator.free(raw);
    const parsed = try std.json.parseFromSlice(PaperExecutionFileWire, allocator, raw, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const w = parsed.value;
    if (w.fills.len > basket.max_basket_instruments) return error.TooManyFills;
    if (!std.mem.eql(u8, w.status, "filled")) return error.UnknownExecutionStatus;
    var result: trade_ticket.PaperExecutionResult = std.mem.zeroes(trade_ticket.PaperExecutionResult);
    if (w.paper_order_id.len > trade_ticket.max_paper_order_id_len) return error.PaperOrderIdTooLong;
    result.paper_order_id_len = @intCast(w.paper_order_id.len);
    @memcpy(result.paper_order_id[0..result.paper_order_id_len], w.paper_order_id);
    if (w.ticket_id.len > trade_ticket.max_ticket_id_len) return error.TicketIdTooLong;
    result.ticket_id_len = @intCast(w.ticket_id.len);
    @memcpy(result.ticket_id[0..result.ticket_id_len], w.ticket_id);
    result.status = .filled;
    result.total_filled_cents = w.total_filled_cents;
    result.fill_count = @intCast(w.fills.len);
    for (w.fills, 0..) |wf, i| { if (wf.ticker.len > portfolio.max_ticker_len) return error.TickerTooLong;
        result.fills[i].ticker = std.mem.zeroes([portfolio.max_ticker_len]u8);
        @memcpy(result.fills[i].ticker[0..wf.ticker.len], wf.ticker);
        result.fills[i].ticker_len = @intCast(wf.ticker.len);
        result.fills[i].quantity_micros = try parseQuantityMicros(wf.quantity);
        result.fills[i].fill_price_cents = wf.fill_price_cents;
        result.fills[i].filled_notional_cents = wf.filled_notional_cents; }
    result.resulting_account_snapshot = .{ .cash_cents = w.resulting_account_snapshot.cash_cents,
        .buying_power_cents = w.resulting_account_snapshot.buying_power_cents,
        .day_notional_used_cents = w.resulting_account_snapshot.day_notional_used_cents,
        .month_notional_used_cents = w.resulting_account_snapshot.month_notional_used_cents, };
    return result;
}

// ---------------------------------------------------------------------------
// FixtureBackend
// ---------------------------------------------------------------------------

pub const FixtureBackend = struct {
    account_snapshot: portfolio.BrokerageAccount = fixture_portfolio.fixtures.cash_rich,
    quote_loader: QuoteLoader = .{},
    // Non-null when loaded from fixture_paper_execution_allowed_2000.json via initFromDir.
    // Null falls back to the dynamic paper order result built from the ticket.
    paper_execution: ?trade_ticket.PaperExecutionResult = null,

    /// Load all three fixture files from fixture_dir and return a populated backend.
    /// No heap memory is retained after the call — all data is stored inline.
    pub fn initFromDir(
        allocator: std.mem.Allocator,
        io: std.Io,
        fixture_dir: []const u8,
    ) !FixtureBackend { return FixtureBackend{
            .account_snapshot = try loadAccountFromDir(allocator, io, fixture_dir),
            .quote_loader = try loadQuoteLoaderFromDir(allocator, io, fixture_dir),
            .paper_execution = try loadPaperExecutionFromDir(allocator, io, fixture_dir), };
    }

    pub fn call(self: FixtureBackend, req: schema.AdapterRequest) schema.BackendError!schema.AdapterResult { return switch (req.operation) {
            .portfolio_snapshot => blk: {
                if (req.account_id != self.account_snapshot.account_id) {
                    return error.UnknownAccount; }
                break :blk .{ .portfolio_snapshot = self.account_snapshot };
            },
            .quote_snapshot => .{ .quote_snapshot = try self.quote_loader.loadSnapshot(req) },
            .paper_order => blk: { const ticket = req.ticket orelse return error.MissingTicket;
                if (ticket.policy_outcome != .allow) return error.PolicyBlocked;
                if (self.paper_execution) |pe| {
                    var result = pe;
                    result.account_id = ticket.account_id;
                    break :blk .{ .paper_order = result };
                }
                var result: trade_ticket.PaperExecutionResult = std.mem.zeroes(trade_ticket.PaperExecutionResult);
                result.paper_order_id_len = @intCast("paper_order_ai_infra_2000_0001".len);
                @memcpy(result.paper_order_id[0..result.paper_order_id_len], "paper_order_ai_infra_2000_0001");
                result.ticket_id_len = ticket.ticket_id_len;
                @memcpy(result.ticket_id[0..ticket.ticket_id_len], ticket.ticket_id[0..ticket.ticket_id_len]);
                result.account_id = ticket.account_id;
                result.status = .filled;
                result.fill_count = ticket.line_item_count;
                var total_filled: i64 = 0;
                for (ticket.line_items[0..ticket.line_item_count], 0..) |item, i| { result.fills[i].ticker = item.ticker;
                    result.fills[i].ticker_len = item.ticker_len;
                    result.fills[i].quantity_micros = item.quantity_micros;
                    result.fills[i].fill_price_cents = item.price_cents;
                    result.fills[i].filled_notional_cents = item.line_notional_cents;
                    total_filled += item.line_notional_cents; }
                result.total_filled_cents = total_filled;
                result.resulting_account_snapshot = .{ .cash_cents = self.account_snapshot.cash_cents - total_filled,
                    .buying_power_cents = self.account_snapshot.buying_power_cents - total_filled,
                    .day_notional_used_cents = self.account_snapshot.day_notional_used_cents + total_filled,
                    .month_notional_used_cents = self.account_snapshot.month_notional_used_cents + total_filled, };
                break :blk .{ .paper_order = result };
            },
        };
    }

    pub fn asBackend(self: *FixtureBackend) Backend { return Backend.from(FixtureBackend, true, self); }
};

/// Type-erased adapter backend interface (Zig's standard vtable-interface
/// idiom, matching model.Backend in src/tickoni/tiles/model/backend.zig).
/// FixtureBackend exposes `asBackend()` built on `Backend.from()`. Test
/// doubles inject through the same entrypoint (see
/// src/tickoni/test/mocks/mock_adapter.zig's asBackend helper) so this
/// module never names a test-only type.
pub const Backend = struct { ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        call: *const fn (ptr: *anyopaque, req: schema.AdapterRequest) anyerror!schema.AdapterResult,
        /// True when no live network calls can occur. Replay must only run
        /// with effect-free backends.
        effect_free: bool, };

    /// Builds a Backend from any type T exposing
    /// `pub fn call(self: T, req) !AdapterResult`. self must outlive the
    /// returned Backend.
    pub fn from(comptime T: type, comptime effect_free: bool, self: *T) Backend { const Impl = struct {
            fn callImpl(ptr: *anyopaque, req: schema.AdapterRequest) anyerror!schema.AdapterResult {
                const s: *T = @ptrCast(@alignCast(ptr));
                return s.call(req); }
            const vtable = VTable{ .call = callImpl, .effect_free = effect_free };
        };
        return .{ .ptr = self, .vtable = &Impl.vtable };
    }

    pub fn call(self: Backend, req: schema.AdapterRequest) anyerror!schema.AdapterResult { return self.vtable.call(self.ptr, req); }

    /// Returns true when no live network calls can occur.
    pub fn isEffectFree(self: Backend) bool { return self.vtable.effect_free; }
};

test "QuoteLoader finds fixture quote by ticker" {
    const loader = QuoteLoader{};
    const quote = loader.load("NVDA") orelse return error.TestUnexpectedResult;

    try std.testing.expectEqualStrings("NVDA", quote.tickerSlice());
    try std.testing.expect(quote.venue == .nasdaq);
    try std.testing.expectEqual(@as(i64, 12_500), quote.ask_cents);
}

test "FixtureBackend builds quote snapshot from loader" { var req = schema.AdapterRequest{
        .operation = .quote_snapshot,
        .ticker_count = 2, };
    req.tickers[0] = tickerBuf("NVDA");
    req.tickers[1] = tickerBuf("AMD");

    const result = try (FixtureBackend{}).call(req);
    const snapshot = switch (result) { .quote_snapshot => |value| value,
        else => unreachable, };

    try std.testing.expectEqual(@as(u8, 2), snapshot.quote_count);
    try std.testing.expectEqualStrings("NVDA", snapshot.quotes[0].tickerSlice());
    try std.testing.expectEqualStrings("AMD", snapshot.quotes[1].tickerSlice());
}

test "Backend dispatches through the vtable to fixture backend" {
    var fixture_backend = FixtureBackend{};
    const backend = fixture_backend.asBackend();
    const result = try backend.call(.{ .operation = .portfolio_snapshot,
        .account_id = fixture_portfolio.fixtures.cash_rich.account_id, });

    const snapshot = switch (result) { .portfolio_snapshot => |value| value,
        else => unreachable, };
    try std.testing.expectEqual(fixture_portfolio.fixtures.cash_rich.account_id, snapshot.account_id);
}

test "FixtureBackend rejects unknown account" {
    try std.testing.expectError(error.UnknownAccount, (FixtureBackend{}).call(.{ .operation = .portfolio_snapshot,
        .account_id = 999_999, }));
}

test "FixtureBackend rejects unsupported ticker" { var req = schema.AdapterRequest{
        .operation = .quote_snapshot,
        .account_id = fixture_portfolio.fixtures.cash_rich.account_id,
        .ticker_count = 1, };
    req.tickers[0] = tickerBuf("NOPE");
    try std.testing.expectError(error.UnsupportedTicker, (FixtureBackend{}).call(req));
}

test "FixtureBackend rejects missing ticket for paper order" {
    try std.testing.expectError(error.MissingTicket, (FixtureBackend{}).call(.{ .operation = .paper_order,
        .account_id = fixture_portfolio.fixtures.cash_rich.account_id,
        .ticket = null, }));
}

test "FixtureBackend rejects policy blocked ticket for paper order" {
    var ticket: trade_ticket.TradeTicket = std.mem.zeroes(trade_ticket.TradeTicket);
    ticket.account_id = fixture_portfolio.fixtures.cash_rich.account_id;
    ticket.policy_outcome = .deny;

    try std.testing.expectError(error.PolicyBlocked, (FixtureBackend{}).call(.{ .operation = .paper_order,
        .account_id = ticket.account_id,
        .ticket = ticket, }));
}

test "parseQuantityMicros parses fractional quantities" { try std.testing.expectEqual(@as(u64, 2_000_000), try parseQuantityMicros("2.000000"));
    try std.testing.expectEqual(@as(u64, 1_562_500), try parseQuantityMicros("1.562500"));
    try std.testing.expectEqual(@as(u64, 12_500_000), try parseQuantityMicros("12.500000"));
    try std.testing.expectEqual(@as(u64, 1_000_000), try parseQuantityMicros("1.000000"));
    try std.testing.expectEqual(@as(u64, 500_000), try parseQuantityMicros("0.500000")); }

test "FixtureBackend.initFromDir loads fixture_account_ops.json" { const backend = try FixtureBackend.initFromDir(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios",
    );
    try std.testing.expectEqual(@as(u32, 2001), backend.account_snapshot.account_id);
    try std.testing.expectEqual(@as(i64, 5_000_000), backend.account_snapshot.cash_cents);
    try std.testing.expectEqual(@as(i64, 5_000_000), backend.account_snapshot.buying_power_cents);
    try std.testing.expectEqual(@as(i64, 2_500_000), backend.account_snapshot.day_notional_limit_cents); }

test "FixtureBackend.initFromDir loads fixture_quotes.json" { const backend = try FixtureBackend.initFromDir(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios",
    );
    try std.testing.expectEqual(@as(u8, 7), backend.quote_loader.quote_count);
    try std.testing.expectEqual(@as(u64, 1_765_792_800_000_000_000), backend.quote_loader.as_of_ns);
    const nvda = backend.quote_loader.load("NVDA") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i64, 12_500), nvda.ask_cents);
    try std.testing.expectEqual(@as(i64, 12_495), nvda.bid_cents); }

test "FixtureBackend.initFromDir loads fixture_paper_execution_allowed_2000.json" { const backend = try FixtureBackend.initFromDir(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios",
    );
    const pe = backend.paper_execution orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("paper_order_ai_infra_2000_0001", pe.paperOrderIdSlice());
    try std.testing.expectEqualStrings("ticket_ai_infra_2000_market", pe.ticketIdSlice());
    try std.testing.expectEqual(@as(i64, 200_000), pe.total_filled_cents);
    try std.testing.expectEqual(@as(u8, 7), pe.fill_count);
    try std.testing.expectEqual(@as(u64, 2_000_000), pe.fills[0].quantity_micros);
    try std.testing.expectEqual(@as(i64, 4_800_000), pe.resulting_account_snapshot.cash_cents); }

test "FixtureBackend.initFromDir data matches hardcoded defaults" {
    const from_file = try FixtureBackend.initFromDir(
        std.testing.allocator,
        std.testing.io,
        "src/tickoni/test/fixtures/investment/scenarios",
    );
    const from_default = FixtureBackend{};

    try std.testing.expectEqual(from_default.account_snapshot.account_id, from_file.account_snapshot.account_id);
    try std.testing.expectEqual(from_default.account_snapshot.cash_cents, from_file.account_snapshot.cash_cents);
    try std.testing.expectEqual(from_default.quote_loader.quote_count, from_file.quote_loader.quote_count);
    try std.testing.expectEqual(from_default.quote_loader.as_of_ns, from_file.quote_loader.as_of_ns);
    for (0..from_default.quote_loader.quote_count) |i| { const dq = from_default.quote_loader.quotes[i];
        const fq = from_file.quote_loader.quotes[i];
        try std.testing.expectEqualStrings(dq.tickerSlice(), fq.tickerSlice());
        try std.testing.expectEqual(dq.ask_cents, fq.ask_cents);
        try std.testing.expectEqual(dq.bid_cents, fq.bid_cents); }
}

test "Backend.isEffectFree stays true for offline adapter backends" {
    var fixture_backend = FixtureBackend{};
    const fixture = fixture_backend.asBackend();

    try std.testing.expect(fixture.isEffectFree());
}
