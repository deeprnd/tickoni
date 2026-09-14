/// Shared instrument classification schema
///
/// This module is the single Zig source of truth for bounded financial
/// classification primitives that are shared across thesis intent, catalog
/// facts, basket construction, and policy screening.
const std = @import("std");
const fixture_paths = @import("fixture_paths");

comptime {
    @setEvalBranchQuota(50_000);
}

pub const classification_contract_version: u16 = 1;

pub const max_canonical_id_len: usize = 32;
pub const max_asset_class_values: usize = 8;
pub const max_instrument_type_values: usize = 8;
pub const max_classification_refs: usize = 8;
pub const max_theme_ids: usize = 8;

pub const Market = enum(u8) { us };

pub const Venue = enum(u8) { nyse, nasdaq };

pub const AssetClass = enum(u8) {
    equity,
    fixed_income,
    commodity,
    fx,
    crypto,
    cash,

    pub fn label(self: AssetClass) []const u8 {
        return switch (self) {
            .equity => "equity",
            .fixed_income => "fixed_income",
            .commodity => "commodity",
            .fx => "fx",
            .crypto => "crypto",
            .cash => "cash",
        };
    }
};

pub const InstrumentType = enum(u8) {
    stock,
    etf,
    bond,
    option,
    future,
    fund,
    token,

    pub fn label(self: InstrumentType) []const u8 {
        return switch (self) {
            .stock => "stock",
            .etf => "ETF",
            .bond => "bond",
            .option => "option",
            .future => "future",
            .fund => "fund",
            .token => "token",
        };
    }
};

pub const RiskPreference = enum(u8) { low, moderate, high };

pub const CanonicalIdError = error{
    Empty,
    TooLong,
    InvalidEncoding,
};

pub const AssetClassListError = error{
    TooManyValues,
    DuplicateValue,
};

pub const InstrumentTypeListError = error{
    TooManyValues,
    DuplicateValue,
};

pub const ClassificationRefError = error{
    MissingTaxonomyVersion,
    TooManyValues,
    DuplicateValue,
    InvalidEncoding,
};

pub const ThemeIdListError = error{
    TooManyValues,
    DuplicateValue,
    InvalidEncoding,
};

pub const CanonicalId = struct {
    bytes: [max_canonical_id_len]u8 = std.mem.zeroes([max_canonical_id_len]u8),
    len: u8 = 0,

    pub fn slice(self: *const CanonicalId) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: CanonicalId, other: CanonicalId) bool {
        return std.mem.eql(u8, self.slice(), other.slice());
    }

    pub fn init(value: []const u8) CanonicalIdError!CanonicalId {
        try validateCanonicalId(value);
        var out = CanonicalId{};
        @memcpy(out.bytes[0..value.len], value);
        out.len = @intCast(value.len);
        return out;
    }
};

pub fn canonicalId(comptime raw_value: anytype) CanonicalId {
    const value = canonicalInputSlice(raw_value);
    validateCanonicalId(value) catch |err| switch (err) {
        error.Empty => @compileError("canonical id must be non-empty"),
        error.TooLong => @compileError("canonical id exceeds max_canonical_id_len"),
        error.InvalidEncoding => @compileError("canonical id must use lowercase ascii, digits, or underscore, and start with a letter"),
    };
    var out = CanonicalId{};
    inline for (value, 0..) |byte, i| out.bytes[i] = byte;
    out.len = value.len;
    return out;
}

