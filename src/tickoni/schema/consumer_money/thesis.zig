/// Thesis input schema and investor intent normalization
///
/// ThesisInput: raw investor request captured from the user or a test fixture.
/// InvestorIntent: validated, structured form produced by normalize().
/// fixtures: deterministic test inputs for the five canonical themes.
///
/// All validation in normalize() is fail-closed: missing or out-of-range
/// fields return an explicit ThesisError instead of silently substituting
/// defaults.
///
/// Filter ordering: normalize() sorts themes, sector_filters, and
/// industry_filters into lexicographic canonical order before returning
/// InvestorIntent so downstream consumers and content hashes see a stable
/// order regardless of source ordering.
///
/// Canonical encoding: binary protobuf. Wire format is defined in
/// src/tickoni/schema/proto/consumer_money/thesis.proto; breaking changes are enforced by buf
/// in CI (quality-check-proto / proto_check.yml).
const std = @import("std");
const c_abi = @import("c_abi");
const cls = @import("classification");
const thesis_proto_path = "src/tickoni/schema/proto/consumer_money/thesis.proto";

pub const classification = cls;
pub const Market = cls.Market;
pub const Venue = cls.Venue;
pub const AssetClass = cls.AssetClass;
pub const AssetClassList = cls.AssetClassList;
pub const InstrumentType = cls.InstrumentType;
pub const InstrumentTypeList = cls.InstrumentTypeList;
pub const RiskPreference = cls.RiskPreference;
pub const CanonicalId = cls.CanonicalId;
pub const ClassificationRef = cls.ClassificationRef;
pub const ClassificationRefList = cls.ClassificationRefList;
pub const ThemeIdList = cls.ThemeIdList;
pub const canonicalId = cls.canonicalId;
pub const classificationRef = cls.classificationRef;
pub const assetClassList = cls.assetClassList;
pub const instrumentTypeList = cls.instrumentTypeList;
pub const themeIdList = cls.themeIdList;
pub const classificationRefList = cls.classificationRefList;
pub const validateCanonicalId = cls.validateCanonicalId;

/// Schema version. Incrementing this value changes the hash key and invalidates
/// existing hashes.
pub const thesis_schema_version: u16 = 3;

/// Maximum bytes stored in the user_text field.
pub const max_user_text_len: usize = 512;

/// Byte width of each ticker slot in requested_tickers.
/// Must match max_ticker_len in catalog.zig.
pub const max_ticker_len: usize = 8;

/// Maximum number of explicitly requested tickers in one ThesisInput.
pub const max_requested_tickers: usize = 8;

/// Minimum allowed target notional: USD 1.00 = 100 cents.
pub const min_target_notional_cents: i64 = 100;
/// Maximum allowed target notional: USD 10 billion = 1_000_000_000_000 cents.
/// Prevents i64 overflow in downstream multiplication: notional * 10_000 (bp_denom) must fit i64.
pub const max_target_notional_cents: i64 = 1_000_000_000_000;

/// Packed byte stride for one ClassificationRef in the hash flat buffers.
/// Layout: taxonomy_id (max_canonical_id_len bytes) + taxonomy_version (2 bytes LE) + code (max_canonical_id_len bytes).
pub const classification_ref_stride: usize = cls.max_canonical_id_len + 2 + cls.max_canonical_id_len;

comptime {
    std.debug.assert(classification_ref_stride == 66);
}

// Known theme/sector/industry taxonomy values live in classification.zig
// (the single source of truth shared with catalog.zig — see finding 30 in
// doc/strategy/roadmap/backlog/audits/tech_debt.md); re-exported here under
// the names normalize()'s local helpers already use.
const sector_taxonomy_id = cls.sector_taxonomy_id;
const industry_taxonomy_id = cls.industry_taxonomy_id;
const sector_taxonomy_version = cls.sector_taxonomy_version;
const industry_taxonomy_version = cls.industry_taxonomy_version;
const known_theme_ids = cls.known_theme_ids;
const known_sector_codes = cls.known_sector_codes;
const known_industry_codes = cls.known_industry_codes;

// Intentional exception to finding 30's taxonomy consolidation
// (doc/strategy/roadmap/backlog/audits/tech_debt.md): this duplicates
// catalog.zig's instrument tickers, but catalog.zig already imports thesis.zig
// for its shared types, so thesis.zig importing catalog.zig back would cycle.
// Removing this duplicate needs finding 29's catalog-provider injection point
// (thesis validation would call the provider instead of a hardcoded list).
const known_tickers = [_][]const u8{
    "NVDA", "AMD",  "AVGO", "MSFT", "BOTZ", "SOXX",
    "AMZN", "WCLD", "PANW", "CRWD", "HACK", "CIBR",
    "SPY",  "IVV",  "VOO",  "VTI",  "VYM",  "DVY",
    "SHV",  "SGOV", "BIL",  "SOXL", "SOXS", "BULZ",
};

/// Raw investor thesis as received from the user or provided by a test fixture.
///
/// user_text is the plain-English investment intent; user_text_len is its byte
/// count. Call normalize() to validate and convert to InvestorIntent.
/// Call computeThesisInputHash() to obtain a stable content hash for dedup
/// and audit reference.
pub const ThesisInput = struct {
    user_text: [max_user_text_len]u8,
    user_text_len: u16,
    target_notional_cents: i64,
    account_id: u32,
    market_scope: Market,
    /// Economic exposures the user wants to include.
    asset_class_prefs: AssetClassList,
    /// Traded product types the user wants to include.
    instrument_type_prefs: InstrumentTypeList,
    /// Investment theme identifiers the user wants to target (at least one required).
    /// normalize() fails with EmptyThemeFilter if count == 0.
    themes: ThemeIdList,
    /// Sector classification filters (empty = no sector constraint).
    /// Each ClassificationRef must have a non-zero taxonomy_version and valid canonical ids.
    sector_filters: ClassificationRefList,
    /// Industry classification filters (empty = no industry constraint).
    industry_filters: ClassificationRefList,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of total basket notional (1-100).
    max_single_name_pct: u8,
    /// Explicit user exclusions; always merged with denied_* policy lists in normalize().
    asset_class_exclusions: AssetClassList,
    instrument_type_exclusions: InstrumentTypeList,
    /// Tickers the user explicitly named in their request (e.g. "Buy SOXL").
    /// Each slot is zero-padded to max_ticker_len bytes.
    /// normalize() passes these through to InvestorIntent unchanged; basket screening
    /// checks them against the catalog restricted list before theme-based scope checks.
    requested_tickers: [max_requested_tickers][max_ticker_len]u8 = std.mem.zeroes([max_requested_tickers][max_ticker_len]u8),
    requested_ticker_count: u8 = 0,

    pub fn text(self: *const ThesisInput) []const u8 {
        return self.user_text[0..self.user_text_len];
    }
};

