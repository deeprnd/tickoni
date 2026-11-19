/// Per-instance tkmodl configuration set.
///
/// Every configured `(tkmodl, kind_id)` process gets exactly one file,
/// `tkmodl.<kind_id>.config`, written by the supervisor before any child is
/// spawned and read only by that child. A file is, in order:
///
///   * a fixed header binding it to one process (`kind_id`), one semantic tier,
///     and the run's configured instance count, so a swapped, stale or missing
///     file fails closed instead of giving a model instance another instance's
///     governance (allowlist, limits, fixtures);
///   * the verbatim `TkModlRuntimeConfig`;
///   * the captured response bytes for its fixtures (`FixtureContent`), which
///     are replay material kept outside the audit record. Each capture must
///     hash to its fixture's `response_hash`, and the supervisor checks that
///     before any child exists.
///
/// This replaces the single shared `tkmodl.config`. The wire config itself is
/// unchanged and still lives in audit_schema.h.
const std = @import("std");
const rt = @import("runtime");
const c_abi = @import("c_abi");

const TkAgntModelTier = rt.model_tier.TkAgntModelTier;
pub const RuntimeConfig = c_abi.tkmodl.TkModlRuntimeConfig;

pub const header_magic: u32 = 0x544b4d49; // "TKMI"
pub const header_version: u16 = 2;

pub const Header = extern struct {
    magic: u32 = header_magic,
    version: u16 = header_version,
    /// The tkmodl instance (Firedancer kind_id) this file belongs to.
    kind_id: u8,
    /// Semantic tier of that instance (`TkAgntModelTier` ordinal).
    tier: u8,
    /// Number of tkmodl instances configured for this run. A file left over
    /// from a run with a different instance set disagrees with the topology.
    instance_cnt: u8,
    reserved: [7]u8 = std.mem.zeroes([7]u8),
};

/// Follows the config: how many captures, and their total byte length.
pub const ContentHeader = extern struct {
    count: u32,
    total_bytes: u32,
};

/// One capture's frame: key, length, then the bytes.
const entry_head_len: usize = 16;

comptime {
    std.debug.assert(@sizeOf(Header) == 16);
    std.debug.assert(@sizeOf(ContentHeader) == 8);
}

/// Length of a file with no captures.
pub const fixed_len: usize = @sizeOf(Header) + @sizeOf(RuntimeConfig) + @sizeOf(ContentHeader);

/// The captured response bytes for the fixture whose `key` is `key`.
pub const FixtureContent = struct {
    key: u64,
    bytes: []const u8,
};

pub const InstanceConfig = struct {
    kind_id: u8,
    tier: TkAgntModelTier,
    config: RuntimeConfig,
    contents: []const FixtureContent = &.{},
};

pub const ValidateError = error{
    TooManyModelInstances,
    DuplicateModelKindId,
    DuplicateModelTier,
    ModelConfigMissing,
    ModelConfigUnmatched,
    /// A capture names no configured fixture, or repeats a key.
    ModelContentUnmatched,
    /// A capture is empty or over a bound.
    ModelContentBound,
    /// A capture does not hash to its fixture's response_hash.
    ModelContentHashMismatch,
};

pub const ReadError = error{
    ConfigTruncated,
    ConfigTrailingBytes,
    ConfigBadHeaderMagic,
    ConfigBadHeaderVersion,
    ConfigUnknownTier,
    ConfigKindIdMismatch,
    ConfigInstanceCountMismatch,
    ConfigContentMalformed,
};

/// Number of tkmodl descriptors in a topology.
pub fn instanceCount(topo: rt.topology.Topology) usize {
    var n: usize = 0;
    for (topo.tiles) |t| {
        if (t.name.eql(rt.tile_ids.tkmodl)) n += 1;
    }
    return n;
}