pub const ClassificationRef = struct {
    taxonomy_id: CanonicalId = .{},
    taxonomy_version: u16 = 0,
    code: CanonicalId = .{},

    pub fn eql(self: ClassificationRef, other: ClassificationRef) bool {
        return self.taxonomy_version == other.taxonomy_version and
            self.taxonomy_id.eql(other.taxonomy_id) and
            self.code.eql(other.code);
    }

    pub fn init(
        taxonomy_id_value: []const u8,
        taxonomy_version_value: u16,
        code_value: []const u8,
    ) ClassificationRefError!ClassificationRef {
        if (taxonomy_version_value == 0) return ClassificationRefError.MissingTaxonomyVersion;
        return .{
            .taxonomy_id = CanonicalId.init(taxonomy_id_value) catch return ClassificationRefError.InvalidEncoding,
            .taxonomy_version = taxonomy_version_value,
            .code = CanonicalId.init(code_value) catch return ClassificationRefError.InvalidEncoding,
        };
    }
};

pub fn classificationRef(
    comptime taxonomy_id_value: anytype,
    comptime taxonomy_version_value: u16,
    comptime code_value: anytype,
) ClassificationRef {
    if (taxonomy_version_value == 0) {
        @compileError("classification taxonomy_version must be non-zero");
    }
    return .{
        .taxonomy_id = canonicalId(taxonomy_id_value),
        .taxonomy_version = taxonomy_version_value,
        .code = canonicalId(code_value),
    };
}

pub const AssetClassList = struct {
    values: [max_asset_class_values]AssetClass = std.mem.zeroes([max_asset_class_values]AssetClass),
    count: u8 = 0,

    pub fn has(self: AssetClassList, value: AssetClass) bool {
        for (self.values[0..self.count]) |member| {
            if (member == value) return true;
        }
        return false;
    }

    pub fn append(self: *AssetClassList, value: AssetClass) AssetClassListError!void {
        if (self.has(value)) return AssetClassListError.DuplicateValue;
        if (self.count >= max_asset_class_values) return AssetClassListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: AssetClassList) AssetClassListError!void {
        if (self.count > max_asset_class_values) return AssetClassListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            for (self.values[0..i]) |prior| {
                if (prior == value) return AssetClassListError.DuplicateValue;
            }
        }
    }
};

pub fn assetClassList(comptime values: anytype) AssetClassList {
    var out = AssetClassList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_asset_class_values) @compileError("too many asset classes in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior == value) @compileError("duplicate asset class in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

pub const InstrumentTypeList = struct {
    values: [max_instrument_type_values]InstrumentType = std.mem.zeroes([max_instrument_type_values]InstrumentType),
    count: u8 = 0,

    pub fn has(self: InstrumentTypeList, value: InstrumentType) bool {
        for (self.values[0..self.count]) |member| {
            if (member == value) return true;
        }
        return false;
    }

    pub fn append(self: *InstrumentTypeList, value: InstrumentType) InstrumentTypeListError!void {
        if (self.has(value)) return InstrumentTypeListError.DuplicateValue;
        if (self.count >= max_instrument_type_values) return InstrumentTypeListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: InstrumentTypeList) InstrumentTypeListError!void {
        if (self.count > max_instrument_type_values) return InstrumentTypeListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            for (self.values[0..i]) |prior| {
                if (prior == value) return InstrumentTypeListError.DuplicateValue;
            }
        }
    }
};

pub fn instrumentTypeList(comptime values: anytype) InstrumentTypeList {
    var out = InstrumentTypeList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_instrument_type_values) @compileError("too many instrument types in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior == value) @compileError("duplicate instrument type in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

pub const ThemeIdList = struct {
    values: [max_theme_ids]CanonicalId = std.mem.zeroes([max_theme_ids]CanonicalId),
    count: u8 = 0,

    pub fn has(self: ThemeIdList, value: CanonicalId) bool {
        for (self.values[0..self.count]) |member| {
            if (member.eql(value)) return true;
        }
        return false;
    }

    pub fn append(self: *ThemeIdList, value: CanonicalId) ThemeIdListError!void {
        if (self.has(value)) return ThemeIdListError.DuplicateValue;
        if (self.count >= max_theme_ids) return ThemeIdListError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: ThemeIdList) ThemeIdListError!void {
        if (self.count > max_theme_ids) return ThemeIdListError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            if (value.len == 0) return ThemeIdListError.InvalidEncoding;
            validateCanonicalId(value.slice()) catch return ThemeIdListError.InvalidEncoding;
            for (self.values[0..i]) |prior| {
                if (prior.eql(value)) return ThemeIdListError.DuplicateValue;
            }
        }
    }
};