/// Structured investor intent produced by normalize().
///
/// allowed_* lists are the user's preferences minus always-denied values and
/// explicit exclusions. excluded_* lists are the union of always-denied values
/// and the user's explicit exclusions, so downstream catalog and basket code
/// can trust them.
///
/// themes, sectors, and industries are sorted into lexicographic canonical order
/// so downstream consumers and content hashes are ordering-invariant.
pub const InvestorIntent = struct {
    account_id: u32,
    /// Sorted canonical theme filter. At least one entry required.
    themes: ThemeIdList,
    /// Sorted sector filter (empty = no sector constraint).
    sectors: ClassificationRefList,
    /// Sorted industry filter (empty = no industry constraint).
    industries: ClassificationRefList,
    target_amount_cents: i64,
    allowed_asset_classes: AssetClassList,
    excluded_asset_classes: AssetClassList,
    allowed_instrument_types: InstrumentTypeList,
    excluded_instrument_types: InstrumentTypeList,
    market: Market,
    venues: [2]Venue,
    venue_count: u8,
    risk_preference: RiskPreference,
    /// Maximum single-name allocation as a percentage of the basket notional.
    max_single_name_pct: u8,
    /// Explicitly requested tickers forwarded from ThesisInput unchanged.
    requested_tickers: [max_requested_tickers][max_ticker_len]u8,
    requested_ticker_count: u8,
};

/// Asset classes always denied in V1.1 regardless of user preference.
/// Commodity, FX, and crypto are outside the initial mandate.
pub const denied_asset_classes = cls.assetClassList(.{
    .commodity,
    .fx,
    .crypto,
});

/// Instrument types always denied in V1.1 regardless of user preference.
/// Bonds, options, futures, funds, and tokens are represented in the shared
/// contract but remain outside the initial thesis mandate.
pub const denied_instrument_types = cls.instrumentTypeList(.{
    .bond,
    .option,
    .future,
    .fund,
    .token,
});

pub const ThesisError = error{
    EmptyUserText,
    UserTextTooLong,
    MissingTargetAmount,
    TargetAmountTooSmall,
    TargetAmountTooLarge,
    EmptyThemeFilter,
    NoEligibleAssetClass,
    NoEligibleInstrumentType,
    MalformedClassification,
};

/// Stable error codes for ThesisDenialPayload, matching ThesisError variants.
pub const ThesisErrorCode = enum(u8) {
    empty_user_text = 0,
    user_text_too_long = 1,
    missing_target_amount = 2,
    target_amount_too_small = 3,
    target_amount_too_large = 4,
    empty_theme_filter = 5,
    no_eligible_asset_class = 6,
    no_eligible_instrument_type = 7,
    malformed_classification = 8,
};

/// Audit record payload for a successful thesis input normalization.
/// Emitted by the thesis normalization tile when normalize() succeeds.
/// thesis_input_hash is the computeThesisInputHash() result for this input.
pub const ThesisNormalizationPayload = struct {
    thesis_input_hash: u64,
    account_id: u32,
    theme_count: u8,
    target_amount_cents: i64,
};

/// Audit record payload for a thesis input denial.
/// Emitted by the thesis normalization tile when normalize() fails.
/// thesis_input_hash is 0 when user_text_len is unsafe to hash (UserTextTooLong).
pub const ThesisDenialPayload = struct {
    thesis_input_hash: u64,
    account_id: u32,
    error_code: ThesisErrorCode,
};

/// Validate a ThesisInput and return a structured InvestorIntent.
pub fn normalize(input: ThesisInput) ThesisError!InvestorIntent {
    if (input.user_text_len == 0) return ThesisError.EmptyUserText;
    if (@as(usize, input.user_text_len) > max_user_text_len) return ThesisError.UserTextTooLong;
    if (input.target_notional_cents <= 0) return ThesisError.MissingTargetAmount;
    if (input.target_notional_cents < min_target_notional_cents) return ThesisError.TargetAmountTooSmall;
    if (input.target_notional_cents > max_target_notional_cents) return ThesisError.TargetAmountTooLarge;

    if (input.themes.count == 0) return ThesisError.EmptyThemeFilter;

    validateInputClassifications(input) catch return ThesisError.MalformedClassification;

    const allowed_asset_classes = buildAllowedAssetClasses(input) catch return ThesisError.MalformedClassification;
    if (allowed_asset_classes.count == 0) return ThesisError.NoEligibleAssetClass;

    const allowed_instrument_types = buildAllowedInstrumentTypes(input) catch return ThesisError.MalformedClassification;
    if (allowed_instrument_types.count == 0) return ThesisError.NoEligibleInstrumentType;

    const excluded_asset_classes = buildExcludedAssetClasses(input) catch return ThesisError.MalformedClassification;
    const excluded_instrument_types = buildExcludedInstrumentTypes(input) catch return ThesisError.MalformedClassification;

    return InvestorIntent{
        .account_id = input.account_id,
        .themes = sortedThemes(input.themes),
        .sectors = sortedClassificationRefs(input.sector_filters),
        .industries = sortedClassificationRefs(input.industry_filters),
        .target_amount_cents = input.target_notional_cents,
        .allowed_asset_classes = allowed_asset_classes,
        .excluded_asset_classes = excluded_asset_classes,
        .allowed_instrument_types = allowed_instrument_types,
        .excluded_instrument_types = excluded_instrument_types,
        .market = input.market_scope,
        .venues = .{ .nyse, .nasdaq },
        .venue_count = 2,
        .risk_preference = input.risk_preference,
        .max_single_name_pct = input.max_single_name_pct,
        .requested_tickers = input.requested_tickers,
        .requested_ticker_count = input.requested_ticker_count,
    };
}

