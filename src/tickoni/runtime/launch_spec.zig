/// Versioned handoff record from the v2.14 process-mode supervisor to a
/// self-exec'd tile child process. Written once by the supervisor before
/// spawning the child and read exactly once by src/app/tickoni/tile_main.zig.
///
/// This is not a durable or cross-version wire format: writer and reader are
/// always the same build of the same binary (self-exec), so a plain
/// fixed-size struct round-tripped through std.mem.asBytes is sufficient.
/// The magic/version/length checks below exist to fail closed on a stray,
/// truncated, or foreign file rather than to support format evolution.
///
/// v2.14.S8.T2: link fields are bounded per-tile arrays (in_links/out_links),
/// not a single input/output pair — a topology where a tile has more than
/// one inbound or outbound channel is representable here without losing any
/// of them. `tile-orchestration.md` documents the eventual target shape as
/// `in_link_id[]`/`out_link_id[]` — integer ids into a shared topology link
/// table read from shmem at tile boot (the real Firedancer
/// `fd_topo_tile_t` shape). That indirection does not exist yet; these
/// arrays instead carry already-resolved `LinkHandles` (mcache/dcache/fseq
/// gaddrs), same as the single-link fields they replace. Payment-pipeline
/// test config (event_count/policy_limit_cents/inject_duplicate/
/// inject_malformed) is intentionally not a field here — this record stays
/// generic bootstrap data (identity, CPU placement, workspace, cnc address,
/// links, heartbeat); see tiles/payment_pipeline/process.zig's
/// writeProcessConfig/readProcessConfig for where that lives instead.
const std = @import("std");
const tile = @import("tile.zig");
const cpu_placement = @import("cpu_placement.zig");
const link = @import("link.zig");

pub const magic: u32 = 0x544b5350; // "TKSP"
pub const version: u16 = 1;

pub const shmem_path_cap: usize = 128;

/// Phase 0 needs at most 2 inbound links for any one tile (e.g. an audit
/// tile fed by both an ingest path and a policy path); 4 leaves headroom
/// without an unbounded/heap-allocated array in a struct that gets
/// round-tripped through raw bytes.
pub const max_links_per_tile: usize = 4;

