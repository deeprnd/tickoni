/// Instrument catalog fixture and lookup functions.
///
/// The versioned record contract (InstrumentEntry, RestrictionReason,
/// catalog_schema_version, CatalogValidationError) lives in
/// catalog_schema.zig and is re-exported below unchanged, so existing
/// `@import("catalog")` call sites keep working; this file owns only the
/// concrete fixture data and the functions that operate on it — see finding
/// 29 in doc/strategy/roadmap/backlog/audits/tech_debt.md.
///
/// catalog: compile-time array of all fixture instruments (24 entries).
/// Lookup functions: filterByTheme, filterBySector, filterByIndustry,
/// filterByAssetClass, filterByInstrumentType, filterByVenue, lookupByTicker.
///
/// Schema version: catalog_schema_version below. When basket construction
/// produces audit records, it stamps the catalog version that was consulted so
/// replay can detect classification drift.
const std = @import("std");
const thesis = @import("thesis");
const cls = @import("classification");
const schema = @import("catalog_schema");

pub const AssetClass = schema.AssetClass;
pub const InstrumentType = schema.InstrumentType;
pub const Market = schema.Market;
pub const Venue = schema.Venue;
pub const RiskPreference = schema.RiskPreference;
pub const CanonicalId = schema.CanonicalId;
pub const ClassificationRef = schema.ClassificationRef;
pub const ClassificationRefList = schema.ClassificationRefList;
pub const ThemeIdList = schema.ThemeIdList;

pub const catalog_schema_version = schema.catalog_schema_version;

pub const max_ticker_len = schema.max_ticker_len;
pub const max_name_len = schema.max_name_len;

pub const sector_taxonomy_version = cls.sector_taxonomy_version;
pub const industry_taxonomy_version = cls.industry_taxonomy_version;

pub const RestrictionReason = schema.RestrictionReason;
pub const InstrumentEntry = schema.InstrumentEntry;
pub const CatalogValidationError = schema.CatalogValidationError;

// Known theme/sector/industry taxonomy values live in classification.zig
// (the single source of truth shared with thesis.zig — see finding 30 in
// doc/strategy/roadmap/backlog/audits/tech_debt.md).
pub const sector_taxonomy_id = cls.sector_taxonomy_id;
pub const industry_taxonomy_id = cls.industry_taxonomy_id;
const known_theme_ids = cls.known_theme_ids;
const known_sector_codes = cls.known_sector_codes;
const known_industry_codes = cls.known_industry_codes;