/// Compute a stable content hash over a ThesisInput via fd_siphash13.
///
/// Returns 0 when user_text_len > max_user_text_len to fail closed without
/// reading out of bounds. Callers building ThesisDenialPayload should record
/// 0 in that case and set error_code to user_text_too_long.
///
/// Themes and sector/industry filters are sorted into canonical order before
/// hashing so equivalent inputs produce identical hashes regardless of source
/// ordering.
pub fn computeThesisInputHash(input: ThesisInput) u64 {
    if (@as(usize, input.user_text_len) > max_user_text_len) return 0;
    const tickers_flat: [*]const u8 = @ptrCast(&input.requested_tickers);
    const asset_class_prefs: [*]const u8 = @ptrCast(&input.asset_class_prefs.values);
    const instrument_type_prefs: [*]const u8 = @ptrCast(&input.instrument_type_prefs.values);
    const asset_class_exclusions: [*]const u8 = @ptrCast(&input.asset_class_exclusions.values);
    const instrument_type_exclusions: [*]const u8 = @ptrCast(&input.instrument_type_exclusions.values);

    // Sort themes and pack to flat buffer (each zero-padded to max_canonical_id_len).
    const sorted_themes = sortedThemes(input.themes);
    const themes_flat = packThemes(sorted_themes);

    // Sort sector/industry filters and pack to ClassificationRef flat buffers.
    const sorted_sectors = sortedClassificationRefs(input.sector_filters);
    const sector_flat = packClassificationRefs(sorted_sectors);
    const sorted_industries = sortedClassificationRefs(input.industry_filters);
    const industry_flat = packClassificationRefs(sorted_industries);

    var sip: c_abi.ballet.Siphash13 = .{};
    c_abi.ballet.siphashInit(&sip, 0x0000535348544B54, thesis_schema_version); // "TKTHSS\0\0" LE

    const ver: u16 = thesis_schema_version;
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&ver));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.account_id));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.target_notional_cents));
    const market_scope: u8 = @backingInt(input.market_scope);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&market_scope));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.asset_class_prefs.count));
    for (0..input.asset_class_prefs.count) |i| c_abi.ballet.siphashAppend(&sip, asset_class_prefs[i .. i + 1]);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.instrument_type_prefs.count));
    for (0..input.instrument_type_prefs.count) |i| c_abi.ballet.siphashAppend(&sip, instrument_type_prefs[i .. i + 1]);

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&sorted_themes.count));
    for (0..sorted_themes.count) |i| {
        const off = i * cls.max_canonical_id_len;
        c_abi.ballet.siphashAppend(&sip, themes_flat[off .. off + cls.max_canonical_id_len]);
    }
    const risk_preference: u8 = @backingInt(input.risk_preference);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&risk_preference));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.max_single_name_pct));
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.asset_class_exclusions.count));
    for (0..input.asset_class_exclusions.count) |i| c_abi.ballet.siphashAppend(&sip, asset_class_exclusions[i .. i + 1]);
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.instrument_type_exclusions.count));
    for (0..input.instrument_type_exclusions.count) |i| c_abi.ballet.siphashAppend(&sip, instrument_type_exclusions[i .. i + 1]);

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&sorted_sectors.count));
    for (0..sorted_sectors.count) |i| {
        const off = i * classification_ref_stride;
        c_abi.ballet.siphashAppend(&sip, sector_flat[off .. off + classification_ref_stride]);
    }
    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&sorted_industries.count));
    for (0..sorted_industries.count) |i| {
        const off = i * classification_ref_stride;
        c_abi.ballet.siphashAppend(&sip, industry_flat[off .. off + classification_ref_stride]);
    }

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.requested_ticker_count));
    for (0..input.requested_ticker_count) |i| {
        const off = i * max_ticker_len;
        c_abi.ballet.siphashAppend(&sip, tickers_flat[off .. off + max_ticker_len]);
    }

    c_abi.ballet.siphashAppend(&sip, std.mem.asBytes(&input.user_text_len));
    c_abi.ballet.siphashAppend(&sip, input.user_text[0..input.user_text_len]);

    return c_abi.ballet.siphashFini(&sip);
}

// ---------------------------------------------------------------------------
// Sort helpers
// ---------------------------------------------------------------------------

/// Return a copy of a ThemeIdList sorted lexicographically by canonical id bytes.
fn sortedThemes(list: ThemeIdList) ThemeIdList {
    var out = list;
    var i: u8 = 1;
    while (i < out.count) : (i += 1) {
        const key = out.values[i];
        var j: u8 = i;
        while (j > 0 and canonicalIdGt(out.values[j - 1], key)) : (j -= 1) {
            out.values[j] = out.values[j - 1];
        }
        out.values[j] = key;
    }
    return out;
}

/// Return a copy of a ClassificationRefList sorted by (taxonomy_id, taxonomy_version, code).
fn sortedClassificationRefs(list: ClassificationRefList) ClassificationRefList {
    var out = list;
    var i: u8 = 1;
    while (i < out.count) : (i += 1) {
        const key = out.values[i];
        var j: u8 = i;
        while (j > 0 and classificationRefGt(out.values[j - 1], key)) : (j -= 1) {
            out.values[j] = out.values[j - 1];
        }
        out.values[j] = key;
    }
    return out;
}

fn canonicalIdGt(a: CanonicalId, b: CanonicalId) bool {
    return std.mem.order(u8, a.slice(), b.slice()) == .gt;
}

fn classificationRefGt(a: ClassificationRef, b: ClassificationRef) bool {
    const tid = std.mem.order(u8, a.taxonomy_id.slice(), b.taxonomy_id.slice());
    if (tid != .eq) return tid == .gt;
    if (a.taxonomy_version != b.taxonomy_version) return a.taxonomy_version > b.taxonomy_version;
    return std.mem.order(u8, a.code.slice(), b.code.slice()) == .gt;
}

// ---------------------------------------------------------------------------
// Flat-buffer packers for the C hash function
// ---------------------------------------------------------------------------

fn packThemes(list: ThemeIdList) [cls.max_theme_ids * cls.max_canonical_id_len]u8 {
    var buf = std.mem.zeroes([cls.max_theme_ids * cls.max_canonical_id_len]u8);
    for (list.values[0..list.count], 0..) |theme_id, i| {
        @memcpy(buf[i * cls.max_canonical_id_len ..][0..theme_id.len], theme_id.bytes[0..theme_id.len]);
    }
    return buf;
}

fn packClassificationRefs(list: ClassificationRefList) [cls.max_classification_refs * classification_ref_stride]u8 {
    var buf = std.mem.zeroes([cls.max_classification_refs * classification_ref_stride]u8);
    for (list.values[0..list.count], 0..) |ref, i| {
        const base = i * classification_ref_stride;
        @memcpy(buf[base..][0..ref.taxonomy_id.len], ref.taxonomy_id.bytes[0..ref.taxonomy_id.len]);
        const ver: u16 = ref.taxonomy_version;
        buf[base + cls.max_canonical_id_len] = @truncate(ver);
        buf[base + cls.max_canonical_id_len + 1] = @truncate(ver >> 8);
        @memcpy(buf[base + cls.max_canonical_id_len + 2 ..][0..ref.code.len], ref.code.bytes[0..ref.code.len]);
    }
    return buf;
}

// ---------------------------------------------------------------------------
// Private normalization helpers
// ---------------------------------------------------------------------------