pub const LaunchSpec = struct {
    magic_field: u32 = magic,
    version_field: u16 = version,
    tile_idx: u32,
    tile_id: tile.TileId,
    cpu_placement: cpu_placement.CpuPlacement,
    workspace_name: link.WorkspaceName,
    /// Global address of this tile's pre-formatted cnc object inside
    /// workspace_name, as returned by fd_wksp_gaddr in the supervisor.
    cnc_gaddr: usize,
    /// Zero (in_cnt/out_cnt == 0) when this tile has no upstream/downstream
    /// correctness link, e.g. tkings has no input and tkaudt has no output
    /// in the current 5-stage core chain.
    in_cnt: u8 = 0,
    in_links: [max_links_per_tile]link.LinkHandles = std.mem.zeroes([max_links_per_tile]link.LinkHandles),
    out_cnt: u8 = 0,
    out_links: [max_links_per_tile]link.LinkHandles = std.mem.zeroes([max_links_per_tile]link.LinkHandles),
    shmem_path_buf: [shmem_path_cap]u8 = std.mem.zeroes([shmem_path_cap]u8),
    shmem_path_len: u16,
    heartbeat_interval_ns: u64,
    /// Test-only hook (v2.14.S1.T12 crash isolation): if > 0, the tile
    /// self-exits(1) after this many heartbeats instead of waiting for
    /// SIGTERM. 0 means run normally until signaled.
    crash_after_heartbeats: u32,

    pub fn init(fields: struct {
        tile_idx: u32,
        tile_id: tile.TileId,
        cpu_placement: cpu_placement.CpuPlacement,
        workspace_name: link.WorkspaceName,
        cnc_gaddr: usize,
        shmem_path: []const u8,
        heartbeat_interval_ns: u64,
        crash_after_heartbeats: u32 = 0,
        /// Topology channels and their resolved shared-memory handles
        /// (parallel arrays, same index in both). Bucketed here into
        /// in_links/out_links by matching tile_idx against each channel's
        /// dst_idx/src_idx — every matching channel is kept, not just the
        /// last one.
        channels: []const link.Channel = &.{},
        link_handles: []const link.LinkHandles = &.{},
    }) error{ ShmemPathTooLong, TooManyInLinks, TooManyOutLinks }!LaunchSpec {
        if (fields.shmem_path.len > shmem_path_cap) return error.ShmemPathTooLong;
        var spec = LaunchSpec{
            .tile_idx = fields.tile_idx,
            .tile_id = fields.tile_id,
            .cpu_placement = fields.cpu_placement,
            .workspace_name = fields.workspace_name,
            .cnc_gaddr = fields.cnc_gaddr,
            .shmem_path_len = @intCast(fields.shmem_path.len),
            .heartbeat_interval_ns = fields.heartbeat_interval_ns,
            .crash_after_heartbeats = fields.crash_after_heartbeats,
        };
        @memcpy(spec.shmem_path_buf[0..fields.shmem_path.len], fields.shmem_path);
        for (fields.channels, fields.link_handles) |ch, lh| {
            if (ch.dst_idx == fields.tile_idx) {
                if (spec.in_cnt >= max_links_per_tile) return error.TooManyInLinks;
                spec.in_links[spec.in_cnt] = lh;
                spec.in_cnt += 1;
            }
            if (ch.src_idx == fields.tile_idx) {
                if (spec.out_cnt >= max_links_per_tile) return error.TooManyOutLinks;
                spec.out_links[spec.out_cnt] = lh;
                spec.out_cnt += 1;
            }
        }
        return spec;
    }

    pub fn inLinks(self: *const LaunchSpec) []const link.LinkHandles {
        return self.in_links[0..self.in_cnt];
    }

    pub fn outLinks(self: *const LaunchSpec) []const link.LinkHandles {
        return self.out_links[0..self.out_cnt];
    }

    pub fn shmemPath(self: *const LaunchSpec) []const u8 {
        return self.shmem_path_buf[0..self.shmem_path_len];
    }

    pub fn writeToFile(self: *const LaunchSpec, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
        var file = try dir.createFile(io, sub_path, .{});
        defer file.close(io);
        try file.writePositionalAll(io, std.mem.asBytes(self), 0);
    }

    pub fn readFromFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !LaunchSpec {
        var file = try dir.openFile(io, sub_path, .{});
        defer file.close(io);
        var spec: LaunchSpec = undefined;
        const buf = std.mem.asBytes(&spec);
        const n = try file.readPositionalAll(io, buf, 0);
        if (n != @sizeOf(LaunchSpec)) return error.LaunchSpecTruncated;
        if (spec.magic_field != magic) return error.LaunchSpecBadMagic;
        if (spec.version_field != version) return error.LaunchSpecUnsupportedVersion;
        if (spec.shmem_path_len > shmem_path_cap) return error.LaunchSpecMalformed;
        return spec;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "LaunchSpec round-trips through a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const spec = try LaunchSpec.init(.{
        .tile_idx = 3,
        .tile_id = try tile.TileId.parse("tkpoly"),
        .cpu_placement = .{ .exclusive = 2 },
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 4096,
        .shmem_path = "/tmp/tickoni-run",
        .heartbeat_interval_ns = 50_000_000,
        .crash_after_heartbeats = 7,
    });
    try spec.writeToFile(std.testing.io, tmp.dir, "tile.spec");

    const read_back = try LaunchSpec.readFromFile(std.testing.io, tmp.dir, "tile.spec");
    try std.testing.expectEqual(@as(u32, 3), read_back.tile_idx);
    try std.testing.expectEqualStrings("tkpoly", read_back.tile_id.slice());
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .exclusive = 2 }, read_back.cpu_placement);
    try std.testing.expectEqualStrings("tkpay0", read_back.workspace_name.slice());
    try std.testing.expectEqual(@as(usize, 4096), read_back.cnc_gaddr);
    try std.testing.expectEqualStrings("/tmp/tickoni-run", read_back.shmemPath());
    try std.testing.expectEqual(@as(u64, 50_000_000), read_back.heartbeat_interval_ns);
    try std.testing.expectEqual(@as(u32, 7), read_back.crash_after_heartbeats);
    try std.testing.expectEqual(@as(u8, 0), read_back.in_cnt);
    try std.testing.expectEqual(@as(u8, 0), read_back.out_cnt);
}

test "LaunchSpec readFromFile rejects a truncated file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(std.testing.io, "short.spec", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.LaunchSpecTruncated, LaunchSpec.readFromFile(std.testing.io, tmp.dir, "short.spec"));
}