/// One-to-one check between the topology's tkmodl descriptors and the
/// configured set, with unique kind ids and unique tiers, and every capture
/// bound to a fixture it hashes to. Runs before any workspace or child exists.
pub fn validate(configs: []const InstanceConfig, topo: rt.topology.Topology) ValidateError!void {
    if (instanceCount(topo) > rt.model_tier.max_model_instances) return error.TooManyModelInstances;
    if (configs.len > rt.model_tier.max_model_instances) return error.TooManyModelInstances;

    for (configs, 0..) |c, i| {
        for (configs[0..i]) |previous| {
            if (previous.kind_id == c.kind_id) return error.DuplicateModelKindId;
            if (previous.tier == c.tier) return error.DuplicateModelTier;
        }
    }
    for (topo.tiles) |t| {
        if (!t.name.eql(rt.tile_ids.tkmodl)) continue;
        if (findConfig(configs, t.kind_id) == null) return error.ModelConfigMissing;
    }
    for (configs) |c| {
        var matched = false;
        for (topo.tiles) |t| {
            if (t.name.eql(rt.tile_ids.tkmodl) and t.kind_id == c.kind_id) matched = true;
        }
        if (!matched) return error.ModelConfigUnmatched;
        try validateContents(c);
    }
}

fn validateContents(c: InstanceConfig) ValidateError!void {
    if (c.contents.len > c.config.fixture_count) return error.ModelContentUnmatched;
    var total: usize = 0;
    for (c.contents, 0..) |content, i| {
        for (c.contents[0..i]) |previous| {
            if (previous.key == content.key) return error.ModelContentUnmatched;
        }
        if (content.bytes.len == 0 or content.bytes.len > c_abi.tkmodl.content_max_bytes) return error.ModelContentBound;
        total += content.bytes.len;
        if (total > c_abi.tkmodl.content_store_bytes) return error.ModelContentBound;
        var fixture_hash: ?u64 = null;
        for (c.config.fixtures[0..c.config.fixture_count]) |f| {
            if (f.key != 0 and f.key == content.key) fixture_hash = f.response_hash;
        }
        const want = fixture_hash orelse return error.ModelContentUnmatched;
        if (c_abi.multipart.messageHash(content.bytes) != want) return error.ModelContentHashMismatch;
    }
}

fn findConfig(configs: []const InstanceConfig, kind_id: u8) ?*const InstanceConfig {
    for (configs) |*c| {
        if (c.kind_id == kind_id) return c;
    }
    return null;
}

/// Path of one instance's file: beside topology.spec in `run_dir`, or relative
/// to the directory handle when `run_dir` is empty (tests).
pub fn path(buf: []u8, run_dir: []const u8, kind_id: u8) std.fmt.BufPrintError![]const u8 {
    if (run_dir.len > 0) return std.fmt.bufPrint(buf, "{s}/tkmodl.{d}.config", .{ run_dir, kind_id });
    return std.fmt.bufPrint(buf, "tkmodl.{d}.config", .{kind_id});
}

/// The fixed part of a file: header, config, and the content header for
/// `c.contents`. A file with no captures is exactly this.
pub fn encode(c: InstanceConfig, instance_cnt: u8) [fixed_len]u8 {
    const header = Header{ .kind_id = c.kind_id, .tier = @backingInt(c.tier), .instance_cnt = instance_cnt };
    var total: u32 = 0;
    for (c.contents) |content| total += @intCast(content.bytes.len);
    const content_header = ContentHeader{ .count = @intCast(c.contents.len), .total_bytes = total };
    var bytes: [fixed_len]u8 = undefined;
    @memcpy(bytes[0..@sizeOf(Header)], std.mem.asBytes(&header));
    @memcpy(bytes[@sizeOf(Header)..][0..@sizeOf(RuntimeConfig)], std.mem.asBytes(&c.config));
    @memcpy(bytes[@sizeOf(Header) + @sizeOf(RuntimeConfig) ..], std.mem.asBytes(&content_header));
    return bytes;
}

/// Validates the set against the topology, then writes one file per instance.
/// Nothing is written if validation fails.
pub fn writeAll(
    io: std.Io,
    dir: std.Io.Dir,
    run_dir: []const u8,
    configs: []const InstanceConfig,
    topo: rt.topology.Topology,
) !void {
    try validate(configs, topo);
    const cnt: u8 = @intCast(configs.len);
    for (configs) |c| {
        var path_buf: [rt.launch_spec.shmem_path_cap + 32]u8 = undefined;
        const file_path = try path(&path_buf, run_dir, c.kind_id);
        // The file holds captured responses (replay material): owner access only.
        var file = try rt.file_io.createOwnerOnlyFile(io, dir, file_path);
        defer file.close(io);
        const fixed = encode(c, cnt);
        try file.writePositionalAll(io, &fixed, 0);
        var off: u64 = fixed.len;
        for (c.contents) |content| {
            var head: [entry_head_len]u8 = std.mem.zeroes([entry_head_len]u8);
            std.mem.writeInt(u64, head[0..8], content.key, .little);
            std.mem.writeInt(u32, head[8..12], @intCast(content.bytes.len), .little);
            try file.writePositionalAll(io, &head, off);
            off += head.len;
            try file.writePositionalAll(io, content.bytes, off);
            off += content.bytes.len;
        }
    }
}

