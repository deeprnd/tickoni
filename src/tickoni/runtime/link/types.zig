const std = @import("std");

/// Bounded name of the Firedancer workspace (src/util/wksp) backing a
/// correctness-bearing link's mcache/dcache/fseq/cnc objects in process
/// mode. 32 bytes is generous for a Tickoni-chosen name; fd_wksp itself has
/// no such limit, but topology identifiers stay fixed-capacity like TileId.
pub const WorkspaceName = struct { bytes: [32]u8 = std.mem.zeroes([32]u8),

    pub fn parse(s: []const u8) error{WorkspaceNameTooLong}!WorkspaceName {
        if (s.len > 32) return error.WorkspaceNameTooLong;
        var w = WorkspaceName{};
        @memcpy(w.bytes[0..s.len], s);
        return w;
    }

    pub fn slice(self: *const WorkspaceName) []const u8 { const end = std.mem.indexOfScalar(u8, &self.bytes, 0) orelse 32;
        return self.bytes[0..end]; }

    pub fn isEmpty(self: *const WorkspaceName) bool { return self.slice().len == 0; }
};

/// Which substrate backs a channel's payload transport.
pub const LinkBacking = enum {
    /// Heap-backed in-process ring (dev/test thread-mode lane only).
    heap_dev,
    /// Firedancer Tango mcache/dcache/fseq shared memory (process mode).
    tango_shm, };

pub const LinkReliability = enum { reliable, lossy };

/// Directed channel between two tiles: exactly one producer, one consumer.
pub const Channel = struct {
    src_idx: u32,
    dst_idx: u32,
    /// Ring-buffer depth — must be a power of two.
    depth: u32,
    /// Max fragment size in bytes; 0 means no dcache.
    mtu: u32,
    /// Defaults to heap_dev: existing topologies use the in-process ring.
    backing: LinkBacking = .heap_dev,
    /// Defaults to reliable: correctness-bearing links backpressure instead
    /// of dropping. Only telemetry links should be lossy.
    reliability: LinkReliability = .reliable,
    /// Required (non-empty) when backing == .tango_shm.
    workspace_name: WorkspaceName = .{},
};

test "WorkspaceName parse and slice round-trip" { const w = try WorkspaceName.parse("tkpay0");
    try std.testing.expectEqualStrings("tkpay0", w.slice());
    try std.testing.expect(!w.isEmpty()); }

test "WorkspaceName parse rejects names longer than 32 chars" { try std.testing.expectError(error.WorkspaceNameTooLong, WorkspaceName.parse("a"**33)); }

test "WorkspaceName default is empty" {
    const w = WorkspaceName{};
    try std.testing.expect(w.isEmpty());
}
