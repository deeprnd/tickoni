/// Root of the tickoni util module: generic, Tickoni-domain-free Linux
/// utility bindings (CPU affinity, clock, process primitives). Nothing here
/// knows about tiles, topology, or any other Tickoni framework concept —
/// see src/tickoni/runtime/ for that layer.
/// Import as @import("util") in files that use the build module system.
const std = @import("std");
const c = std.c;
const c_abi = @import("c_abi");
pub const cpu = @import("cpu.zig");
pub const process = @import("process.zig");
pub const process_api = @import("process_api.zig");
pub const os_api = @import("os_api.zig");
pub const linux_ids = @import("linux_ids.zig");
pub const sizes = @import("sizes.zig");
pub const sandbox_defaults = @import("sandbox_defaults.zig");

/// Check whether a TCP port is already bound on localhost.
/// Returns true if `bind()` fails (port in use or TIME_WAIT), false otherwise (port free).
///
/// This is used by `nextMetricPort()` to skip ports still in TIME_WAIT
/// from a previous test run.  We use TCP sockets because the metric
/// tile's HTTP server binds TCP — a UDP bind check would miss TCP
/// TIME_WAIT ports.
///
/// NOTE: bind() succeeds when the port is FREE — we want the inverse:
/// return false on success (free) and true on failure (in use).
pub fn portIsInUse(port: u16) bool {
    return c_abi.os.portIsInUse(port);
}

/// Validate that a port is NOT currently in use (free to bind).
///
/// Thin wrapper: returns true when the port is available, false when
/// `portIsInUse` reports it.  Intended for explicit assertions before
/// binding or when the caller wants a positive-check API:
///
///     port = getPort();
///     try std.testing.expect(validateNotUsedPort(port));
///
pub fn validateNotUsedPort(port: u16) bool {
    return !portIsInUse(port);
}

/// Generate a random unprivileged port for integration tests.
///
/// Uses a simple counter seeded from getpid() to pick from
/// [30000, 65535].  Each successive test call increments the counter,
/// so successive calls never collide.  This eliminates TIME_WAIT port
/// conflicts without OS-specific socket code.
var _metric_port_counter: u16 = 0;

pub fn nextMetricPort() u16 {
    const low: u16 = 30000;
    const span: u16 = 35536; // 65535 - 30000 + 1

    // Seed the counter once per process using pid (unique per test run).
    if (_metric_port_counter == 0) {
        _metric_port_counter = @as(u16, @intCast(c_abi.sandbox.getpid() & 0xFFFF));
    }

    // Map into [low, low+span)
    const port = @as(u32, low) + (_metric_port_counter % span);
    _metric_port_counter += 1;
    return @intCast(port);
}

/// Generate a unique workspace name for integration tests.
///
/// Uses the same counter-based pattern as nextMetricPort() — a static
/// counter seeded with getpid() ensures successive calls produce distinct
/// names like "topo_0", "topo_1", etc.  Callers must provide a buffer
/// (at least 16 bytes) to hold the formatted string.
var _ws_name_counter: u32 = 0;

pub fn nextWorkspaceName(buf: []u8) []const u8 {
    // Max output "topo_4294967295" = 15 chars; caller must provide ≥16 bytes.
    std.debug.assert(buf.len >= 16);
    if (_ws_name_counter == 0) {
        _ws_name_counter = @as(u32, @intCast(c_abi.sandbox.getpid())) & 0xFFFF;
    }

    const n = std.fmt.bufPrint(buf, "topo_{d}", .{_ws_name_counter}) catch unreachable;
    _ws_name_counter += 1;
    return buf[0..n.len];
}

