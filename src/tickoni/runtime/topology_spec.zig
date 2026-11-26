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
const tile_ids_mod = @import("tile_ids.zig");
const cpu_placement = @import("cpu_placement.zig");
const link = @import("link.zig");
const topology = @import("topology.zig");
const util = @import("util");
const logger = @import("logger");

const tile_ids = tile_ids_mod;

pub const magic: u32 = 0x544b5453; // "TKST"
/// v4: per-tile `tile_kind_id`, capacity raised to 32 tiles / 64 channels for
/// the tkagnt multi-tkmodl graph (see the tkagnt fd_stem migration plan,
/// "Topology capacity and instance contract").
/// v5: per-channel `reliability`. The diagnostic fan-in links are lossy
/// (unreliable consumers), and a child that rebuilt them reliable would wire a
/// different consumer than the supervisor did.
/// v6: `case_rng_seed`, the seed of tkcase's case-id generator.
pub const version: u16 = 6;

pub const max_tiles: usize = 32;
pub const max_channels: usize = 64;

pub const TopologySpec = struct {
    magic_field: u32 = magic,
    version_field: u16 = version,
    tile_cnt: u8,
    tile_id: [max_tiles]usize = std.mem.zeroes([max_tiles]usize),
    tile_dispatch_name: [max_tiles]tile.TileId = std.mem.zeroes([max_tiles]tile.TileId),
    /// Instance ordinal among tiles sharing the same dispatch name; with the
    /// name it is the tile's `(name, kind_id)` process identity.
    tile_kind_id: [max_tiles]u8 = std.mem.zeroes([max_tiles]u8),
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
    /// `link.LinkReliability` ordinal: 0 reliable, 1 lossy.
    channel_reliability: [max_channels]u8 = std.mem.zeroes([max_channels]u8),
    workspace_name: link.WorkspaceName = std.mem.zeroes(link.WorkspaceName),
    metric_port: u16 = 7999,
    /// Pipeline event count for this run.
    ///
    /// Carried here because it is a *topology layout* input, not just tile
    /// behaviour: tkdedu's scratch footprint reserves `event_count` entries for
    /// each of its `seen_keys`/`seen_hashes` arrays, so the supervisor and every
    /// self-exec'd child must feed topo_build.build the same value or their
    /// object offsets diverge. 0 selects the tile's default reservation.
    event_count: u64 = 0,
    /// Seed of tkcase's case-id generator (tk_case_stem.c). 0 seeds it from the
    /// tile's tick counter: a fresh random case id every run. A nonzero seed
    /// repeats the run's case id, so the same inputs commit the same audit
    /// chain. Not a layout input; it travels here because the tkcase child
    /// reads its run parameters from this spec.
    case_rng_seed: u64 = 0,

    pub fn fromTopology(topo: topology.Topology, metric_port: u16, event_count: u64) error{ TooManyTiles, TooManyChannels, MissingWorkspaceName }!TopologySpec {
        const log = logger.get();
        log.enter("topology_spec", "TopologySpec.fromTopology");
        defer log.exit("topology_spec", "TopologySpec.fromTopology");
        if (topo.tiles.len > max_tiles) return error.TooManyTiles;
        if (topo.channels.len > max_channels) return error.TooManyChannels;

        var spec = TopologySpec{
            .tile_cnt = @intCast(topo.tiles.len),
            .channel_cnt = @intCast(topo.channels.len),
            .metric_port = metric_port,
            .event_count = event_count,
        };
        for (topo.tiles, 0..) |t, i| {
            spec.tile_id[i] = i;
            spec.tile_dispatch_name[i] = t.name;
            spec.tile_kind_id[i] = t.kind_id;
            spec.tile_cpu_placement[i] = t.cpu_placement;
        }
        for (topo.channels, 0..) |ch, i| {
            spec.channel_src_idx[i] = ch.src_idx;
            spec.channel_dst_idx[i] = ch.dst_idx;
            spec.channel_depth[i] = ch.depth;
            spec.channel_mtu[i] = ch.mtu;
            spec.channel_reliability[i] = @backingInt(ch.reliability);
            if (i == 0) {
                if (ch.workspace_name.isEmpty()) return error.MissingWorkspaceName;
                spec.workspace_name = ch.workspace_name;
            }
        }
        return spec;
    }

    /// Writes into caller-provided fixed buffers (no allocation).
    pub fn toTopology(self: *const TopologySpec, tiles_buf: []tile.TileDescriptor, channels_buf: []link.Channel) topology.Topology {
        const log = logger.get();
        log.enter("topology_spec", "TopologySpec.toTopology");
        defer log.exit("topology_spec", "TopologySpec.toTopology");
        std.debug.assert(tiles_buf.len >= self.tile_cnt);
        std.debug.assert(channels_buf.len >= self.channel_cnt);
        for (0..self.tile_cnt) |i| {
            tiles_buf[i] = .{
                .id = self.tile_id[i],
                .name = self.tile_dispatch_name[i],
                .cpu_placement = self.tile_cpu_placement[i],
                .kind_id = self.tile_kind_id[i],
            };
        }
        for (0..self.channel_cnt) |i| {
            channels_buf[i] = .{
                .src_idx = self.channel_src_idx[i],
                .dst_idx = self.channel_dst_idx[i],
                .depth = self.channel_depth[i],
                .mtu = self.channel_mtu[i],
                .backing = .tango_shm,
                // validate() rejects any code that is not a LinkReliability.
                .reliability = @fromBackingInt(@intCast(self.channel_reliability[i])),
                .workspace_name = self.workspace_name,
            };
        }
        return .{ .tiles = tiles_buf[0..self.tile_cnt], .channels = channels_buf[0..self.channel_cnt] };
    }

    /// Fail-closed structural check shared by every reader: counts within
    /// capacity, then the graph rules Topology.validate owns (unique
    /// `(name, kind_id)` identities in descriptor order, channel endpoint
    /// range, depth, workspace and CPU placement).
    pub fn validate(self: *const TopologySpec) !void {
        if (self.tile_cnt > max_tiles or self.channel_cnt > max_channels) return error.TopologySpecMalformed;
        for (self.channel_reliability[0..self.channel_cnt]) |code| {
            if (std.enums.fromInt(link.LinkReliability, code) == null) return error.TopologySpecMalformed;
        }
        var tiles_buf: [max_tiles]tile.TileDescriptor = undefined;
        var channels_buf: [max_channels]link.Channel = undefined;
        try self.toTopology(&tiles_buf, &channels_buf).validate();
    }

    const fio = @import("file_io.zig");

    pub fn writeToFile(self: *const TopologySpec, io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !void {
        std.debug.print("[TopologySpec] writeToFile: path={s} magic={x} version={d} tile_cnt={d} chan_cnt={d}\n", .{ sub_path, self.magic_field, self.version_field, self.tile_cnt, self.channel_cnt });
        var file = try fio.createFile(io, dir, sub_path);
        defer file.close(io);
        const bytes = std.mem.asBytes(self);
        std.debug.print("[TopologySpec] writeToFile: writing {d} bytes\n", .{bytes.len});
        try file.writePositionalAll(io, bytes, 0);
    }

    pub fn readFromFile(io: std.Io, dir: std.Io.Dir, sub_path: []const u8) !TopologySpec {
        var file = try fio.openFile(io, dir, sub_path);
        defer file.close(io);
        var spec: TopologySpec = undefined;
        const buf = std.mem.asBytes(&spec);
        const n = try file.readPositionalAll(io, buf, 0);
        std.debug.print("[TopologySpec] readFromFile: path={s} n={d} sizeof={d} read_magic={x}\n", .{ sub_path, n, @sizeOf(TopologySpec), spec.magic_field });
        if (n != @sizeOf(TopologySpec)) return error.TopologySpecTruncated;
        if (spec.magic_field != magic) return error.TopologySpecBadMagic;
        if (spec.version_field != version) return error.TopologySpecUnsupportedVersion;
        try spec.validate();
        return spec;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "TopologySpec round-trips through a file for the linear Phase 0 chain" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    const tiles = [_]tile.TileDescriptor{
        .{ .id = 0, .name = tile_ids.tkings, .cpu_placement = .{ .exclusive = 0 } },
        .{ .id = 1, .name = tile_ids.tknorm, .cpu_placement = .{ .shared = 1 } },
        .{ .id = 2, .name = tile_ids.tkdedu },
    };
    const channels = [_]link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = try link.WorkspaceName.parse("tkpay0") },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = try link.WorkspaceName.parse("tkpay0") },
    };
    const topo = topology.Topology{ .tiles = &tiles, .channels = &channels };

    const port = util.nextMetricPort();
    const spec = try TopologySpec.fromTopology(topo, port, 32);
    try spec.writeToFile(std.testing.io, tmp.dir, "topology.spec");

    const read_back = try TopologySpec.readFromFile(std.testing.io, tmp.dir, "topology.spec");
    var tiles_buf: [topology_spec_max_tiles_for_test]tile.TileDescriptor = undefined;
    var channels_buf: [topology_spec_max_tiles_for_test]link.Channel = undefined;
    const rebuilt = read_back.toTopology(&tiles_buf, &channels_buf);

    try std.testing.expectEqual(@as(usize, 3), rebuilt.tiles.len);
    try std.testing.expectEqualStrings(tile_ids.tkings.slice(), rebuilt.tiles[0].name.slice());
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .exclusive = 0 }, rebuilt.tiles[0].cpu_placement);
    try std.testing.expectEqual(cpu_placement.CpuPlacement{ .shared = 1 }, rebuilt.tiles[1].cpu_placement);
    try std.testing.expectEqual(cpu_placement.CpuPlacement.floating, rebuilt.tiles[2].cpu_placement);
    try std.testing.expectEqual(@as(usize, 2), rebuilt.channels.len);
    try std.testing.expectEqual(@as(u32, 0), rebuilt.channels[0].src_idx);
    try std.testing.expectEqual(@as(u32, 1), rebuilt.channels[0].dst_idx);
    try std.testing.expectEqualStrings("tkpay0", rebuilt.channels[0].workspace_name.slice());
    // event_count must survive the round-trip: a child that reads back a
    // different value than the supervisor wrote derives a different tkdedu
    // scratch footprint, and every object offset after it shifts.
    try std.testing.expectEqual(@as(u64, 32), read_back.event_count);
    try std.testing.expectEqual(port, read_back.metric_port);
}

