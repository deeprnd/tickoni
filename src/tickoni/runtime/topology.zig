const std = @import("std");
const tile = @import("tile.zig");
const cpu_placement = @import("cpu_placement.zig");
const link = @import("link.zig");

pub const TileId = tile.TileId;
pub const TileDescriptor = tile.TileDescriptor;
pub const CpuPlacement = cpu_placement.CpuPlacement;
pub const WorkspaceName = link.WorkspaceName;
pub const LinkBacking = link.LinkBacking;
pub const LinkReliability = link.LinkReliability;
pub const Channel = link.Channel;

/// Immutable snapshot of tile ownership and channel wiring. The tile and link
/// modules own the underlying descriptor types; topology owns only the graph.
pub const Topology = struct {
    tiles: []const TileDescriptor,
    channels: []const Channel,

    pub fn validate(self: Topology) !void {
        for (self.tiles) |t| {
            // TileId.parse always succeeds for ≤6-char inputs; empty name only
            // happens if someone explicitly parsed "".  Keep the check for
            // explicit empty-name detection via zeroed TileId.
            if (t.name.eql(.{})) return error.EmptyTileName;
        }
        for (self.channels) |ch| {
            if (ch.src_idx >= self.tiles.len) return error.ChannelSrcOutOfRange;
            if (ch.dst_idx >= self.tiles.len) return error.ChannelDstOutOfRange;
            if (ch.src_idx == ch.dst_idx) return error.ChannelSelfLoop;
            if (ch.depth == 0 or !std.math.isPowerOfTwo(ch.depth)) return error.ChannelDepthNotPowerOfTwo;
            if (ch.backing == .tango_shm) {
                var name = ch.workspace_name;
                if (name.isEmpty()) return error.ChannelWorkspaceNameMissing;
            }
        }
        try cpu_placement.validateStatic(self.tiles);
    }
};

// Shared synthetic tile ids for the validate() tests below, so the same id
// text is not retyped as a raw string literal in every test case.
const test_tile_foo = TileId.parse("tkfoo") catch unreachable;
const test_tile_bar = TileId.parse("tkbar") catch unreachable;
const test_tile_baz = TileId.parse("tkbaz") catch unreachable;
const test_name_foo = TileId.parse("foo") catch unreachable;
const test_name_bar = TileId.parse("bar") catch unreachable;
const test_name_baz = TileId.parse("baz") catch unreachable;

test "validate rejects non-power-of-two channel depth" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo },
            .{ .id = 1, .name = test_name_bar },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 7, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelDepthNotPowerOfTwo, topo.validate());
}

test "validate rejects self-loop channel" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 0, .depth = 64, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelSelfLoop, topo.validate());
}

test "validate rejects out-of-range channel src" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo },
        },
        .channels = &.{.{ .src_idx = 99, .dst_idx = 0, .depth = 64, .mtu = 0 }},
    };
    try std.testing.expectError(error.ChannelSrcOutOfRange, topo.validate());
}

test "validate rejects tango_shm channel with missing workspace name" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo },
            .{ .id = 1, .name = test_name_bar },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128, .backing = .tango_shm }},
    };
    try std.testing.expectError(error.ChannelWorkspaceNameMissing, topo.validate());
}

test "validate accepts heap_dev channel with no workspace name" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo },
            .{ .id = 1, .name = test_name_bar },
        },
        .channels = &.{.{ .src_idx = 0, .dst_idx = 1, .depth = 64, .mtu = 128 }},
    };
    try topo.validate();
}

test "validate rejects two tiles pinned exclusive on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo, .cpu_placement = .{ .exclusive = 0 } },
            .{ .id = 1, .name = test_name_bar, .cpu_placement = .{ .exclusive = 0 } },
        },
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate rejects exclusive and shared colliding on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo, .cpu_placement = .{ .exclusive = 2 } },
            .{ .id = 1, .name = test_name_bar, .cpu_placement = .{ .shared = 2 } },
        },
        .channels = &.{},
    };
    try std.testing.expectError(error.CpuPlacementConflict, topo.validate());
}

test "validate accepts two tiles declaring shared on the same cpu" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo, .cpu_placement = .{ .shared = 3 } },
            .{ .id = 1, .name = test_name_bar, .cpu_placement = .{ .shared = 3 } },
        },
        .channels = &.{},
    };
    try topo.validate();
}

test "validate accepts distinct exclusive cpu ids and floating tiles" {
    const topo = Topology{
        .tiles = &.{
            .{ .id = 0, .name = test_name_foo, .cpu_placement = .{ .exclusive = 0 } },
            .{ .id = 1, .name = test_name_bar, .cpu_placement = .{ .exclusive = 1 } },
            .{ .id = 2, .name = test_name_baz },
        },
        .channels = &.{},
    };
    try topo.validate();
}