fn tickerBuf(comptime s: []const u8) [max_ticker_len]u8 {
    if (s.len > max_ticker_len) @compileError("ticker exceeds max_ticker_len");
    var buf = std.mem.zeroes([max_ticker_len]u8);
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

fn nameBuf(comptime s: []const u8) [max_name_len]u8 {
    if (s.len > max_name_len) @compileError("name exceeds max_name_len");
    var buf = std.mem.zeroes([max_name_len]u8);
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

fn sectorRef(code: []const u8) ClassificationRef {
    return thesis.ClassificationRef.init("gics_sector", sector_taxonomy_version, code) catch unreachable;
}

fn industryRef(code: []const u8) ClassificationRef {
    return thesis.ClassificationRef.init("gics_industry", industry_taxonomy_version, code) catch unreachable;
}

fn sectors(codes: []const []const u8) ClassificationRefList {
    var refs = ClassificationRefList{};
    for (codes) |code| {
        refs.append(sectorRef(code)) catch unreachable;
    }
    return refs;
}

fn industries(codes: []const []const u8) ClassificationRefList {
    var refs = ClassificationRefList{};
    for (codes) |code| {
        refs.append(industryRef(code)) catch unreachable;
    }
    return refs;
}

fn themes(ids: []const []const u8) ThemeIdList {
    var list = ThemeIdList{};
    for (ids) |id| {
        list.append(thesis.CanonicalId.init(id) catch unreachable) catch unreachable;
    }
    return list;
}

fn mkEntry(
    comptime ticker_s: []const u8,
    comptime name_s: []const u8,
    asset_class: AssetClass,
    instrument_type: InstrumentType,
    market: Market,
    venue: Venue,
    entry_sectors: ClassificationRefList,
    entry_industries: ClassificationRefList,
    entry_themes: ThemeIdList,
    risk: RiskPreference,
    expense_ratio_bps: u16,
    restricted: bool,
    restriction_reason: RestrictionReason,
) InstrumentEntry {
    return .{
        .ticker = tickerBuf(ticker_s),
        .ticker_len = @intCast(ticker_s.len),
        .name = nameBuf(name_s),
        .name_len = @intCast(name_s.len),
        .asset_class = asset_class,
        .instrument_type = instrument_type,
        .market = market,
        .venue = venue,
        .sectors = entry_sectors,
        .industries = entry_industries,
        .themes = entry_themes,
        .risk_tier = risk,
        .expense_ratio_bps = expense_ratio_bps,
        .restricted = restricted,
        .restriction_reason = restriction_reason,
    };
}

pub const catalog = [_]InstrumentEntry{
    // --- Semiconductors / AI infrastructure stocks ---
    mkEntry("NVDA", "NVIDIA Corporation", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{ "ai_infrastructure", "semiconductors" }), .high, 0, false, .none),
    mkEntry("AMD", "Advanced Micro Devices Inc.", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{ "ai_infrastructure", "semiconductors" }), .high, 0, false, .none),
    mkEntry("AVGO", "Broadcom Inc.", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{ "ai_infrastructure", "semiconductors" }), .moderate, 0, false, .none),
    mkEntry("MSFT", "Microsoft Corporation", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"systems_software"}), themes(&[_][]const u8{ "ai_infrastructure", "cloud" }), .moderate, 0, false, .none),
    // --- AI infrastructure ETFs ---
    mkEntry("BOTZ", "Global X Robotics & AI ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{ "information_technology", "industrials" }), industries(&[_][]const u8{"robotics_and_ai"}), themes(&[_][]const u8{"ai_infrastructure"}), .moderate, 68, false, .none),
    mkEntry("SOXX", "iShares Semiconductor ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{ "ai_infrastructure", "semiconductors" }), .high, 35, false, .none),
    // --- Cloud ---
    mkEntry("AMZN", "Amazon.com Inc.", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{ "consumer_discretionary", "information_technology" }), industries(&[_][]const u8{ "internet_retail", "cloud_platforms" }), themes(&[_][]const u8{ "ai_infrastructure", "cloud" }), .moderate, 0, false, .none),
    mkEntry("WCLD", "WisdomTree Cloud Computing ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"cloud_software"}), themes(&[_][]const u8{"cloud"}), .moderate, 45, false, .none),
    // --- Cyber security ---
    mkEntry("PANW", "Palo Alto Networks Inc.", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"cybersecurity"}), themes(&[_][]const u8{"cyber_security"}), .high, 0, false, .none),
    mkEntry("CRWD", "CrowdStrike Holdings Inc.", .equity, .stock, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"cybersecurity"}), themes(&[_][]const u8{"cyber_security"}), .high, 0, false, .none),
    mkEntry("HACK", "ETFMG Prime Cyber Security ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"cybersecurity"}), themes(&[_][]const u8{"cyber_security"}), .moderate, 60, false, .none),
    mkEntry("CIBR", "First Trust NASDAQ Cybersecurity ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"cybersecurity"}), themes(&[_][]const u8{"cyber_security"}), .moderate, 60, false, .none),
    // --- Broad market ---
    mkEntry("SPY", "SPDR S&P 500 ETF Trust", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{ "information_technology", "financials", "health_care" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"broad_market"}), .low, 9, false, .none),
    mkEntry("IVV", "iShares Core S&P 500 ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{ "information_technology", "financials", "health_care" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"broad_market"}), .low, 3, false, .none),
    mkEntry("VOO", "Vanguard S&P 500 ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{ "information_technology", "financials", "health_care" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"broad_market"}), .low, 3, false, .none),
    mkEntry("VTI", "Vanguard Total Stock Market ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{ "information_technology", "financials", "health_care" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"broad_market"}), .low, 3, false, .none),
    // --- Dividends ---
    mkEntry("VYM", "Vanguard High Dividend Yield ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{ "financials", "health_care", "consumer_staples" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"dividends"}), .low, 6, false, .none),
    mkEntry("DVY", "iShares Select Dividend ETF", .equity, .etf, .us, .nasdaq, sectors(&[_][]const u8{ "financials", "utilities", "consumer_staples" }), industries(&[_][]const u8{}), themes(&[_][]const u8{"dividends"}), .low, 38, false, .none),
    // --- Cash-like ---
    mkEntry("SHV", "iShares Short Treasury Bond ETF", .cash, .etf, .us, .nasdaq, sectors(&[_][]const u8{}), industries(&[_][]const u8{"sovereign_debt"}), themes(&[_][]const u8{"cash_like"}), .low, 15, false, .none),
    mkEntry("SGOV", "iShares 0-3 Month Treasury Bond ETF", .cash, .etf, .us, .nyse, sectors(&[_][]const u8{}), industries(&[_][]const u8{"sovereign_debt"}), themes(&[_][]const u8{"cash_like"}), .low, 9, false, .none),
    mkEntry("BIL", "SPDR Bloomberg 1-3 Month T-Bill ETF", .cash, .etf, .us, .nyse, sectors(&[_][]const u8{}), industries(&[_][]const u8{"sovereign_debt"}), themes(&[_][]const u8{"cash_like"}), .low, 14, false, .none),
    // --- Restricted leveraged/inverse ETFs ---
    mkEntry("SOXL", "Direxion Daily Semiconductor Bull 3X ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{ "ai_infrastructure", "semiconductors" }), .high, 77, true, .leveraged_etf),
    mkEntry("SOXS", "Direxion Daily Semiconductor Bear 3X ETF", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"semiconductors"}), themes(&[_][]const u8{"semiconductors"}), .high, 92, true, .inverse_etf),
    mkEntry("BULZ", "MicroSectors FANG 3X Bull Leveraged ETN", .equity, .etf, .us, .nyse, sectors(&[_][]const u8{"information_technology"}), industries(&[_][]const u8{"robotics_and_ai"}), themes(&[_][]const u8{"ai_infrastructure"}), .high, 95, true, .leveraged_etf),
};

pub fn validateCatalog() CatalogValidationError!void {
    for (catalog, 0..) |entry, i| {
        try validateEntry(entry);
        for (catalog[0..i]) |prior| {
            if (std.mem.eql(u8, entry.tickerSlice(), prior.tickerSlice())) {
                return CatalogValidationError.DuplicateTicker;
            }
        }
    }
}

fn validateEntry(entry: InstrumentEntry) CatalogValidationError!void {
    if (entry.ticker_len == 0 or entry.ticker_len > max_ticker_len) return CatalogValidationError.InvalidTicker;
    if (entry.name_len == 0 or entry.name_len > max_name_len) return CatalogValidationError.InvalidName;
    entry.sectors.validate() catch return CatalogValidationError.InvalidClassification;
    entry.industries.validate() catch return CatalogValidationError.InvalidClassification;
    entry.themes.validate() catch return CatalogValidationError.InvalidClassification;
    for (entry.sectors.values[0..entry.sectors.count]) |sector| {
        if (!isKnownSectorRef(sector)) return CatalogValidationError.InvalidClassification;
    }
    for (entry.industries.values[0..entry.industries.count]) |industry| {
        if (!isKnownIndustryRef(industry)) return CatalogValidationError.InvalidClassification;
    }
    for (entry.themes.values[0..entry.themes.count]) |theme_id| {
        if (!isKnownThemeId(theme_id)) return CatalogValidationError.InvalidClassification;
    }
    if (entry.restricted and entry.restriction_reason == .none) return CatalogValidationError.InvalidClassification;
    if (!entry.restricted and entry.restriction_reason != .none) return CatalogValidationError.InvalidClassification;
}

fn isKnownThemeId(theme_id: CanonicalId) bool {
    return cls.hasCanonicalId(&known_theme_ids, theme_id);
}

fn isKnownSectorRef(ref: ClassificationRef) bool {
    if (!ref.taxonomy_id.eql(sector_taxonomy_id)) return false;
    if (ref.taxonomy_version != sector_taxonomy_version) return false;
    return cls.hasCanonicalId(&known_sector_codes, ref.code);
}

fn isKnownIndustryRef(ref: ClassificationRef) bool {
    if (!ref.taxonomy_id.eql(industry_taxonomy_id)) return false;
    if (ref.taxonomy_version != industry_taxonomy_version) return false;
    return cls.hasCanonicalId(&known_industry_codes, ref.code);
}

pub fn filterByTheme(theme: CanonicalId, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.themes.has(theme)) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn filterBySector(sector: ClassificationRef, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.sectors.has(sector)) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn filterByIndustry(industry: ClassificationRef, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.industries.has(industry)) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn filterByAssetClass(asset_class: AssetClass, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.asset_class == asset_class) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn filterByInstrumentType(instrument_type: InstrumentType, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.instrument_type == instrument_type) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn filterByVenue(venue: Venue, out: []*const InstrumentEntry) usize {
    var n: usize = 0;
    for (0..catalog.len) |i| {
        if (n >= out.len) break;
        const entry = &catalog[i];
        if (entry.venue == venue) {
            out[n] = entry;
            n += 1;
        }
    }
    return n;
}

pub fn lookupByTicker(ticker: []const u8) ?*const InstrumentEntry {
    for (0..catalog.len) |i| {
        const entry = &catalog[i];
        if (std.mem.eql(u8, entry.tickerSlice(), ticker)) return entry;
    }
    return null;
}

test "catalog validates classification bounds and uniqueness" {
    try validateCatalog();
}

test "catalog: total entry count is 24" {
    try std.testing.expectEqual(@as(usize, 24), catalog.len);
}

test "catalog: all entries have non-empty ticker and name" {
    for (catalog) |entry| {
        try std.testing.expect(entry.ticker_len > 0);
        try std.testing.expect(entry.name_len > 0);
        try std.testing.expect(entry.ticker_len <= max_ticker_len);
        try std.testing.expect(entry.name_len <= max_name_len);
    }
}

test "catalog: restricted entries have non-none restriction_reason" {
    for (catalog) |entry| {
        if (entry.restricted) {
            try std.testing.expect(entry.restriction_reason != .none);
        } else {
            try std.testing.expectEqual(RestrictionReason.none, entry.restriction_reason);
        }
    }
}

test "catalog: all stocks have expense_ratio_bps == 0" {
    for (catalog) |entry| {
        if (entry.instrument_type == .stock) {
            try std.testing.expectEqual(@as(u16, 0), entry.expense_ratio_bps);
        }
    }
}

test "catalog: all entries are US market" {
    for (catalog) |entry| {
        try std.testing.expectEqual(Market.us, entry.market);
    }
}

test "catalog: all entries are NYSE or NASDAQ" {
    for (catalog) |entry| {
        const ok = entry.venue == .nyse or entry.venue == .nasdaq;
        try std.testing.expect(ok);
    }
}

test "filterByTheme: ai_infrastructure scenario yields >= 4 eligible and >= 2 restricted" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByTheme(thesis.CanonicalId.init("ai_infrastructure") catch unreachable, &out);
    var eligible: usize = 0;
    var restricted: usize = 0;
    for (out[0..n]) |entry| {
        if (entry.restricted) restricted += 1 else eligible += 1;
    }
    try std.testing.expect(eligible >= 4);
    try std.testing.expect(restricted >= 2);
}

test "filterByTheme: every returned entry has the requested theme id" {
    const theme_ids = [_]CanonicalId{
        thesis.CanonicalId.init("ai_infrastructure") catch unreachable,
        thesis.CanonicalId.init("semiconductors") catch unreachable,
        thesis.CanonicalId.init("cloud") catch unreachable,
        thesis.CanonicalId.init("cyber_security") catch unreachable,
        thesis.CanonicalId.init("broad_market") catch unreachable,
        thesis.CanonicalId.init("dividends") catch unreachable,
        thesis.CanonicalId.init("cash_like") catch unreachable,
    };
    var out: [catalog.len]*const InstrumentEntry = undefined;
    for (theme_ids) |theme_id| {
        const n = filterByTheme(theme_id, &out);
        for (out[0..n]) |entry| {
            try std.testing.expect(entry.themes.has(theme_id));
        }
    }
}

test "filterBySector: information technology returns tagged entries" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterBySector(sectorRef("information_technology"), &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |entry| {
        try std.testing.expect(entry.sectors.has(sectorRef("information_technology")));
    }
}

test "filterByIndustry: semiconductors returns tagged entries" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByIndustry(industryRef("semiconductors"), &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |entry| {
        try std.testing.expect(entry.industries.has(industryRef("semiconductors")));
    }
}

test "catalog: sector and industry refs preserve canonical taxonomy metadata" {
    const amzn = lookupByTicker("AMZN").?;
    try std.testing.expect(amzn.sectors.has(sectorRef("consumer_discretionary")));
    try std.testing.expect(amzn.sectors.has(sectorRef("information_technology")));
    for (amzn.sectors.values[0..amzn.sectors.count]) |sector| {
        try std.testing.expectEqualStrings("gics_sector", sector.taxonomy_id.slice());
        try std.testing.expectEqual(sector_taxonomy_version, sector.taxonomy_version);
    }

    const botz = lookupByTicker("BOTZ").?;
    try std.testing.expect(botz.industries.has(industryRef("robotics_and_ai")));
    for (botz.industries.values[0..botz.industries.count]) |industry| {
        try std.testing.expectEqualStrings("gics_industry", industry.taxonomy_id.slice());
        try std.testing.expectEqual(industry_taxonomy_version, industry.taxonomy_version);
    }
}

test "filterByAssetClass: cash returns only cash exposures" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByAssetClass(.cash, &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |entry| {
        try std.testing.expectEqual(AssetClass.cash, entry.asset_class);
    }
}

test "filterByInstrumentType: etf returns only ETFs" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByInstrumentType(.etf, &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |entry| {
        try std.testing.expectEqual(InstrumentType.etf, entry.instrument_type);
    }
}

test "filterByInstrumentType: stock returns only stocks" {
    var out: [catalog.len]*const InstrumentEntry = undefined;
    const n = filterByInstrumentType(.stock, &out);
    try std.testing.expect(n > 0);
    for (out[0..n]) |entry| {
        try std.testing.expectEqual(InstrumentType.stock, entry.instrument_type);
    }
}

test "filterByVenue: every returned entry is on the requested venue" {
    var nasdaq_out: [catalog.len]*const InstrumentEntry = undefined;
    const nasdaq_n = filterByVenue(.nasdaq, &nasdaq_out);
    try std.testing.expect(nasdaq_n > 0);
    for (nasdaq_out[0..nasdaq_n]) |entry| {
        try std.testing.expectEqual(Venue.nasdaq, entry.venue);
    }

    var nyse_out: [catalog.len]*const InstrumentEntry = undefined;
    const nyse_n = filterByVenue(.nyse, &nyse_out);
    try std.testing.expect(nyse_n > 0);
    for (nyse_out[0..nyse_n]) |entry| {
        try std.testing.expectEqual(Venue.nyse, entry.venue);
    }
}

test "lookupByTicker: NVDA returns correct entry" {
    const entry = lookupByTicker("NVDA");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("NVDA", entry.?.tickerSlice());
    try std.testing.expectEqual(AssetClass.equity, entry.?.asset_class);
    try std.testing.expectEqual(InstrumentType.stock, entry.?.instrument_type);
    try std.testing.expectEqual(Market.us, entry.?.market);
    try std.testing.expectEqual(Venue.nasdaq, entry.?.venue);
    try std.testing.expect(entry.?.themes.has(thesis.CanonicalId.init("ai_infrastructure") catch unreachable));
    try std.testing.expect(entry.?.themes.has(thesis.CanonicalId.init("semiconductors") catch unreachable));
    try std.testing.expect(entry.?.industries.has(industryRef("semiconductors")));
    try std.testing.expect(!entry.?.restricted);
    try std.testing.expectEqual(@as(u16, 0), entry.?.expense_ratio_bps);
}

test "lookupByTicker: SOXL is restricted with leveraged_etf reason" {
    const entry = lookupByTicker("SOXL");
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.restricted);
    try std.testing.expectEqual(RestrictionReason.leveraged_etf, entry.?.restriction_reason);
    try std.testing.expectEqual(AssetClass.equity, entry.?.asset_class);
    try std.testing.expectEqual(InstrumentType.etf, entry.?.instrument_type);
}

test "lookupByTicker: SOXS is restricted with inverse_etf reason" {
    const entry = lookupByTicker("SOXS");
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.restricted);
    try std.testing.expectEqual(RestrictionReason.inverse_etf, entry.?.restriction_reason);
}