fn validateInputClassifications(input: ThesisInput) !void {
    try input.asset_class_prefs.validate();
    try input.instrument_type_prefs.validate();
    try input.asset_class_exclusions.validate();
    try input.instrument_type_exclusions.validate();
    try input.themes.validate();
    try input.sector_filters.validate();
    try input.industry_filters.validate();
    try validateKnownThemes(input.themes);
    try validateKnownSectorFilters(input.sector_filters);
    try validateKnownIndustryFilters(input.industry_filters);
    try validateRequestedTickers(input);
}

fn validateKnownThemes(themes: ThemeIdList) !void {
    for (themes.values[0..themes.count]) |theme_id| {
        if (!isKnownThemeId(theme_id)) return error.UnknownThemeId;
    }
}

fn validateKnownSectorFilters(sectors: ClassificationRefList) !void {
    for (sectors.values[0..sectors.count]) |sector| {
        if (!isKnownSectorRef(sector)) return error.UnknownSectorFilter;
    }
}

fn validateKnownIndustryFilters(industries: ClassificationRefList) !void {
    for (industries.values[0..industries.count]) |industry| {
        if (!isKnownIndustryRef(industry)) return error.UnknownIndustryFilter;
    }
}

fn validateRequestedTickers(input: ThesisInput) !void {
    if (input.requested_ticker_count > max_requested_tickers) return error.TooManyRequestedTickers;

    var i: usize = 0;
    while (i < input.requested_ticker_count) : (i += 1) {
        const ticker = std.mem.sliceTo(&input.requested_tickers[i], 0);
        if (ticker.len == 0) return error.EmptyRequestedTicker;
        if (!isKnownTicker(ticker)) return error.UnknownRequestedTicker;

        var j: usize = 0;
        while (j < i) : (j += 1) {
            const prior = std.mem.sliceTo(&input.requested_tickers[j], 0);
            if (std.mem.eql(u8, ticker, prior)) return error.DuplicateRequestedTicker;
        }
    }
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

fn isKnownTicker(ticker: []const u8) bool {
    for (known_tickers) |known| {
        if (std.mem.eql(u8, known, ticker)) return true;
    }
    return false;
}

fn buildAllowedAssetClasses(input: ThesisInput) !AssetClassList {
    var allowed = AssetClassList{};
    for (input.asset_class_prefs.values[0..input.asset_class_prefs.count]) |asset_class| {
        if (denied_asset_classes.has(asset_class)) continue;
        if (input.asset_class_exclusions.has(asset_class)) continue;
        try allowed.append(asset_class);
    }
    return allowed;
}

fn buildExcludedAssetClasses(input: ThesisInput) !AssetClassList {
    var excluded = AssetClassList{};
    for (denied_asset_classes.values[0..denied_asset_classes.count]) |asset_class| {
        try excluded.append(asset_class);
    }
    for (input.asset_class_exclusions.values[0..input.asset_class_exclusions.count]) |asset_class| {
        if (!excluded.has(asset_class)) try excluded.append(asset_class);
    }
    return excluded;
}

fn buildAllowedInstrumentTypes(input: ThesisInput) !InstrumentTypeList {
    var allowed = InstrumentTypeList{};
    for (input.instrument_type_prefs.values[0..input.instrument_type_prefs.count]) |instrument_type| {
        if (denied_instrument_types.has(instrument_type)) continue;
        if (input.instrument_type_exclusions.has(instrument_type)) continue;
        try allowed.append(instrument_type);
    }
    return allowed;
}

fn buildExcludedInstrumentTypes(input: ThesisInput) !InstrumentTypeList {
    var excluded = InstrumentTypeList{};
    for (denied_instrument_types.values[0..denied_instrument_types.count]) |instrument_type| {
        try excluded.append(instrument_type);
    }
    for (input.instrument_type_exclusions.values[0..input.instrument_type_exclusions.count]) |instrument_type| {
        if (!excluded.has(instrument_type)) try excluded.append(instrument_type);
    }
    return excluded;
}

fn textBuf(comptime s: []const u8) [max_user_text_len]u8 {
    if (s.len > max_user_text_len) @compileError("user text exceeds max_user_text_len");
    var buf = std.mem.zeroes([max_user_text_len]u8);
    for (s, 0..) |byte, i| buf[i] = byte;
    return buf;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// Deterministic test fixtures for the five canonical investment themes.
pub const fixtures = struct {
    const default_asset_classes = cls.assetClassList(.{.equity});
    const default_instrument_types = cls.instrumentTypeList(.{ .stock, .etf });
    const default_asset_exclusions = cls.assetClassList(.{ .commodity, .fx, .crypto });
    const default_instrument_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund, .token });

    const ai_text =
        "I want to invest USD 2,000 in AI infrastructure, " ++
        "but avoid single-name concentration and keep it to US-listed ETFs or large-cap equities.";
    pub const ai_infrastructure = ThesisInput{
        .user_text = textBuf(ai_text),
        .user_text_len = @intCast(ai_text.len),
        .target_notional_cents = 200_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .themes = cls.themeIdList(.{"ai_infrastructure"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .moderate,
        .max_single_name_pct = 30,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const div_text =
        "I want USD 1,500 in US dividend-paying equities or dividend ETFs for steady income.";
    pub const us_dividends = ThesisInput{
        .user_text = textBuf(div_text),
        .user_text_len = @intCast(div_text.len),
        .target_notional_cents = 150_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .themes = cls.themeIdList(.{"dividends"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .low,
        .max_single_name_pct = 60,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const cyber_text =
        "I want USD 3,000 in US-listed cybersecurity equities or ETFs.";
    pub const cyber_security = ThesisInput{
        .user_text = textBuf(cyber_text),
        .user_text_len = @intCast(cyber_text.len),
        .target_notional_cents = 300_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .themes = cls.themeIdList(.{"cyber_security"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .moderate,
        .max_single_name_pct = 35,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const broad_text =
        "I want USD 5,000 in broad US market ETFs with low cost and wide diversification.";
    pub const broad_market = ThesisInput{
        .user_text = textBuf(broad_text),
        .user_text_len = @intCast(broad_text.len),
        .target_notional_cents = 500_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = cls.instrumentTypeList(.{.etf}),
        .themes = cls.themeIdList(.{"broad_market"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .moderate,
        .max_single_name_pct = 50,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    const cash_text =
        "I want USD 10,000 in cash-like US ETFs such as Treasury money market or short-duration bond ETFs.";
    pub const cash_preservation = ThesisInput{
        .user_text = textBuf(cash_text),
        .user_text_len = @intCast(cash_text.len),
        .target_notional_cents = 1_000_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{ .cash, .fixed_income }),
        .instrument_type_prefs = cls.instrumentTypeList(.{.etf}),
        .themes = cls.themeIdList(.{"cash_like"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .low,
        .max_single_name_pct = 50,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    /// Multi-theme fixture: AI infrastructure and semiconductors thesis.
    /// Proves that ThemeIdList can carry multiple themes for a combined mandate.
    const ai_semi_text =
        "I want USD 2,000 split across AI infrastructure and semiconductor leaders and ETFs.";
    pub const ai_and_semiconductors = ThesisInput{
        .user_text = textBuf(ai_semi_text),
        .user_text_len = @intCast(ai_semi_text.len),
        .target_notional_cents = 200_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .themes = cls.themeIdList(.{ "ai_infrastructure", "semiconductors" }),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .high,
        .max_single_name_pct = 25,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    /// Sector-filtered fixture: AI infrastructure restricted to industrials sector.
    /// Only BOTZ (robotics_and_ai) has industrials alongside information_technology,
    /// so all other ai_infrastructure instruments get wrong_sector rejected.
    const it_sector_ref = cls.classificationRef("gics_sector", 2025, "industrials");
    const ai_it_text =
        "I want USD 2,000 in AI infrastructure, industrials sector only.";
    pub const ai_infrastructure_it_sector = ThesisInput{
        .user_text = textBuf(ai_it_text),
        .user_text_len = @intCast(ai_it_text.len),
        .target_notional_cents = 200_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = default_asset_classes,
        .instrument_type_prefs = default_instrument_types,
        .themes = cls.themeIdList(.{"ai_infrastructure"}),
        .sector_filters = blk: {
            var refs = ClassificationRefList{};
            refs.append(it_sector_ref) catch unreachable;
            break :blk refs;
        },
        .industry_filters = ClassificationRefList{},
        .risk_preference = .moderate,
        .max_single_name_pct = 30,
        .asset_class_exclusions = default_asset_exclusions,
        .instrument_type_exclusions = default_instrument_exclusions,
    };

    // ---------------------------------------------------------------------------
    // T6 fixtures: classifications that can be expressed but are not permitted.
    // These prove the type system can represent chemical, gold, Solana, and
    // memecoin classifications without granting trading authority for them.
    // ---------------------------------------------------------------------------

    /// Chemical sector thesis (commodity asset class → denied by denied_asset_classes).
    const chemicals_text = "I want USD 1,000 in chemical sector commodity exposure.";
    pub const chemicals_commodity = ThesisInput{
        .user_text = textBuf(chemicals_text),
        .user_text_len = @intCast(chemicals_text.len),
        .target_notional_cents = 100_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{.commodity}),
        .instrument_type_prefs = cls.instrumentTypeList(.{ .etf, .fund }),
        .themes = cls.themeIdList(.{"chemicals"}),
        .sector_filters = blk: {
            var refs = ClassificationRefList{};
            refs.append(cls.classificationRef("gics_sector", 2025, "materials")) catch unreachable;
            break :blk refs;
        },
        .industry_filters = blk: {
            var refs = ClassificationRefList{};
            refs.append(cls.classificationRef("gics_industry", 2025, "chemicals")) catch unreachable;
            break :blk refs;
        },
        .risk_preference = .moderate,
        .max_single_name_pct = 50,
        .asset_class_exclusions = cls.assetClassList(.{ .fx, .crypto }),
        .instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .token }),
    };

    /// Gold thesis (commodity asset class → denied by denied_asset_classes).
    const gold_text = "I want USD 1,000 in gold commodity exposure.";
    pub const gold_commodity = ThesisInput{
        .user_text = textBuf(gold_text),
        .user_text_len = @intCast(gold_text.len),
        .target_notional_cents = 100_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{.commodity}),
        .instrument_type_prefs = cls.instrumentTypeList(.{ .etf, .fund }),
        .themes = cls.themeIdList(.{"gold"}),
        .sector_filters = blk: {
            var refs = ClassificationRefList{};
            refs.append(cls.classificationRef("gics_sector", 2025, "materials")) catch unreachable;
            break :blk refs;
        },
        .industry_filters = blk: {
            var refs = ClassificationRefList{};
            refs.append(cls.classificationRef("gics_industry", 2025, "gold")) catch unreachable;
            break :blk refs;
        },
        .risk_preference = .moderate,
        .max_single_name_pct = 50,
        .asset_class_exclusions = cls.assetClassList(.{ .fx, .crypto }),
        .instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .token }),
    };

    /// Solana thesis (crypto asset class → denied by denied_asset_classes).
    const solana_text = "I want USD 500 in Solana crypto exposure.";
    pub const solana_crypto = ThesisInput{
        .user_text = textBuf(solana_text),
        .user_text_len = @intCast(solana_text.len),
        .target_notional_cents = 50_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{.crypto}),
        .instrument_type_prefs = cls.instrumentTypeList(.{.token}),
        .themes = cls.themeIdList(.{"solana"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .high,
        .max_single_name_pct = 100,
        .asset_class_exclusions = cls.assetClassList(.{ .commodity, .fx }),
        .instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund }),
    };

    /// Memecoin thesis (crypto asset class → denied by denied_asset_classes).
    const memecoin_text = "I want USD 100 in memecoin crypto speculation.";
    pub const memecoins_crypto = ThesisInput{
        .user_text = textBuf(memecoin_text),
        .user_text_len = @intCast(memecoin_text.len),
        .target_notional_cents = 10_000,
        .account_id = 1001,
        .market_scope = .us,
        .asset_class_prefs = cls.assetClassList(.{.crypto}),
        .instrument_type_prefs = cls.instrumentTypeList(.{.token}),
        .themes = cls.themeIdList(.{"memecoins"}),
        .sector_filters = ClassificationRefList{},
        .industry_filters = ClassificationRefList{},
        .risk_preference = .high,
        .max_single_name_pct = 100,
        .asset_class_exclusions = cls.assetClassList(.{ .commodity, .fx }),
        .instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund }),
    };
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "schema version matches codec constant" {
    try std.testing.expectEqual(@as(u16, 3), thesis_schema_version);
}

test "thesis proto message contract stays aligned with zig definitions" {
    const thesis_proto = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, thesis_proto_path, std.testing.allocator, .limited(32 * 1024));
    defer std.testing.allocator.free(thesis_proto);

    const required_lines = [_][]const u8{
        "ThemeIdList        themes                       = 7;",
        "ClassificationRefList sector_filters           = 8;",
        "ClassificationRefList industry_filters         = 9;",
        "repeated bytes     requested_tickers            = 14;",
        "ThemeIdList        themes                       = 2;",
        "ClassificationRefList sectors                  = 3;",
        "ClassificationRefList industries               = 4;",
        "uint32      theme_count         = 3;",
    };
    for (required_lines) |line| {
        try std.testing.expect(std.mem.indexOf(u8, thesis_proto, line) != null);
    }
}

test "normalize: ai_infrastructure fixture produces valid intent" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expectEqual(@as(u32, 1001), intent.account_id);
    try std.testing.expect(intent.themes.has(CanonicalId.init("ai_infrastructure") catch unreachable));
    try std.testing.expectEqual(@as(u8, 1), intent.themes.count);
    try std.testing.expectEqual(@as(i64, 200_000), intent.target_amount_cents);
    try std.testing.expect(intent.allowed_asset_classes.has(.equity));
    try std.testing.expect(intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expectEqual(@as(u8, 2), intent.venue_count);
    try std.testing.expectEqual(Venue.nyse, intent.venues[0]);
    try std.testing.expectEqual(Venue.nasdaq, intent.venues[1]);
    try std.testing.expectEqual(Market.us, intent.market);
    try std.testing.expectEqual(RiskPreference.moderate, intent.risk_preference);
    try std.testing.expectEqual(@as(u8, 30), intent.max_single_name_pct);
    try std.testing.expectEqual(@as(u8, 0), intent.sectors.count);
    try std.testing.expectEqual(@as(u8, 0), intent.industries.count);
}

test "normalize: account_id is preserved in InvestorIntent" {
    var input = fixtures.ai_infrastructure;
    input.account_id = 42;
    const intent = try normalize(input);
    try std.testing.expectEqual(@as(u32, 42), intent.account_id);
}

test "normalize: all five fixtures produce valid intent" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |fixture| {
        _ = try normalize(fixture);
    }
}

test "normalize: always-denied classes excluded from allowed_asset_classes" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(!intent.allowed_asset_classes.has(.commodity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.fx));
    try std.testing.expect(!intent.allowed_asset_classes.has(.crypto));
}

test "normalize: always-denied instrument types excluded from allowed_instrument_types" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(!intent.allowed_instrument_types.has(.bond));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expect(!intent.allowed_instrument_types.has(.future));
    try std.testing.expect(!intent.allowed_instrument_types.has(.fund));
    try std.testing.expect(!intent.allowed_instrument_types.has(.token));
}

test "normalize: always-denied lists present in excluded lists" {
    const intent = try normalize(fixtures.ai_infrastructure);
    try std.testing.expect(intent.excluded_asset_classes.has(.commodity));
    try std.testing.expect(intent.excluded_asset_classes.has(.fx));
    try std.testing.expect(intent.excluded_asset_classes.has(.crypto));
    try std.testing.expect(intent.excluded_instrument_types.has(.bond));
    try std.testing.expect(intent.excluded_instrument_types.has(.option));
    try std.testing.expect(intent.excluded_instrument_types.has(.future));
    try std.testing.expect(intent.excluded_instrument_types.has(.fund));
    try std.testing.expect(intent.excluded_instrument_types.has(.token));
}

test "normalize: denied values removed from allowed lists even when user requests them" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = cls.assetClassList(.{ .equity, .commodity, .crypto });
    input.instrument_type_prefs = cls.instrumentTypeList(.{ .stock, .etf, .option, .future });
    const intent = try normalize(input);
    try std.testing.expect(intent.allowed_asset_classes.has(.equity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.commodity));
    try std.testing.expect(!intent.allowed_asset_classes.has(.crypto));
    try std.testing.expect(intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!intent.allowed_instrument_types.has(.option));
    try std.testing.expect(!intent.allowed_instrument_types.has(.future));
}

test "normalize: explicit exclusions remove otherwise-allowed values and remain in excluded lists" {
    var input = fixtures.cash_preservation;
    input.asset_class_exclusions = cls.assetClassList(.{ .commodity, .fx, .crypto, .fixed_income });
    const intent = try normalize(input);
    try std.testing.expect(intent.allowed_asset_classes.has(.cash));
    try std.testing.expect(!intent.allowed_asset_classes.has(.fixed_income));
    try std.testing.expect(intent.excluded_asset_classes.has(.fixed_income));

    var ai_input = fixtures.ai_infrastructure;
    ai_input.instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund, .token, .stock });
    const ai_intent = try normalize(ai_input);
    try std.testing.expect(ai_intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(!ai_intent.allowed_instrument_types.has(.stock));
    try std.testing.expect(ai_intent.excluded_instrument_types.has(.stock));
}

test "normalize: empty user text returns EmptyUserText" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = 0;
    try std.testing.expectError(ThesisError.EmptyUserText, normalize(input));
}