/// Drop-in replacement for std.testing.tmpDir() that respects
/// ZIG_LOCAL_CACHE_DIR.  When set (as in the justfile), creates temp
/// directories under $ZIG_LOCAL_CACHE_DIR/tmp/ — the same cache the
/// Zig compiler uses — instead of CWD-relative .zig-cache/tmp/.
///
/// Usage (identical to std.testing.tmpDir):
///   var tmp = util.tmpDir();
///   defer tmp.cleanup();
///   const run_dir = try tmp.dir.realPath(std.testing.io, &path_buf);
///
pub fn tmpDir() TmpDir {
    const io = std.testing.io;

    const base_path = blk: {
        var buf: [1024]u8 = undefined;
        const env = c.getenv("ZIG_LOCAL_CACHE_DIR");
        if (env) |raw| {
            const path = std.mem.sliceTo(raw, 0);
            const n = std.fmt.bufPrint(&buf, "{s}/tmp", .{path}) catch
                @panic("util.tmpDir: base path too long");
            break :blk buf[0..n.len];
        } else {
            const n = std.fmt.bufPrint(&buf, "build/.zig-cache/tmp", .{}) catch
                @panic("util.tmpDir: base path too long");
            break :blk buf[0..n.len];
        }
    };

    // Create directory hierarchy: base_path (minus 'tmp') -> tmp -> unique_subdir
    const parent_dir: std.Io.Dir = blk2: {
        const last_slash = std.mem.lastIndexOfScalar(u8, base_path, '/') orelse
            @panic("util.tmpDir: base_path has no slash");
        const parent = base_path[0..last_slash];
        if (parent.len > 0 and parent[0] == '/') {
            // Absolute path: open it directly
            break :blk2 std.Io.Dir.openDir(std.Io.Dir.cwd(), io, parent, .{
                .access_sub_paths = true,
            }) catch @panic("util.tmpDir: failed to open parent dir");
        }
        // Relative path: create it, then open as a Dir handle
        var dir = std.Io.Dir.cwd();
        var remaining = parent;
        while (remaining.len > 0) {
            const slash = std.mem.indexOfScalar(u8, remaining, '/') orelse {
                _ = dir.createDirPath(io, remaining) catch
                    @panic("util.tmpDir: failed to create dir");
                break;
            };
            const comp = remaining[0..slash];
            _ = dir.createDirPath(io, comp) catch
                @panic("util.tmpDir: failed to create dir");
            remaining = remaining[slash + 1 ..];
        }
        // dir is now CWD; open `parent` as a handle
        break :blk2 dir.openDir(io, parent, .{
            .access_sub_paths = true,
        }) catch @panic("util.tmpDir: failed to open parent dir");
    };
    const tmp_dir = parent_dir.createDirPathOpen(io, "tmp", .{}) catch
        @panic("util.tmpDir: failed to create tmp dir");
    const cache_dir = tmp_dir;

    // Generate unique subdirectory name (12 base64 chars from 12 random bytes)
    var random_bytes: [12]u8 = undefined;
    std.Io.random(io, &random_bytes);
    var sub_path: [16]u8 = undefined;
    _ = std.base64.url_safe.Encoder.encode(&sub_path, &random_bytes);

    const dir = tmp_dir.createDirPathOpen(io, sub_path[0..12], .{}) catch
        @panic("util.tmpDir: failed to create temp directory");

    return .{
        .dir = dir,
        .parent_dir = parent_dir,
        .cache_dir = cache_dir,
        .base_path = base_path,
        .sub_path = sub_path,
    };
}

pub const TmpDir = struct {
    dir: std.Io.Dir,
    parent_dir: std.Io.Dir,
    cache_dir: std.Io.Dir,
    base_path: []const u8,
    sub_path: [16]u8,

    pub fn cleanup(self: *TmpDir) void {
        const io = std.testing.io;
        self.dir.close(io);

        // Guard: keep temp dirs (and their log files) when TK_KEEP_LOGS=1
        const keep = c.getenv("TK_KEEP_LOGS");
        if (keep == null or std.mem.sliceTo(keep.?, 0)[0] != '1') {
            // safe: cleanup only; primary operation completed, caller's path
            // already handles any failure via its own error path.
            self.parent_dir.deleteTree(io, self.sub_path[0..12]) catch {};
        }
        self.parent_dir.close(io);
        self.cache_dir.close(io);
        self.* = undefined;
    }
};