test "LaunchSpec readFromFile rejects a bad magic" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var spec = try LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = try tile.TileId.parse("tkings"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "/tmp",
        .heartbeat_interval_ns = 1,
    });
    spec.magic_field = 0xdeadbeef;
    try spec.writeToFile(std.testing.io, tmp.dir, "bad_magic.spec");

    try std.testing.expectError(error.LaunchSpecBadMagic, LaunchSpec.readFromFile(std.testing.io, tmp.dir, "bad_magic.spec"));
}

test "LaunchSpec init rejects an over-long shmem path" {
    var too_long: [shmem_path_cap + 1]u8 = undefined;
    for (&too_long) |*c| c.* = 'a';
    try std.testing.expectError(error.ShmemPathTooLong, LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = try tile.TileId.parse("tkings"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = &too_long,
        .heartbeat_interval_ns = 1,
    }));
}

test "LaunchSpec init keeps every matching inbound channel, not just the last (fan-in)" {
    const channels = [_]link.Channel{
        .{ .src_idx = 0, .dst_idx = 2, .depth = 64, .mtu = 128 },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128 },
    };
    const handles = [_]link.LinkHandles{
        .{ .mcache_gaddr = 111, .dcache_gaddr = 0, .fseq_gaddr = 0, .depth = 64, .mtu = 128 },
        .{ .mcache_gaddr = 222, .dcache_gaddr = 0, .fseq_gaddr = 0, .depth = 64, .mtu = 128 },
    };

    const spec = try LaunchSpec.init(.{
        .tile_idx = 2,
        .tile_id = try tile.TileId.parse("tkaudt"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "/tmp",
        .heartbeat_interval_ns = 1,
        .channels = &channels,
        .link_handles = &handles,
    });

    try std.testing.expectEqual(@as(u8, 2), spec.in_cnt);
    try std.testing.expectEqual(@as(usize, 111), spec.inLinks()[0].mcache_gaddr);
    try std.testing.expectEqual(@as(usize, 222), spec.inLinks()[1].mcache_gaddr);
    try std.testing.expectEqual(@as(u8, 0), spec.out_cnt);
}

test "LaunchSpec init keeps every matching outbound channel (fan-out)" {
    const channels = [_]link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 },
        .{ .src_idx = 0, .dst_idx = 2, .depth = 64, .mtu = 128 },
    };
    const handles = [_]link.LinkHandles{
        .{ .mcache_gaddr = 333, .dcache_gaddr = 0, .fseq_gaddr = 0, .depth = 64, .mtu = 128 },
        .{ .mcache_gaddr = 444, .dcache_gaddr = 0, .fseq_gaddr = 0, .depth = 64, .mtu = 128 },
    };

    const spec = try LaunchSpec.init(.{
        .tile_idx = 0,
        .tile_id = try tile.TileId.parse("tkings"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "/tmp",
        .heartbeat_interval_ns = 1,
        .channels = &channels,
        .link_handles = &handles,
    });

    try std.testing.expectEqual(@as(u8, 2), spec.out_cnt);
    try std.testing.expectEqual(@as(usize, 333), spec.outLinks()[0].mcache_gaddr);
    try std.testing.expectEqual(@as(usize, 444), spec.outLinks()[1].mcache_gaddr);
    try std.testing.expectEqual(@as(u8, 0), spec.in_cnt);
}

test "LaunchSpec init fails closed when inbound links exceed max_links_per_tile" {
    var channels: [max_links_per_tile + 1]link.Channel = undefined;
    var handles: [max_links_per_tile + 1]link.LinkHandles = undefined;
    for (&channels, &handles, 0..) |*ch, *lh, i| {
        ch.* = .{ .src_idx = @intCast(i + 10), .dst_idx = 5, .depth = 64, .mtu = 128 };
        lh.* = .{ .mcache_gaddr = i + 1, .dcache_gaddr = 0, .fseq_gaddr = 0, .depth = 64, .mtu = 128 };
    }

    try std.testing.expectError(error.TooManyInLinks, LaunchSpec.init(.{
        .tile_idx = 5,
        .tile_id = try tile.TileId.parse("tkaudt"),
        .cpu_placement = .floating,
        .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        .cnc_gaddr = 0,
        .shmem_path = "/tmp",
        .heartbeat_interval_ns = 1,
        .channels = &channels,
        .link_handles = &handles,
    }));
}