test "lookupByTicker: BULZ is restricted with leveraged_etf reason" {
    const entry = lookupByTicker("BULZ");
    try std.testing.expect(entry != null);
    try std.testing.expect(entry.?.restricted);
    try std.testing.expectEqual(RestrictionReason.leveraged_etf, entry.?.restriction_reason);
}

test "lookupByTicker: unknown ticker returns null" {
    try std.testing.expectEqual(@as(?*const InstrumentEntry, null), lookupByTicker("ZZZZ"));
    try std.testing.expectEqual(@as(?*const InstrumentEntry, null), lookupByTicker(""));
}

test "lookupByTicker: all catalog tickers are individually resolvable" {
    for (&catalog) |*entry| {
        const found = lookupByTicker(entry.tickerSlice());
        try std.testing.expect(found != null);
        try std.testing.expectEqualStrings(entry.tickerSlice(), found.?.tickerSlice());
    }
}

test "catalog: ticker slices match expected values for known entries" {
    const nvda = lookupByTicker("NVDA").?;
    try std.testing.expectEqualStrings("NVIDIA Corporation", nvda.nameSlice());

    const spy = lookupByTicker("SPY").?;
    try std.testing.expectEqualStrings("SPDR S&P 500 ETF Trust", spy.nameSlice());
    try std.testing.expectEqual(InstrumentType.etf, spy.instrument_type);
    try std.testing.expectEqual(@as(u16, 9), spy.expense_ratio_bps);

    const sgov = lookupByTicker("SGOV").?;
    try std.testing.expectEqual(AssetClass.cash, sgov.asset_class);
    try std.testing.expect(sgov.themes.has(thesis.CanonicalId.init("cash_like") catch unreachable));
    try std.testing.expect(!sgov.restricted);
}