/// The semantic tier a file binds its instance to, after the same identity
/// checks `read` makes, without loading the config or captures. tkagnt uses it
/// to learn which tkmodl instance serves which tier.
pub fn readTier(
    io: std.Io,
    dir: std.Io.Dir,
    file_path: []const u8,
    expect_kind_id: u8,
    expect_instance_cnt: usize,
) !TkAgntModelTier {
    var file = try rt.file_io.openFile(io, dir, file_path);
    defer file.close(io);
    var header: Header = undefined;
    const n = try file.readPositionalAll(io, std.mem.asBytes(&header), 0);
    if (n != @sizeOf(Header)) return error.ConfigTruncated;
    if (header.magic != header_magic) return error.ConfigBadHeaderMagic;
    if (header.version != header_version) return error.ConfigBadHeaderVersion;
    const tier = TkAgntModelTier.fromInt(header.tier) orelse return error.ConfigUnknownTier;
    if (header.kind_id != expect_kind_id) return error.ConfigKindIdMismatch;
    if (header.instance_cnt != expect_instance_cnt) return error.ConfigInstanceCountMismatch;
    return tier;
}

/// A file read back: the config, and the captures as slices of one owned blob.
pub const Loaded = struct {
    kind_id: u8,
    tier: TkAgntModelTier,
    config: RuntimeConfig,
    contents: []FixtureContent,
    blob: []u8,

    pub fn deinit(self: *Loaded, allocator: std.mem.Allocator) void {
        allocator.free(self.contents);
        allocator.free(self.blob);
        self.* = undefined;
    }
};