pub fn themeIdList(comptime values: anytype) ThemeIdList {
    var out = ThemeIdList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_theme_ids) @compileError("too many theme ids in literal");
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (std.mem.eql(u8, canonicalInputSlice(prior), canonicalInputSlice(value))) {
                @compileError("duplicate theme id in literal");
            }
        }
        out.values[i] = canonicalId(value);
        out.count = i + 1;
    }
    return out;
}

pub const ClassificationRefList = struct {
    values: [max_classification_refs]ClassificationRef = std.mem.zeroes([max_classification_refs]ClassificationRef),
    count: u8 = 0,

    pub fn has(self: ClassificationRefList, value: ClassificationRef) bool {
        for (self.values[0..self.count]) |member| {
            if (member.eql(value)) return true;
        }
        return false;
    }

    pub fn append(self: *ClassificationRefList, value: ClassificationRef) ClassificationRefError!void {
        if (value.taxonomy_version == 0) return ClassificationRefError.MissingTaxonomyVersion;
        validateCanonicalId(value.taxonomy_id.slice()) catch return ClassificationRefError.InvalidEncoding;
        validateCanonicalId(value.code.slice()) catch return ClassificationRefError.InvalidEncoding;
        if (self.has(value)) return ClassificationRefError.DuplicateValue;
        if (self.count >= max_classification_refs) return ClassificationRefError.TooManyValues;
        self.values[self.count] = value;
        self.count += 1;
    }

    pub fn validate(self: ClassificationRefList) ClassificationRefError!void {
        if (self.count > max_classification_refs) return ClassificationRefError.TooManyValues;
        for (self.values[0..self.count], 0..) |value, i| {
            if (value.taxonomy_version == 0) return ClassificationRefError.MissingTaxonomyVersion;
            validateCanonicalId(value.taxonomy_id.slice()) catch return ClassificationRefError.InvalidEncoding;
            validateCanonicalId(value.code.slice()) catch return ClassificationRefError.InvalidEncoding;
            for (self.values[0..i]) |prior| {
                if (prior.eql(value)) return ClassificationRefError.DuplicateValue;
            }
        }
    }
};

pub fn classificationRefList(comptime values: anytype) ClassificationRefList {
    var out = ClassificationRefList{};
    inline for (values, 0..) |value, i| {
        if (i >= max_classification_refs) @compileError("too many classification refs in literal");
        if (value.taxonomy_version == 0) @compileError("classification taxonomy_version must be non-zero");
        validateCanonicalId(value.taxonomy_id.slice()) catch |err| switch (err) {
            error.Empty => @compileError("classification taxonomy_id must be non-empty"),
            error.TooLong => @compileError("classification taxonomy_id exceeds max_canonical_id_len"),
            error.InvalidEncoding => @compileError("classification taxonomy_id must be a canonical id"),
        };
        validateCanonicalId(value.code.slice()) catch |err| switch (err) {
            error.Empty => @compileError("classification code must be non-empty"),
            error.TooLong => @compileError("classification code exceeds max_canonical_id_len"),
            error.InvalidEncoding => @compileError("classification code must be a canonical id"),
        };
        inline for (values, 0..) |prior, j| {
            if (j >= i) break;
            if (prior.eql(value)) @compileError("duplicate classification ref in literal");
        }
        out.values[i] = value;
        out.count = i + 1;
    }
    return out;
}

// ---------------------------------------------------------------------------
// Known taxonomy values
//
// Single source of truth for which theme/sector/industry canonical ids are
// currently recognized, and which taxonomy (id + version) sector/industry
// codes are checked against. thesis.zig's normalize() validates investor
// input against these; catalog.zig's fixture instruments are drawn from
// (and should stay a subset of) the same lists, so the two never drift
// against each other silently.
// ---------------------------------------------------------------------------