test "normalize: user_text_len exceeding max returns UserTextTooLong" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = @intCast(max_user_text_len + 1);
    try std.testing.expectError(ThesisError.UserTextTooLong, normalize(input));
}

test "normalize: zero target notional returns MissingTargetAmount" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = 0;
    try std.testing.expectError(ThesisError.MissingTargetAmount, normalize(input));
}

test "normalize: negative target notional returns MissingTargetAmount" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = -1;
    try std.testing.expectError(ThesisError.MissingTargetAmount, normalize(input));
}

test "normalize: notional below minimum returns TargetAmountTooSmall" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = 50;
    try std.testing.expectError(ThesisError.TargetAmountTooSmall, normalize(input));
}

test "normalize: notional above maximum returns TargetAmountTooLarge" {
    var input = fixtures.ai_infrastructure;
    input.target_notional_cents = max_target_notional_cents + 1;
    try std.testing.expectError(ThesisError.TargetAmountTooLarge, normalize(input));
}

test "normalize: empty themes list returns EmptyThemeFilter" {
    var input = fixtures.ai_infrastructure;
    input.themes = ThemeIdList{};
    try std.testing.expectError(ThesisError.EmptyThemeFilter, normalize(input));
}

test "normalize: denied-only asset classes return NoEligibleAssetClass" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs = cls.assetClassList(.{ .commodity, .crypto });
    try std.testing.expectError(ThesisError.NoEligibleAssetClass, normalize(input));
}