const topology_spec_max_tiles_for_test = max_tiles;

test "TopologySpec round-trips each channel's reliability, so a child rebuilds the parent's consumers" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    const wksp = try link.WorkspaceName.parse("tkpay0");
    const tiles = [_]tile.TileDescriptor{
        .{ .id = 0, .name = tile_ids.tkings },
        .{ .id = 1, .name = tile_ids.tknorm },
        .{ .id = 2, .name = tile_ids.tkdiag },
    };
    const channels = [_]link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .reliability = .reliable, .workspace_name = wksp },
        .{ .src_idx = 0, .dst_idx = 2, .depth = 64, .mtu = 128, .backing = .tango_shm, .reliability = .lossy, .workspace_name = wksp },
        .{ .src_idx = 1, .dst_idx = 2, .depth = 64, .mtu = 128, .backing = .tango_shm, .reliability = .lossy, .workspace_name = wksp },
    };
    const topo = topology.Topology{ .tiles = &tiles, .channels = &channels };

    const spec = try TopologySpec.fromTopology(topo, util.nextMetricPort(), 0);
    try spec.writeToFile(std.testing.io, tmp.dir, "reliability.spec");
    const read_back = try TopologySpec.readFromFile(std.testing.io, tmp.dir, "reliability.spec");
    try read_back.validate();

    var tiles_buf: [topology_spec_max_tiles_for_test]tile.TileDescriptor = undefined;
    var channels_buf: [max_channels]link.Channel = undefined;
    const rebuilt = read_back.toTopology(&tiles_buf, &channels_buf);
    try std.testing.expectEqual(@as(usize, 3), rebuilt.channels.len);
    for (channels, rebuilt.channels) |want, got| try std.testing.expectEqual(want.reliability, got.reliability);
}