/// Reads and checks one instance's file against the identity this child was
/// launched as and the run's instance count. Does not install anything.
pub fn read(
    io: std.Io,
    dir: std.Io.Dir,
    file_path: []const u8,
    expect_kind_id: u8,
    expect_instance_cnt: usize,
    allocator: std.mem.Allocator,
) !Loaded {
    var file = try rt.file_io.openFile(io, dir, file_path);
    defer file.close(io);

    var fixed: [fixed_len]u8 = undefined;
    const n = try file.readPositionalAll(io, &fixed, 0);
    if (n != fixed.len) return error.ConfigTruncated;

    var header: Header = undefined;
    @memcpy(std.mem.asBytes(&header), fixed[0..@sizeOf(Header)]);
    if (header.magic != header_magic) return error.ConfigBadHeaderMagic;
    if (header.version != header_version) return error.ConfigBadHeaderVersion;
    const tier = TkAgntModelTier.fromInt(header.tier) orelse return error.ConfigUnknownTier;
    if (header.kind_id != expect_kind_id) return error.ConfigKindIdMismatch;
    if (header.instance_cnt != expect_instance_cnt) return error.ConfigInstanceCountMismatch;

    var cfg: RuntimeConfig = undefined;
    @memcpy(std.mem.asBytes(&cfg), fixed[@sizeOf(Header)..][0..@sizeOf(RuntimeConfig)]);
    var content_header: ContentHeader = undefined;
    @memcpy(std.mem.asBytes(&content_header), fixed[@sizeOf(Header) + @sizeOf(RuntimeConfig) ..]);

    // Bound the capture section before allocating for it.
    if (content_header.count > c_abi.tkmodl.fixture_cap or
        content_header.total_bytes > c_abi.tkmodl.content_store_bytes) return error.ConfigContentMalformed;
    const section_len: usize = content_header.total_bytes + @as(usize, content_header.count) * entry_head_len;

    const blob = try allocator.alloc(u8, section_len);
    errdefer allocator.free(blob);
    if ((try file.readPositionalAll(io, blob, fixed_len)) != section_len) return error.ConfigTruncated;
    var extra: [1]u8 = undefined;
    if ((try file.readPositionalAll(io, &extra, fixed_len + section_len)) != 0) return error.ConfigTrailingBytes;

    const contents = try allocator.alloc(FixtureContent, content_header.count);
    errdefer allocator.free(contents);
    var off: usize = 0;
    var seen: usize = 0;
    for (contents) |*c| {
        if (off + entry_head_len > blob.len) return error.ConfigContentMalformed;
        const key = std.mem.readInt(u64, blob[off..][0..8], .little);
        const len: usize = std.mem.readInt(u32, blob[off + 8 ..][0..4], .little);
        off += entry_head_len;
        if (len == 0 or off + len > blob.len) return error.ConfigContentMalformed;
        c.* = .{ .key = key, .bytes = blob[off .. off + len] };
        off += len;
        seen += len;
    }
    if (off != blob.len or seen != content_header.total_bytes) return error.ConfigContentMalformed;

    return .{ .kind_id = header.kind_id, .tier = tier, .config = cfg, .contents = contents, .blob = blob };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn testConfig(model_id: []const u8) RuntimeConfig {
    var cfg = std.mem.zeroes(RuntimeConfig);
    cfg.magic = c_abi.tkmodl.config_magic;
    cfg.version = c_abi.tkmodl.config_version;
    cfg.allowed_model_count = 1;
    @memcpy(cfg.allowed_model_ids[0][0..model_id.len], model_id);
    return cfg;
}

/// A config whose one fixture (key 7) is the capture `bytes`.
fn configWithCapture(model_id: []const u8, bytes: []const u8) RuntimeConfig {
    var cfg = testConfig(model_id);
    cfg.fixture_count = 1;
    cfg.fixtures[0].key = 7;
    cfg.fixtures[0].response_hash = c_abi.multipart.messageHash(bytes);
    @memcpy(cfg.fixtures[0].model_id[0..model_id.len], model_id);
    return cfg;
}

const two_model_tiles = [_]rt.tile.TileDescriptor{
    .{ .id = 0, .name = rt.tile_ids.tkagnt },
    .{ .id = 1, .name = rt.tile_ids.tkmodl, .kind_id = 0 },
    .{ .id = 2, .name = rt.tile_ids.tkmodl, .kind_id = 1 },
};
const two_model_topo = rt.topology.Topology{ .tiles = &two_model_tiles, .channels = &.{} };

fn twoConfigs() [2]InstanceConfig {
    return .{
        .{ .kind_id = 0, .tier = .classifier_fast, .config = testConfig("cls-fast") },
        .{ .kind_id = 1, .tier = .embedding, .config = testConfig("embed") },
    };
}

test "validate accepts a sparse tier selection mapped one-to-one onto instances" {
    // Two of the eleven tiers: instances are compact (0, 1) while the tiers
    // are not adjacent in the tier list.
    const configs = twoConfigs();
    try validate(&configs, two_model_topo);
}

test "validate accepts a topology with no tkmodl and no configs" {
    const tiles = [_]rt.tile.TileDescriptor{.{ .id = 0, .name = rt.tile_ids.tkings }};
    try validate(&.{}, .{ .tiles = &tiles, .channels = &.{} });
}

test "validate rejects a missing per-instance config" {
    const configs = twoConfigs();
    try std.testing.expectError(error.ModelConfigMissing, validate(configs[0..1], two_model_topo));
    try std.testing.expectError(error.ModelConfigMissing, validate(&.{}, two_model_topo));
}

test "validate rejects a config for an instance the topology does not have" {
    // Both real instances are configured; the third entry names kind 2.
    const two = twoConfigs();
    const configs = [_]InstanceConfig{
        two[0],
        two[1],
        .{ .kind_id = 2, .tier = .low, .config = testConfig("low") },
    };
    try std.testing.expectError(error.ModelConfigUnmatched, validate(&configs, two_model_topo));
}

test "validate reports a missing instance before an unmatched one" {
    // Instance 1 has no entry and entry kind 2 has no instance: the missing
    // process is the more serious fault, since it would start ungoverned.
    var configs = twoConfigs();
    configs[1].kind_id = 2;
    try std.testing.expectError(error.ModelConfigMissing, validate(&configs, two_model_topo));
}

test "validate rejects duplicate kind ids and duplicate tiers" {
    var configs = twoConfigs();
    configs[1].kind_id = 0;
    try std.testing.expectError(error.DuplicateModelKindId, validate(&configs, two_model_topo));

    configs = twoConfigs();
    configs[1].tier = .classifier_fast;
    try std.testing.expectError(error.DuplicateModelTier, validate(&configs, two_model_topo));
}

test "validate rejects more instances than the supported maximum" {
    var tiles: [rt.model_tier.max_model_instances + 1]rt.tile.TileDescriptor = undefined;
    for (&tiles, 0..) |*t, i| t.* = .{ .id = i, .name = rt.tile_ids.tkmodl, .kind_id = @intCast(i) };
    try std.testing.expectError(error.TooManyModelInstances, validate(&.{}, .{ .tiles = &tiles, .channels = &.{} }));
}

test "validate accepts a capture that hashes to its fixture" {
    const bytes = "the captured response";
    var configs = twoConfigs();
    configs[0].config = configWithCapture("cls-fast", bytes);
    configs[0].contents = &.{.{ .key = 7, .bytes = bytes }};
    try validate(&configs, two_model_topo);
}

test "validate rejects a capture that is wrong, unmatched, duplicated, or out of bounds" {
    const bytes = "the captured response";
    var configs = twoConfigs();
    configs[0].config = configWithCapture("cls-fast", bytes);

    // Bytes that do not hash to the fixture's response_hash.
    configs[0].contents = &.{.{ .key = 7, .bytes = "tampered response!!!!" }};
    try std.testing.expectError(error.ModelContentHashMismatch, validate(&configs, two_model_topo));

    // A capture for a key no fixture has.
    configs[0].contents = &.{.{ .key = 99, .bytes = bytes }};
    try std.testing.expectError(error.ModelContentUnmatched, validate(&configs, two_model_topo));

    // The same key twice.
    configs[0].contents = &.{ .{ .key = 7, .bytes = bytes }, .{ .key = 7, .bytes = bytes } };
    try std.testing.expectError(error.ModelContentUnmatched, validate(&configs, two_model_topo));

    // Empty.
    configs[0].contents = &.{.{ .key = 7, .bytes = "" }};
    try std.testing.expectError(error.ModelContentBound, validate(&configs, two_model_topo));
}

test "writeAll then read round-trips each instance's tier, config and captures" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = "the captured response";
    var configs = twoConfigs();
    configs[0].config = configWithCapture("cls-fast", bytes);
    configs[0].contents = &.{.{ .key = 7, .bytes = bytes }};
    try writeAll(std.testing.io, tmp.dir, "", &configs, two_model_topo);

    var buf: [64]u8 = undefined;
    for (configs) |want| {
        var got = try read(std.testing.io, tmp.dir, try path(&buf, "", want.kind_id), want.kind_id, 2, std.testing.allocator);
        defer got.deinit(std.testing.allocator);
        try std.testing.expectEqual(want.kind_id, got.kind_id);
        try std.testing.expectEqual(want.tier, got.tier);
        try std.testing.expectEqualSlices(u8, std.mem.asBytes(&want.config), std.mem.asBytes(&got.config));
        try std.testing.expectEqual(want.contents.len, got.contents.len);
        for (want.contents, got.contents) |w, g| {
            try std.testing.expectEqual(w.key, g.key);
            try std.testing.expectEqualSlices(u8, w.bytes, g.bytes);
        }
    }
}