pub const sector_taxonomy_id = canonicalId("gics_sector");
pub const industry_taxonomy_id = canonicalId("gics_industry");
pub const sector_taxonomy_version: u16 = 2025;
pub const industry_taxonomy_version: u16 = 2025;

pub const known_theme_ids = [_]CanonicalId{
    canonicalId("ai_infrastructure"),
    canonicalId("semiconductors"),
    canonicalId("cloud"),
    canonicalId("cyber_security"),
    canonicalId("broad_market"),
    canonicalId("dividends"),
    canonicalId("cash_like"),
    canonicalId("chemicals"),
    canonicalId("gold"),
    canonicalId("solana"),
    canonicalId("memecoins"),
};

pub const known_sector_codes = [_]CanonicalId{
    canonicalId("information_technology"),
    canonicalId("industrials"),
    canonicalId("consumer_discretionary"),
    canonicalId("financials"),
    canonicalId("health_care"),
    canonicalId("consumer_staples"),
    canonicalId("utilities"),
    canonicalId("materials"),
};

pub const known_industry_codes = [_]CanonicalId{
    canonicalId("semiconductors"),
    canonicalId("systems_software"),
    canonicalId("robotics_and_ai"),
    canonicalId("internet_retail"),
    canonicalId("cloud_platforms"),
    canonicalId("cloud_software"),
    canonicalId("cybersecurity"),
    canonicalId("sovereign_debt"),
    canonicalId("chemicals"),
    canonicalId("gold"),
};

/// True when value is present in a plain []const CanonicalId list (linear
/// scan — these lists are small and comptime-sized, not a hot path).
pub fn hasCanonicalId(known_values: []const CanonicalId, value: CanonicalId) bool {
    for (known_values) |known| {
        if (known.eql(value)) return true;
    }
    return false;
}

pub fn validateCanonicalId(value: []const u8) CanonicalIdError!void {
    @setEvalBranchQuota(50_000);
    if (value.len == 0) return CanonicalIdError.Empty;
    if (value.len > max_canonical_id_len) return CanonicalIdError.TooLong;
    if (!isLowerAlpha(value[0])) return CanonicalIdError.InvalidEncoding;
    for (value) |byte| {
        if (!(isLowerAlpha(byte) or isDigit(byte) or byte == '_')) {
            return CanonicalIdError.InvalidEncoding;
        }
    }
}

fn isLowerAlpha(byte: u8) bool {
    return byte >= 'a' and byte <= 'z';
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn canonicalInputSlice(comptime value: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => value,
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| value.*[0..array.len],
                else => @compileError("unsupported canonical id pointer input"),
            },
            else => @compileError("unsupported canonical id pointer input"),
        },
        .array => value[0..],
        else => value,
    };
}

const ProtoEnumEntry = struct {
    name: []const u8,
    value: u32,
};

const ProtoField = struct {
    type_name: []const u8,
    field_name: []const u8,
    field_number: u32,
};

fn expectProtoEnumMatchesZigEnum(
    classification_proto: []const u8,
    comptime ZigEnum: type,
    comptime proto_enum_name: []const u8,
    comptime proto_prefix: []const u8,
) !void {
    const proto_entries = try parseProtoEnum(classification_proto, proto_enum_name);
    const zig_fields = std.meta.fields(ZigEnum);

    try std.testing.expectEqual(zig_fields.len + 1, proto_entries.len);
    try std.testing.expectEqualStrings(
        std.fmt.comptimePrint("{s}UNSPECIFIED", .{proto_prefix}),
        proto_entries[0].name,
    );
    try std.testing.expectEqual(@as(u32, 0), proto_entries[0].value);

    inline for (zig_fields, 0..) |field, i| {
        const expected_name = comptime std.fmt.comptimePrint(
            "{s}{s}",
            .{ proto_prefix, upperSnake(field.name) },
        );
        try std.testing.expectEqualStrings(expected_name, proto_entries[i + 1].name);
        try std.testing.expectEqual(@as(u32, i + 1), proto_entries[i + 1].value);
    }
}