test "TopologySpec validate rejects an unknown channel reliability code" {
    const wksp = try link.WorkspaceName.parse("tkpay0");
    const tiles = [_]tile.TileDescriptor{
        .{ .id = 0, .name = tile_ids.tkings },
        .{ .id = 1, .name = tile_ids.tknorm },
    };
    const channels = [_]link.Channel{
        .{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm, .workspace_name = wksp },
    };
    var spec = try TopologySpec.fromTopology(.{ .tiles = &tiles, .channels = &channels }, util.nextMetricPort(), 0);
    try spec.validate();
    spec.channel_reliability[0] = 2;
    try std.testing.expectError(error.TopologySpecMalformed, spec.validate());
}

test "TopologySpec readFromFile rejects a truncated file" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(std.testing.io, "short.spec", .{});
    try file.writePositionalAll(std.testing.io, &[_]u8{ 1, 2, 3, 4 }, 0);
    file.close(std.testing.io);

    try std.testing.expectError(error.TopologySpecTruncated, TopologySpec.readFromFile(std.testing.io, tmp.dir, "short.spec"));
}

test "TopologySpec readFromFile rejects a bad magic" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 0, .channel_cnt = 0 };
    spec.magic_field = 0xdeadbeef;
    try spec.writeToFile(std.testing.io, tmp.dir, "bad_magic.spec");

    try std.testing.expectError(error.TopologySpecBadMagic, TopologySpec.readFromFile(std.testing.io, tmp.dir, "bad_magic.spec"));
}