test "writeAll leaves each instance file readable and writable by its owner only" {
    if (!@hasDecl(std.Io.File.Permissions, "toMode")) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = "the captured response";
    var configs = twoConfigs();
    configs[0].config = configWithCapture("cls-fast", bytes);
    configs[0].contents = &.{.{ .key = 7, .bytes = bytes }};
    try writeAll(std.testing.io, tmp.dir, "", &configs, two_model_topo);

    var buf: [64]u8 = undefined;
    for (configs) |c| {
        var file = try tmp.dir.openFile(std.testing.io, try path(&buf, "", c.kind_id), .{});
        defer file.close(std.testing.io);
        const stat = try file.stat(std.testing.io);
        try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
    }
}

test "a capture larger than one fragment survives the file round trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const big = try std.testing.allocator.alloc(u8, 100_000);
    defer std.testing.allocator.free(big);
    for (big, 0..) |*b, i| b.* = @truncate(i *% 31);
    var configs = twoConfigs();
    configs[0].config = configWithCapture("cls-fast", big);
    configs[0].contents = &.{.{ .key = 7, .bytes = big }};
    try writeAll(std.testing.io, tmp.dir, "", &configs, two_model_topo);

    var buf: [64]u8 = undefined;
    var got = try read(std.testing.io, tmp.dir, try path(&buf, "", 0), 0, 2, std.testing.allocator);
    defer got.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, big, got.contents[0].bytes);
}