test "normalize: denied-only instrument types return NoEligibleInstrumentType" {
    var input = fixtures.ai_infrastructure;
    input.instrument_type_prefs = cls.instrumentTypeList(.{ .option, .future });
    try std.testing.expectError(ThesisError.NoEligibleInstrumentType, normalize(input));
}

test "normalize: duplicate classifications fail closed" {
    var input = fixtures.ai_infrastructure;
    input.asset_class_prefs.count = 2;
    input.asset_class_prefs.values[0] = .equity;
    input.asset_class_prefs.values[1] = .equity;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: malformed theme id fails closed" {
    var input = fixtures.ai_infrastructure;
    input.themes = ThemeIdList{};
    input.themes.values[0].bytes[0] = 'A';
    input.themes.values[0].bytes[1] = 'I';
    input.themes.values[0].len = 2;
    input.themes.count = 1;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: duplicate theme ids fail closed" {
    var input = fixtures.ai_infrastructure;
    const t = cls.CanonicalId.init("ai_infrastructure") catch unreachable;
    input.themes = ThemeIdList{};
    input.themes.values[0] = t;
    input.themes.values[1] = t;
    input.themes.count = 2;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: unknown theme id fails closed" {
    var input = fixtures.ai_infrastructure;
    input.themes = ThemeIdList{};
    input.themes.append(CanonicalId.init("quantum") catch unreachable) catch unreachable;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: sector filter with missing taxonomy_version fails closed" {
    var input = fixtures.ai_infrastructure;
    var refs = ClassificationRefList{};
    // taxonomy_version = 0 is invalid
    refs.values[0] = ClassificationRef{ .taxonomy_id = CanonicalId.init("gics_sector") catch unreachable, .taxonomy_version = 0, .code = CanonicalId.init("information_technology") catch unreachable };
    refs.count = 1;
    input.sector_filters = refs;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: sector filter with unknown taxonomy id fails closed" {
    var input = fixtures.ai_infrastructure;
    var refs = ClassificationRefList{};
    refs.append(
        ClassificationRef.init("sic_sector", 2025, "information_technology") catch unreachable,
    ) catch unreachable;
    input.sector_filters = refs;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: sector filter with unknown code fails closed" {
    var input = fixtures.ai_infrastructure;
    var refs = ClassificationRefList{};
    refs.append(
        ClassificationRef.init("gics_sector", 2025, "real_estate") catch unreachable,
    ) catch unreachable;
    input.sector_filters = refs;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: industry filter with duplicate ref fails closed" {
    var input = fixtures.ai_infrastructure;
    const ref = cls.ClassificationRef.init("gics_industry", 2025, "semiconductors") catch unreachable;
    var refs = ClassificationRefList{};
    refs.values[0] = ref;
    refs.values[1] = ref;
    refs.count = 2;
    input.industry_filters = refs;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: industry filter with wrong taxonomy id fails closed" {
    var input = fixtures.ai_infrastructure;
    var refs = ClassificationRefList{};
    refs.append(
        ClassificationRef.init("gics_sector", 2025, "semiconductors") catch unreachable,
    ) catch unreachable;
    input.industry_filters = refs;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: too many requested tickers fails closed" {
    var input = fixtures.ai_infrastructure;
    input.requested_ticker_count = max_requested_tickers + 1;
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: duplicate requested tickers fail closed" {
    var input = fixtures.ai_infrastructure;
    input.requested_ticker_count = 2;
    @memset(&input.requested_tickers[0], 0);
    @memset(&input.requested_tickers[1], 0);
    @memcpy(input.requested_tickers[0][0..4], "SOXL");
    @memcpy(input.requested_tickers[1][0..4], "SOXL");
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: unknown requested ticker fails closed" {
    var input = fixtures.ai_infrastructure;
    input.requested_ticker_count = 1;
    @memset(&input.requested_tickers[0], 0);
    @memcpy(input.requested_tickers[0][0..4], "ZZZZ");
    try std.testing.expectError(ThesisError.MalformedClassification, normalize(input));
}

