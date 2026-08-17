/// v2.14.S8.T4: small serialized description of Topology (tiles + channels
/// only — no Firedancer types, nowhere near the ~40-80KB fd_topo_t),
/// written once by the supervisor and read by every self-exec'd child
/// before it calls topo_build.build() to rebuild an identical topology
/// (see topo_build.zig's module doc, "topology handoff" finding).
///
/// This is NOT a contradiction of that finding's "rebuild, don't
/// serialize fd_topo_t" resolution — it's serializing Tickoni's own small
/// description as the deterministic *input* to the rebuild, since a child
/// has no other way to know which topology variant (e.g. which CPU
/// placement a given test configured) the parent actually used. Same
/// magic/version/fail-closed round-trip idiom as LaunchSpec and
/// ProcessConfig.
const std = @import("std");
const tile = @import("tile.zig");
const cpu_placement = @import("cpu_placement.zig");
const link = @import("link.zig");
const topology = @import("topology.zig");

pub const magic: u32 = 0x544b5453; // "TKST"
pub const version: u16 = 1;

pub const max_tiles: usize = 8;
pub const max_channels: usize = 8;

pub const TopologySpec = struct {
    magic_field: u32 = magic,
    version_field: u16 = version,
    tile_cnt: u8,
    tile_id: [max_tiles]tile.TileId = std.mem.zeroes([max_tiles]tile.TileId),
    tile_cpu_placement: [max_tiles]cpu_placement.CpuPlacement = blk: {
        var buf: [max_tiles]cpu_placement.CpuPlacement = undefined;
        var i: usize = 0;
        while (i < buf.len) : (i += 1) buf[i] = .floating;
        break :blk buf;
    },
    channel_cnt: u8,
    channel_src_idx: [max_channels]u32 = std.mem.zeroes([max_channels]u32),
    channel_dst_idx: [max_channels]u32 = std.mem.zeroes([max_channels]u32),
    channel_depth: [max_channels]u32 = std.mem.zeroes([max_channels]u32),
    channel_mtu: [max_channels]u32 = std.mem.zeroes([max_channels]u32),
    workspace_name: link.WorkspaceName = .{},

    pub fn fromTopology(topo: topology.Topology) error{ TooManyTiles, TooManyChannels, MissingWorkspaceName }!TopologySpec { if (topo.tiles.len > max_tiles) return error.TooManyTiles;
        if (topo.channels.len > max_channels) return error.TooManyChannels;

        var spec = TopologySpec{
            .tile_cnt = @intCast(topo.tiles.len),
            .channel_cnt = @intCast(topo.channels.len), };
        for (topo.tiles, 0..) |t, i| { spec.tile_id[i] = t.id;
            spec.tile_cpu_placement[i] = t.cpu_placement; }
        for (topo.channels, 0..) |ch, i| { spec.channel_src_idx[i] = ch.src_idx;
            spec.channel_dst_idx[i] = ch.dst_idx;
            spec.channel_depth[i] = ch.depth;
            spec.channel_mtu[i] = ch.mtu;
            if (i == 0) {
                if (ch.workspace_name.isEmpty()) return error.MissingWorkspaceName;
                spec.workspace_name = ch.workspace_name; }
        }
        return spec;
    }

    /// Writes into caller-provided fixed buffers (no allocation).
    /// TileDescriptor.name is diagnostics-only and not part of the wire
    /// format — reconstructed here as the same string as id.slice().
    pub fn toTopology(self: *const TopologySpec, tiles_buf: []tile.TileDescriptor, channels_buf: []link.Channel) topology.Topology { std.debug.assert(tiles_buf.len >= self.tile_cnt);
        std.debug.assert(channels_buf.len >= self.channel_cnt);
        for (0..self.tile_cnt) |i| {
            tiles_buf[i] = .{
                .id = self.tile_id[i],
                .name = self.tile_id[i].slice(),
                .cpu_placement = self.tile_cpu_placement[i], };
        }
        for (0..self.channel_cnt) |i| { channels_buf[i] = .{
                .src_idx = self.channel_src_idx[i],
                .dst_idx = self.channel_dst_idx[i],
                .depth = self.channel_depth[i],
                .mtu = self.channel_mtu[i],
                .backing = .tango_shm,
                .workspace_name = self.workspace_name, };
        }
        return .{ .tiles = tiles_buf[0..self.tile_cnt], .channels = channels_buf[0..self.channel_cnt] };
    }

    pub fn writeToFile(self: *const TopologySpec, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
        var file = try dir.createFile(io, sub_path, .{});
        defer file.close(io);
        try file.writePositionalAll(io, std.mem.asBytes(self), 0);
    }

    pub fn readFromFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !TopologySpec {
        var file = try dir.openFile(io, sub_path, .{});
        defer file.close(io);
        var spec: TopologySpec = undefined;
        const buf = std.mem.asBytes(&spec);
        const n = try file.readPositionalAll(io, buf, 0);
        if (n != @sizeOf(TopologySpec)) return error.TopologySpecTruncated;
        if (spec.magic_field != magic) return error.TopologySpecBadMagic;
        if (spec.version_field != version) return error.TopologySpecUnsupportedVersion;
        if (spec.tile_cnt > max_tiles or spec.channel_cnt > max_channels) return error.TopologySpecMalformed;
        return spec;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TopologySpec round-trips through a file for the linear Phase 0 chain" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tiles = [_]tile.TileDescriptor{ .{ .id = try tile.TileId.parse("tkings"), .name = "tkings", .cpu_placement = .{ .exclusive = 0 } },
        .{ .id = try tile.TileId.parse("tknorm"), .name = "tknorm", .cpu_placement = .{ .shared = 1 } },
        .{ .id = try tile.TileId.parse("tkdedu"), .name = "tkdedu" },
    };
    const channels = [_]link.Channel{ .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = try link.WorkspaceName.parse("tkpay0") },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = try link.WorkspaceName.parse("tkpay0") },
    };
    const topo = topology.Topology{ .tiles = &tiles, .channels = &channels };

    const spec = try TopologySpec.fromTopology(topo);
    try spec.writeToFile(std.testing.io, tmp.dir, "topology.spec");

    const read_back = try TopologySpec.readFromFile(std.testing.io, tmp.dir, "topology.spec");
    var tiles_buf: [topology_spec_max_tiles_for_test]tile.TileDescriptor = undefined;
    var channels_buf: [topology_spec_max_tiles_for_test]link.Channel = undefined;
    const rebuilt = read_back.toTopology(&tiles_buf, &channels_buf);

    try std.testing.expectEqual(@as(usize, 3), rebuilt.tiles.len);
    try std.testing.expectEqualStrings("tkings", rebuilt.tiles[0].id.slice());
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .exclusive = 0 }, rebuilt.tiles[0].cpu_placement);
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .shared = 1 }, rebuilt.tiles[1].cpu_placement);
    try std.testing.expectEqual(cpu_placement.CpuPlacement.floating, rebuilt.tiles[2].cpu_placement);
    try std.testing.expectEqual(@as(usize, 2), rebuilt.channels.len);
    try std.testing.expectEqual(@as(u32, 0), rebuilt.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), rebuilt.channels[0].dst_idx);
    try std.testing.expectEqualStrings("tkpay0", rebuilt.channels[0].workspace_name.slice());
}

const topology_spec_max_tiles_for_test = max_tiles;

test "TopologySpec readFromFile rejects a truncated file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(std.testing.io, "short.spec", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.TopologySpecTruncated, TopologySpec.readFromFile(std.testing.io, tmp.dir, "short.spec"));
}

test "TopologySpec readFromFile rejects a bad magic" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 0, .channel_cnt = 0 };
    spec.magic_field = 0xdeadbeef;
    try spec.writeToFile(std.testing.io, tmp.dir, "bad_magic.spec");

    try std.testing.expectError(error.TopologySpecBadMagic, TopologySpec.readFromFile(std.testing.io, tmp.dir, "bad_magic.spec"));
}

test "TopologySpec fromTopology fails closed on too many tiles" { var tiles: [max_tiles + 1]tile.TileDescriptor = undefined;
    for (&tiles) |*t| t.* = .{ .id = tile.TileId.parse("tkfoo") catch unreachable, .name = "t", .cpu_placement = .floating };
    const topo = topology.Topology{ .tiles = &tiles, .channels = &.{} };
    try std.testing.expectError(error.TooManyTiles, TopologySpec.fromTopology(topo));
}