test "writeAll writes nothing when validation fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const configs = twoConfigs();
    try std.testing.expectError(error.ModelConfigMissing, writeAll(std.testing.io, tmp.dir, "", configs[0..1], two_model_topo));
    var buf: [64]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, rt.file_io.openFile(std.testing.io, tmp.dir, try path(&buf, "", 0)));
}

test "read fails on a missing file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(error.FileNotFound, read(std.testing.io, tmp.dir, "tkmodl.1.config", 1, 2, std.testing.allocator));
}

test "readTier returns the bound tier and applies the same identity checks" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const configs = twoConfigs();
    try writeAll(std.testing.io, tmp.dir, "", &configs, two_model_topo);
    var buf: [64]u8 = undefined;
    for (configs) |c| {
        const tier = try readTier(std.testing.io, tmp.dir, try path(&buf, "", c.kind_id), c.kind_id, 2);
        try std.testing.expectEqual(c.tier, tier);
    }
    try std.testing.expectError(error.ConfigKindIdMismatch, readTier(std.testing.io, tmp.dir, "tkmodl.0.config", 1, 2));
    try std.testing.expectError(error.ConfigInstanceCountMismatch, readTier(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 3));
    try std.testing.expectError(error.FileNotFound, readTier(std.testing.io, tmp.dir, "tkmodl.9.config", 9, 2));
}

test "read rejects a config swapped between instances" {
    // Instance 0's bytes saved under instance 1's name: loading would run
    // instance 1 with instance 0's allowlist and tier.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const configs = twoConfigs();
    const bytes = encode(configs[0], 2);
    var file = try tmp.dir.createFile(std.testing.io, "tkmodl.1.config", .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &bytes, 0);
    try std.testing.expectError(error.ConfigKindIdMismatch, read(std.testing.io, tmp.dir, "tkmodl.1.config", 1, 2, std.testing.allocator));
}

test "read rejects a stale file from a run with a different instance count" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const configs = twoConfigs();
    const bytes = encode(configs[0], 3);
    var file = try tmp.dir.createFile(std.testing.io, "tkmodl.0.config", .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &bytes, 0);
    try std.testing.expectError(error.ConfigInstanceCountMismatch, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, std.testing.allocator));
}

test "read rejects truncated, over-long, mis-magic'd, mis-versioned, unknown-tier and malformed-capture files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const configs = twoConfigs();
    const good = encode(configs[0], 2);
    const alloc = std.testing.allocator;

    try writeRaw(&tmp, good[0 .. good.len - 1]);
    try std.testing.expectError(error.ConfigTruncated, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    var long: [fixed_len + 1]u8 = undefined;
    @memcpy(long[0..fixed_len], &good);
    long[fixed_len] = 0;
    try writeRaw(&tmp, &long);
    try std.testing.expectError(error.ConfigTrailingBytes, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    var bad = good;
    bad[0] ^= 0xff;
    try writeRaw(&tmp, &bad);
    try std.testing.expectError(error.ConfigBadHeaderMagic, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    bad = good;
    bad[4] +%= 1;
    try writeRaw(&tmp, &bad);
    try std.testing.expectError(error.ConfigBadHeaderVersion, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    bad = good;
    bad[7] = 200; // tier byte
    try writeRaw(&tmp, &bad);
    try std.testing.expectError(error.ConfigUnknownTier, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    // A content header that claims more captures than the fixture table holds.
    bad = good;
    const content_off = @sizeOf(Header) + @sizeOf(RuntimeConfig);
    std.mem.writeInt(u32, bad[content_off..][0..4], @intCast(c_abi.tkmodl.fixture_cap + 1), .little);
    try writeRaw(&tmp, &bad);
    try std.testing.expectError(error.ConfigContentMalformed, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));

    // Claims one capture of 8 bytes but the file ends after the header.
    bad = good;
    std.mem.writeInt(u32, bad[content_off..][0..4], 1, .little);
    std.mem.writeInt(u32, bad[content_off + 4 ..][0..4], 8, .little);
    try writeRaw(&tmp, &bad);
    try std.testing.expectError(error.ConfigTruncated, read(std.testing.io, tmp.dir, "tkmodl.0.config", 0, 2, alloc));
}

fn writeRaw(tmp: anytype, bytes: []const u8) !void {
    var file = try tmp.dir.createFile(std.testing.io, "tkmodl.0.config", .{});
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, bytes, 0);
}
