const std = @import("std");
const cpu_placement = @import("cpu_placement.zig");

/// Six-character runtime ID for a tile (matches the fd_topo char name[7] constraint).
pub const TileId = struct {
    bytes: [6]u8 = std.mem.zeroes([6]u8),

    pub fn parse(s: []const u8) error{TileIdTooLong}!TileId {
        if (s.len > 6) return error.TileIdTooLong;
        var id = TileId{};
        @memcpy(id.bytes[0..s.len], s);
        return id;
    }

    pub fn slice(self: *const TileId) []const u8 {
        const end = std.mem.indexOfScalar(u8, &self.bytes, 0) orelse 6;
        return self.bytes[0..end];
    }

    pub fn eql(self: TileId, other: TileId) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }
};

/// Static description of one tile in a topology.
pub const TileDescriptor = struct {
    id: TileId,
    /// Human-readable name used in logs and diagnostics.
    name: []const u8,
    /// Defaults to floating: existing thread-mode topologies do not pin
    /// CPUs. Process-mode topologies set this explicitly.
    cpu_placement: cpu_placement.CpuPlacement = .floating,
};

pub const TileState = enum {
    stopped,
    starting,
    running,
    stopping,
    /// Tile process is still alive but its heartbeat has not advanced
    /// within the supervisor's stale threshold.
    stale,
    /// Tile exited with a non-zero status; topology is unhealthy.
    crashed,
    /// Shutdown reached its deadline without a terminal reap observation.
    /// Shared process resources remain retained and cleanup may be retried.
    unresolved,
    /// The supervisor confirmed that it no longer owns a child process but
    /// did not receive a terminal observation for it.
    detached,
};

/// Identifies why a tile transitioned to .crashed, for supervisor
/// diagnostics and crash/health-isolation tests. Every retained value must
/// be producible by an implemented supervisor monitoring path.
pub const CrashReason = enum {
    none,
    /// Process exited with a non-zero status (or thread-mode equivalent).
    exit_code,
    /// Supervisor observed a non-advancing heartbeat past the configured
    /// stale threshold.
    stale,
    /// Process was terminated by a signal (e.g. SIGKILL), process mode
    /// only. Distinct from exit_code because the tile never got to exit
    /// on its own terms — a forced-kill/OOM-style death rather than a
    /// self-detected failure.
    signal,
};

/// Raw process evidence retained by a tile handle. These mirror the portable
/// process API's transport values without making the runtime tile model depend
/// on the util module (topology-only unit tests import this file directly).
pub const ProcessObservation = union(enum) {
    exited: u32,
    signaled: u32,
    stopped: u32,
};

pub const ProcessTerminationAction = union(enum) {
    signal: u32,
    exit_code: u32,
};

pub const ProcessError = struct {
    category: u32,
    native_code: u32,
};

/// Runtime handle for one tile managed by the supervisor.
pub const TileHandle = struct {
    tile_idx: u32,
    state: TileState,
    /// Non-null when the tile runs as an in-process thread (test/dev mode).
    thread: ?std.Thread,
    /// Full-width native exit code; meaningful when state == .crashed.
    exit_code: u32,
    /// Non-null when the tile runs as a supervisor-managed OS process
    /// (v2.14 process mode).
    pid: ?std.process.Child.Id = null,
    /// Effective CPU placement for this tile, copied from the topology at
    /// start time so diagnostics do not need to re-consult the topology.
    cpu_placement: cpu_placement.CpuPlacement = .floating,
    /// Meaningful only when state == .crashed.
    crashed_because: CrashReason = .none,
    /// The unclassified process observation that last changed this handle.
    observation: ?ProcessObservation = null,
    /// The exact accepted force action, if any, for this run.
    termination_action: ?ProcessTerminationAction = null,
    /// The last reap/terminate failure; retained through shutdown diagnostics.
    last_process_error: ?ProcessError = null,

    pub fn init(idx: u32) TileHandle {
        return .{ .tile_idx = idx, .state = .stopped, .thread = null, .exit_code = 0 };
    }

    pub fn isAlive(self: TileHandle) bool {
        return switch (self.state) {
            .starting, .running, .stopping, .stale, .unresolved => true,
            .stopped, .crashed, .detached => false,
        };
    }
};

test "TileId parse valid 6-char name" {
    const id = try TileId.parse("tkings");
    try std.testing.expectEqualStrings("tkings", id.slice());
}

test "TileId parse short name" {
    const id = try TileId.parse("tk");
    try std.testing.expectEqualStrings("tk", id.slice());
}

test "TileId parse rejects names longer than 6 chars" {
    try std.testing.expectError(error.TileIdTooLong, TileId.parse("toolong7"));
}

test "TileId equality" {
    const a = try TileId.parse("tknorm");
    const b = try TileId.parse("tknorm");
    const c = try TileId.parse("tkdedu");
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}

test "TileHandle initialises in stopped state" {
    const h = TileHandle.init(0);
    try std.testing.expectEqual(TileState.stopped, h.state);
    try std.testing.expectEqual(@as(u32, 0), h.tile_idx);
    try std.testing.expect(!h.isAlive());
}

test "TileHandle isAlive is true for running" {
    var h = TileHandle.init(1);
    h.state = .running;
    try std.testing.expect(h.isAlive());
}

test "TileHandle isAlive is true for starting and stopping" {
    var h = TileHandle.init(2);
    h.state = .starting;
    try std.testing.expect(h.isAlive());
    h.state = .stopping;
    try std.testing.expect(h.isAlive());
}

test "TileHandle isAlive is true for stale" {
    var h = TileHandle.init(4);
    h.state = .stale;
    try std.testing.expect(h.isAlive());
}

test "TileHandle isAlive is false for crashed" {
    var h = TileHandle.init(3);
    h.state = .crashed;
    try std.testing.expect(!h.isAlive());
}