test "TopologySpec fromTopology fails closed on too many tiles" {
    const port = util.nextMetricPort();
    var tiles: [max_tiles + 1]tile.TileDescriptor = undefined;
    for (&tiles, 0..) |*t, i| t.* = .{ .id = i, .name = tile_ids.tkings, .cpu_placement = .floating };
    const topo = topology.Topology{ .tiles = &tiles, .channels = &.{} };
    try std.testing.expectError(error.TooManyTiles, TopologySpec.fromTopology(topo, port, 0));
}

// The illustrative N-model agent graph from the tkagnt migration plan:
// N+4 tiles and 1+3N channels (one agent-request link, then per model a
// request, a result and a model-audit link). Tile order: tkings, tkagnt,
// tkaudt, tkmodl kind 0..N-1, metric.
const agent_graph_tile_cnt = 11 + 4;
const agent_graph_channel_cnt = 1 + 3 * 11;
const agent_graph_first_model_idx = 3;

fn agentGraph(
    tiles: *[agent_graph_tile_cnt]tile.TileDescriptor,
    channels: *[agent_graph_channel_cnt]link.Channel,
) !topology.Topology {
    const wksp = try link.WorkspaceName.parse("tkpay0");
    tiles[0] = .{ .id = 0, .name = tile_ids.tkings };
    tiles[1] = .{ .id = 1, .name = tile_ids.tkagnt };
    tiles[2] = .{ .id = 2, .name = tile_ids.tkaudt };
    for (0..11) |m| {
        tiles[agent_graph_first_model_idx + m] = .{
            .id = agent_graph_first_model_idx + m,
            .name = tile_ids.tkmodl,
            .kind_id = @intCast(m),
        };
    }
    tiles[agent_graph_tile_cnt - 1] = .{ .id = agent_graph_tile_cnt - 1, .name = tile_ids.metric };

    channels[0] = .{ .src_idx = 0, .dst_idx = 1, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
    for (0..11) |m| {
        const model_idx: u32 = @intCast(agent_graph_first_model_idx + m);
        channels[1 + 3 * m + 0] = .{ .src_idx = 1, .dst_idx = model_idx, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
        channels[1 + 3 * m + 1] = .{ .src_idx = model_idx, .dst_idx = 2, .depth = 32, .mtu = 256, .backing = .tango_shm, .workspace_name = wksp };
        channels[1 + 3 * m + 2] = .{ .src_idx = model_idx, .dst_idx = 1, .depth = 32, .mtu = 8192, .backing = .tango_shm, .workspace_name = wksp };
    }
    return .{ .tiles = tiles, .channels = channels };
}

test "TopologySpec round-trips the 11-model agent graph with each tkmodl kind_id" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var tiles: [agent_graph_tile_cnt]tile.TileDescriptor = undefined;
    var channels: [agent_graph_channel_cnt]link.Channel = undefined;
    const topo = try agentGraph(&tiles, &channels);
    try topo.validate();

    const spec = try TopologySpec.fromTopology(topo, util.nextMetricPort(), 8);
    try spec.writeToFile(std.testing.io, tmp.dir, "agent.spec");
    const read_back = try TopologySpec.readFromFile(std.testing.io, tmp.dir, "agent.spec");

    var tiles_buf: [max_tiles]tile.TileDescriptor = undefined;
    var channels_buf: [max_channels]link.Channel = undefined;
    const rebuilt = read_back.toTopology(&tiles_buf, &channels_buf);
    try rebuilt.validate();

    try std.testing.expectEqual(@as(usize, agent_graph_tile_cnt), rebuilt.tiles.len);
    try std.testing.expectEqual(@as(usize, agent_graph_channel_cnt), rebuilt.channels.len);
    for (topo.tiles, rebuilt.tiles) |want, got| {
        try std.testing.expect(want.name.eql(got.name));
        try std.testing.expectEqual(want.kind_id, got.kind_id);
    }
    for (topo.channels, rebuilt.channels) |want, got| {
        try std.testing.expectEqual(want.src_idx, got.src_idx);
        try std.testing.expectEqual(want.dst_idx, got.dst_idx);
        try std.testing.expectEqual(want.mtu, got.mtu);
    }
}

test "TopologySpec holds the approved capacity of 32 tiles and 64 channels" {
    try std.testing.expect(max_tiles >= 32);
    try std.testing.expect(max_channels >= 64);

    var tiles: [max_tiles]tile.TileDescriptor = undefined;
    tiles[0] = .{ .id = 0, .name = tile_ids.tkings };
    for (tiles[1..], 1..) |*t, i| t.* = .{ .id = i, .name = tile_ids.tkmodl, .kind_id = @intCast(i - 1) };
    var channels: [max_channels]link.Channel = undefined;
    for (&channels, 0..) |*ch, i| {
        ch.* = .{
            .src_idx = 0,
            .dst_idx = @intCast(1 + i % (max_tiles - 1)),
            .depth = 32,
            .mtu = 256,
            .backing = .tango_shm,
            .workspace_name = try link.WorkspaceName.parse("tkpay0"),
        };
    }
    const spec = try TopologySpec.fromTopology(.{ .tiles = &tiles, .channels = &channels }, util.nextMetricPort(), 0);
    try std.testing.expectEqual(@as(u8, max_tiles), spec.tile_cnt);
    try std.testing.expectEqual(@as(u8, max_channels), spec.channel_cnt);
}

test "TopologySpec fromTopology fails closed on too many channels" {
    var tiles = [_]tile.TileDescriptor{
        .{ .id = 0, .name = tile_ids.tkings },
        .{ .id = 1, .name = tile_ids.tknorm },
    };
    var channels: [max_channels + 1]link.Channel = undefined;
    for (&channels) |*ch| ch.* = .{ .src_idx = 0, .dst_idx = 1, .depth = 32, .mtu = 64 };
    try std.testing.expectError(
        error.TooManyChannels,
        TopologySpec.fromTopology(.{ .tiles = &tiles, .channels = &channels }, util.nextMetricPort(), 0),
    );
}

test "TopologySpec toTopology rebuilds each name from its own array index" {
    // tile_id[i] is the descriptor's positional id, not an index into the
    // name table. A spec whose ids are permuted must still keep every name
    // next to its own cpu placement and kind_id.
    var spec = TopologySpec{ .tile_cnt = 3, .channel_cnt = 0 };
    spec.tile_id[0] = 2;
    spec.tile_id[1] = 0;
    spec.tile_id[2] = 1;
    spec.tile_dispatch_name[0] = tile_ids.tkings;
    spec.tile_dispatch_name[1] = tile_ids.tkmodl;
    spec.tile_dispatch_name[2] = tile_ids.tkmodl;
    spec.tile_kind_id[1] = 0;
    spec.tile_kind_id[2] = 1;

    var tiles_buf: [max_tiles]tile.TileDescriptor = undefined;
    var channels_buf: [max_channels]link.Channel = undefined;
    const rebuilt = spec.toTopology(&tiles_buf, &channels_buf);

    try std.testing.expect(rebuilt.tiles[0].name.eql(tile_ids.tkings));
    try std.testing.expect(rebuilt.tiles[1].name.eql(tile_ids.tkmodl));
    try std.testing.expect(rebuilt.tiles[2].name.eql(tile_ids.tkmodl));
    try std.testing.expectEqual(@as(u8, 0), rebuilt.tiles[1].kind_id);
    try std.testing.expectEqual(@as(u8, 1), rebuilt.tiles[2].kind_id);
    try std.testing.expectEqual(@as(usize, 2), rebuilt.tiles[0].id);
}

test "TopologySpec readFromFile rejects a duplicate tile identity" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 2, .channel_cnt = 0 };
    spec.tile_dispatch_name[0] = tile_ids.tkmodl;
    spec.tile_dispatch_name[1] = tile_ids.tkmodl;
    spec.tile_kind_id[0] = 0;
    spec.tile_kind_id[1] = 0;
    try spec.writeToFile(std.testing.io, tmp.dir, "dup.spec");

    try std.testing.expectError(error.DuplicateTileIdentity, TopologySpec.readFromFile(std.testing.io, tmp.dir, "dup.spec"));
}