fn expectProtoMessageFields(
    classification_proto: []const u8,
    comptime proto_message_name: []const u8,
    comptime expected_fields: []const ProtoField,
) !void {
    const fields = try parseProtoMessage(classification_proto, proto_message_name);
    try std.testing.expectEqual(expected_fields.len, fields.len);
    for (expected_fields, fields) |expected, actual| {
        try std.testing.expectEqualStrings(expected.type_name, actual.type_name);
        try std.testing.expectEqualStrings(expected.field_name, actual.field_name);
        try std.testing.expectEqual(expected.field_number, actual.field_number);
    }
}

fn parseProtoEnum(classification_proto: []const u8, comptime enum_name: []const u8) ![]const ProtoEnumEntry {
    const block = try findProtoBlock(classification_proto, "enum", enum_name);
    return try parseProtoEnumBlock(block);
}

fn parseProtoMessage(classification_proto: []const u8, comptime message_name: []const u8) ![]const ProtoField {
    const block = try findProtoBlock(classification_proto, "message", message_name);
    return try parseProtoMessageBlock(block);
}

fn findProtoBlock(classification_proto: []const u8, comptime kind: []const u8, comptime block_name: []const u8) ![]const u8 {
    const needle = comptime std.fmt.comptimePrint("{s} {s} {{", .{ kind, block_name });
    const start = std.mem.indexOf(u8, classification_proto, needle) orelse return error.MissingProtoBlock;
    const body_start = start + needle.len;
    const end_rel = std.mem.indexOf(u8, classification_proto[body_start..], "\n}") orelse
        return error.MalformedProtoBlock;
    return classification_proto[body_start .. body_start + end_rel];
}

fn parseProtoEnumBlock(block: []const u8) ![]const ProtoEnumEntry {
    var entries: [32]ProtoEnumEntry = undefined;
    var count: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, block, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (count >= entries.len) return error.TooManyProtoEntries;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.MalformedProtoEnumEntry;
        const semi_idx = std.mem.indexOfScalar(u8, line, ';') orelse return error.MalformedProtoEnumEntry;
        entries[count] = .{
            .name = std.mem.trim(u8, line[0..eq_idx], " \t"),
            .value = try std.fmt.parseInt(u32, std.mem.trim(u8, line[eq_idx + 1 .. semi_idx], " \t"), 10),
        };
        count += 1;
    }
    return entries[0..count];
}

fn parseProtoMessageBlock(block: []const u8) ![]const ProtoField {
    var fields: [16]ProtoField = undefined;
    var count: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, block, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (count >= fields.len) return error.TooManyProtoEntries;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return error.MalformedProtoField;
        const semi_idx = std.mem.indexOfScalar(u8, line, ';') orelse return error.MalformedProtoField;
        const left = std.mem.trim(u8, line[0..eq_idx], " \t");
        const last_space = std.mem.lastIndexOfScalar(u8, left, ' ') orelse return error.MalformedProtoField;
        fields[count] = .{
            .type_name = std.mem.trim(u8, left[0..last_space], " \t"),
            .field_name = std.mem.trim(u8, left[last_space + 1 ..], " \t"),
            .field_number = try std.fmt.parseInt(u32, std.mem.trim(u8, line[eq_idx + 1 .. semi_idx], " \t"), 10),
        };
        count += 1;
    }
    return fields[0..count];
}

fn upperSnake(comptime value: []const u8) [value.len]u8 {
    var out: [value.len]u8 = undefined;
    inline for (value, 0..) |byte, i| {
        out[i] = if (byte >= 'a' and byte <= 'z') byte - ('a' - 'A') else byte;
    }
    return out;
}