test "normalize: cash_preservation fixture keeps fixed income and cash exposure" {
    const intent = try normalize(fixtures.cash_preservation);
    try std.testing.expect(intent.allowed_asset_classes.has(.cash));
    try std.testing.expect(intent.allowed_asset_classes.has(.fixed_income));
    try std.testing.expect(intent.allowed_instrument_types.has(.etf));
    try std.testing.expect(intent.themes.has(CanonicalId.init("cash_like") catch unreachable));
    try std.testing.expectEqual(RiskPreference.low, intent.risk_preference);
}

test "normalize: multi-theme fixture produces correct theme list" {
    const intent = try normalize(fixtures.ai_and_semiconductors);
    try std.testing.expectEqual(@as(u8, 2), intent.themes.count);
    try std.testing.expect(intent.themes.has(CanonicalId.init("ai_infrastructure") catch unreachable));
    try std.testing.expect(intent.themes.has(CanonicalId.init("semiconductors") catch unreachable));
}

test "normalize: sector-filtered fixture carries sector ref through to intent" {
    const intent = try normalize(fixtures.ai_infrastructure_it_sector);
    try std.testing.expectEqual(@as(u8, 1), intent.sectors.count);
    try std.testing.expect(intent.sectors.has(
        cls.ClassificationRef.init("gics_sector", 2025, "industrials") catch unreachable,
    ));
    try std.testing.expectEqual(@as(u8, 0), intent.industries.count);
}

test "normalize: themes sorted into canonical order" {
    // Provide themes in reverse alphabetical order; normalize must sort them.
    var input = fixtures.ai_infrastructure;
    input.themes = ThemeIdList{};
    input.themes.values[0] = CanonicalId.init("semiconductors") catch unreachable;
    input.themes.values[1] = CanonicalId.init("ai_infrastructure") catch unreachable;
    input.themes.count = 2;
    const intent = try normalize(input);
    // After sorting: ai_infrastructure < semiconductors lexicographically.
    try std.testing.expectEqualStrings("ai_infrastructure", intent.themes.values[0].slice());
    try std.testing.expectEqualStrings("semiconductors", intent.themes.values[1].slice());
}

test "normalize: sector filters sorted into canonical order" {
    var input = fixtures.ai_infrastructure;
    var refs = ClassificationRefList{};
    refs.values[0] = cls.ClassificationRef.init("gics_sector", 2025, "information_technology") catch unreachable;
    refs.values[1] = cls.ClassificationRef.init("gics_sector", 2025, "consumer_discretionary") catch unreachable;
    refs.count = 2;
    input.sector_filters = refs;
    const intent = try normalize(input);
    // consumer_discretionary < information_technology lexicographically.
    try std.testing.expectEqualStrings("consumer_discretionary", intent.sectors.values[0].code.slice());
    try std.testing.expectEqualStrings("information_technology", intent.sectors.values[1].code.slice());
}

test "fixtures: text() length matches user_text_len" {
    for ([_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    }) |fixture| {
        try std.testing.expectEqual(@as(usize, fixture.user_text_len), fixture.text().len);
    }
}

test "computeThesisInputHash: same input produces same hash" {
    const h1 = computeThesisInputHash(fixtures.ai_infrastructure);
    const h2 = computeThesisInputHash(fixtures.ai_infrastructure);
    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != 0);
}