test "TopologySpec readFromFile rejects a kind_id gap" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 2, .channel_cnt = 0 };
    spec.tile_dispatch_name[0] = tile_ids.tkmodl;
    spec.tile_dispatch_name[1] = tile_ids.tkmodl;
    spec.tile_kind_id[0] = 0;
    spec.tile_kind_id[1] = 2;
    try spec.writeToFile(std.testing.io, tmp.dir, "gap.spec");

    try std.testing.expectError(error.TileKindIdMismatch, TopologySpec.readFromFile(std.testing.io, tmp.dir, "gap.spec"));
}

test "TopologySpec readFromFile rejects a channel endpoint beyond tile_cnt" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 2, .channel_cnt = 1 };
    spec.tile_dispatch_name[0] = tile_ids.tkings;
    spec.tile_dispatch_name[1] = tile_ids.tknorm;
    spec.channel_src_idx[0] = 0;
    spec.channel_dst_idx[0] = 2;
    spec.channel_depth[0] = 32;
    try spec.writeToFile(std.testing.io, tmp.dir, "endpoint.spec");

    try std.testing.expectError(error.ChannelDstOutOfRange, TopologySpec.readFromFile(std.testing.io, tmp.dir, "endpoint.spec"));
}

test "TopologySpec readFromFile rejects counts above the capacity" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = max_tiles, .channel_cnt = 0 };
    spec.tile_cnt = @intCast(max_tiles);
    // One past capacity cannot be expressed through fromTopology, so write
    // the raw byte the way a corrupt or foreign file would carry it.
    spec.channel_cnt = 255;
    try spec.writeToFile(std.testing.io, tmp.dir, "counts.spec");

    try std.testing.expectError(error.TopologySpecMalformed, TopologySpec.readFromFile(std.testing.io, tmp.dir, "counts.spec"));
}

test "TopologySpec readFromFile fails closed on an unsupported version" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var spec = TopologySpec{ .tile_cnt = 0, .channel_cnt = 0 };
    spec.version_field = version - 1;
    try spec.writeToFile(std.testing.io, tmp.dir, "old_version.spec");

    try std.testing.expectError(
        error.TopologySpecUnsupportedVersion,
        TopologySpec.readFromFile(std.testing.io, tmp.dir, "old_version.spec"),
    );
}