test "canonicalId validates lowercase underscore encoding" {
    const ok = try CanonicalId.init("ai_infrastructure");
    try std.testing.expectEqualStrings("ai_infrastructure", ok.slice());
    try std.testing.expectError(CanonicalIdError.InvalidEncoding, CanonicalId.init("AI"));
    try std.testing.expectError(CanonicalIdError.InvalidEncoding, CanonicalId.init("cash-like"));
}

test "assetClassList rejects duplicates" {
    var list = AssetClassList{};
    try list.append(.equity);
    try std.testing.expectError(AssetClassListError.DuplicateValue, list.append(.equity));
}

test "classificationRefList validates taxonomy version and uniqueness" {
    var list = ClassificationRefList{};
    const sector = try ClassificationRef.init("gics_sector", 2025, "information_technology");
    try list.append(sector);
    try std.testing.expectError(ClassificationRefError.DuplicateValue, list.append(sector));
    try std.testing.expectError(
        ClassificationRefError.MissingTaxonomyVersion,
        ClassificationRef.init("gics_sector", 0, "information_technology"),
    );
}

test "themeIdList rejects duplicate canonical ids" {
    var list = ThemeIdList{};
    try list.append(CanonicalId.init("ai_infrastructure") catch unreachable);
    try std.testing.expectError(
        ThemeIdListError.DuplicateValue,
        list.append(CanonicalId.init("ai_infrastructure") catch unreachable),
    );
}

test "classification proto enum contract stays aligned with zig definitions" {
    const classification_proto = try fixture_paths.readFixturePath(
        std.testing.allocator,
        std.testing.io,
        fixture_paths.classification_proto,
        32 * 1024,
    );
    defer std.testing.allocator.free(classification_proto);

    try expectProtoEnumMatchesZigEnum(classification_proto, Market, "Market", "MARKET_");
    try expectProtoEnumMatchesZigEnum(classification_proto, Venue, "Venue", "VENUE_");
    try expectProtoEnumMatchesZigEnum(classification_proto, AssetClass, "AssetClass", "ASSET_CLASS_");
    try expectProtoEnumMatchesZigEnum(classification_proto, InstrumentType, "InstrumentType", "INSTRUMENT_TYPE_");
    try expectProtoEnumMatchesZigEnum(classification_proto, RiskPreference, "RiskPreference", "RISK_PREFERENCE_");
}

test "classification proto message contract stays aligned with zig definitions" {
    const classification_proto = try fixture_paths.readFixturePath(
        std.testing.allocator,
        std.testing.io,
        fixture_paths.classification_proto,
        32 * 1024,
    );
    defer std.testing.allocator.free(classification_proto);

    try expectProtoMessageFields(classification_proto, "CanonicalId", &.{
        .{ .type_name = "string", .field_name = "value", .field_number = 1 },
    });
    try expectProtoMessageFields(classification_proto, "ClassificationRef", &.{
        .{ .type_name = "CanonicalId", .field_name = "taxonomy_id", .field_number = 1 },
        .{ .type_name = "uint32", .field_name = "taxonomy_version", .field_number = 2 },
        .{ .type_name = "CanonicalId", .field_name = "code", .field_number = 3 },
    });
    try expectProtoMessageFields(classification_proto, "AssetClassList", &.{
        .{ .type_name = "repeated AssetClass", .field_name = "values", .field_number = 1 },
    });
    try expectProtoMessageFields(classification_proto, "InstrumentTypeList", &.{
        .{ .type_name = "repeated InstrumentType", .field_name = "values", .field_number = 1 },
    });
    try expectProtoMessageFields(classification_proto, "ThemeIdList", &.{
        .{ .type_name = "repeated CanonicalId", .field_name = "values", .field_number = 1 },
    });
    try expectProtoMessageFields(classification_proto, "ClassificationRefList", &.{
        .{ .type_name = "repeated ClassificationRef", .field_name = "values", .field_number = 1 },
    });
}