test "computeThesisInputHash: different account_id produces different hash" {
    var other = fixtures.ai_infrastructure;
    other.account_id = 9999;
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other),
    );
}

test "computeThesisInputHash: different themes produce different hashes" {
    var other = fixtures.ai_infrastructure;
    other.themes = ThemeIdList{};
    other.themes.append(CanonicalId.init("cloud") catch unreachable) catch unreachable;
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other),
    );
}

test "computeThesisInputHash: different instrument type prefs produce different hashes" {
    var other = fixtures.ai_infrastructure;
    other.instrument_type_prefs = cls.instrumentTypeList(.{.stock});
    try std.testing.expect(
        computeThesisInputHash(fixtures.ai_infrastructure) != computeThesisInputHash(other),
    );
}

test "computeThesisInputHash: theme ordering does not affect hash" {
    var unordered = fixtures.ai_and_semiconductors;
    // Swap the two themes so they arrive in reverse order.
    const first = unordered.themes.values[0];
    unordered.themes.values[0] = unordered.themes.values[1];
    unordered.themes.values[1] = first;
    // Both orderings must produce the same hash after canonical sort.
    try std.testing.expectEqual(
        computeThesisInputHash(fixtures.ai_and_semiconductors),
        computeThesisInputHash(unordered),
    );
}

test "computeThesisInputHash: sector filter ordering does not affect hash" {
    // Provide sector filters in reverse alphabetical order; normalize must sort them
    // before hashing so both orderings of the same set produce the same hash.
    var forward = fixtures.ai_infrastructure;
    forward.sector_filters = blk: {
        var refs = ClassificationRefList{};
        refs.append(cls.ClassificationRef.init("gics_sector", 2025, "consumer_discretionary") catch unreachable) catch unreachable;
        refs.append(cls.ClassificationRef.init("gics_sector", 2025, "information_technology") catch unreachable) catch unreachable;
        break :blk refs;
    };
    var reversed = fixtures.ai_infrastructure;
    reversed.sector_filters = blk: {
        var refs = ClassificationRefList{};
        refs.append(cls.ClassificationRef.init("gics_sector", 2025, "information_technology") catch unreachable) catch unreachable;
        refs.append(cls.ClassificationRef.init("gics_sector", 2025, "consumer_discretionary") catch unreachable) catch unreachable;
        break :blk refs;
    };
    try std.testing.expectEqual(
        computeThesisInputHash(forward),
        computeThesisInputHash(reversed),
    );
}

test "computeThesisInputHash: sector filter changes hash" {
    const h_no_sector = computeThesisInputHash(fixtures.ai_infrastructure);
    const h_with_sector = computeThesisInputHash(fixtures.ai_infrastructure_it_sector);
    try std.testing.expect(h_no_sector != h_with_sector);
}

test "computeThesisInputHash: all five fixtures produce distinct hashes" {
    const all = [_]ThesisInput{
        fixtures.ai_infrastructure,
        fixtures.us_dividends,
        fixtures.cyber_security,
        fixtures.broad_market,
        fixtures.cash_preservation,
    };
    for (all, 0..) |a, i| {
        for (all, 0..) |b, j| {
            if (i != j) {
                try std.testing.expect(computeThesisInputHash(a) != computeThesisInputHash(b));
            }
        }
    }
}

test "computeThesisInputHash: unsafe user_text_len returns 0" {
    var input = fixtures.ai_infrastructure;
    input.user_text_len = @intCast(max_user_text_len + 1);
    try std.testing.expectEqual(@as(u64, 0), computeThesisInputHash(input));
}

// ---------------------------------------------------------------------------
// T6: Denied classification fixtures — expressed but not automatically permitted
// ---------------------------------------------------------------------------

test "T6: chemicals commodity thesis is denied at normalize (commodity denied)" {
    try std.testing.expectError(
        ThesisError.NoEligibleAssetClass,
        normalize(fixtures.chemicals_commodity),
    );
}

test "T6: gold commodity thesis is denied at normalize (commodity denied)" {
    try std.testing.expectError(
        ThesisError.NoEligibleAssetClass,
        normalize(fixtures.gold_commodity),
    );
}

test "T6: solana crypto thesis is denied at normalize (crypto denied)" {
    try std.testing.expectError(
        ThesisError.NoEligibleAssetClass,
        normalize(fixtures.solana_crypto),
    );
}

test "T6: memecoins crypto thesis is denied at normalize (crypto denied)" {
    try std.testing.expectError(
        ThesisError.NoEligibleAssetClass,
        normalize(fixtures.memecoins_crypto),
    );
}

test "T6: denied classification fixtures can express sector/industry refs without compile error" { // Classification data is well-formed even though policy denies trading authority.
    try std.testing.expect(fixtures.chemicals_commodity.sector_filters.count == 1);
    try std.testing.expect(fixtures.chemicals_commodity.industry_filters.count == 1);
    try std.testing.expect(fixtures.gold_commodity.sector_filters.count == 1);
    try std.testing.expect(fixtures.gold_commodity.industry_filters.count == 1);
    try std.testing.expect(fixtures.solana_crypto.sector_filters.count == 0);
    try std.testing.expect(fixtures.memecoins_crypto.themes.count == 1);
}

test "T6: classification can be expressed independently from trading authority" {
    // A classification that maps to commodity or crypto is representable in the
    // type system via asset_class_prefs = .commodity/.crypto, a sector ref, and
    // an industry ref.  The denied_asset_classes policy barrier prevents any
    // allowed_asset_classes from containing those values.
    const chem_intent_err = normalize(fixtures.chemicals_commodity);
    try std.testing.expectError(ThesisError.NoEligibleAssetClass, chem_intent_err);

    // If we allow equity instead (a different asset class that IS permitted),
    // the sector/industry refs themselves carry no extra trading authority.
    var equity_chem = fixtures.chemicals_commodity;
    equity_chem.asset_class_prefs = cls.assetClassList(.{.equity});
    equity_chem.instrument_type_prefs = cls.instrumentTypeList(.{ .stock, .etf });
    equity_chem.asset_class_exclusions = cls.assetClassList(.{ .commodity, .fx, .crypto });
    equity_chem.instrument_type_exclusions = cls.instrumentTypeList(.{ .bond, .option, .future, .fund, .token });
    // normalize() succeeds — the sector ref is allowed intent metadata, not a grant.
    const equity_intent = try normalize(equity_chem);
    try std.testing.expect(equity_intent.allowed_asset_classes.has(.equity));
    // The sector filter is carried through to the intent but does not grant
    // authority over any classification not already permitted by asset_class.
    try std.testing.expectEqual(@as(u8, 1), equity_intent.sectors.count);
}
