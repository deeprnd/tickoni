/// Root of the tickoni util module: generic, Tickoni-domain-free Linux
/// utility bindings (CPU affinity, clock, process primitives). Nothing here
/// knows about tiles, topology, or any other Tickoni framework concept —
/// see src/tickoni/runtime/ for that layer.
/// Import as @import("util") in files that use the build module system.
const std = @import("std");
const c = std.c;
const builtin = @import("builtin");
const c_abi = @import("c_abi");
pub const cpu = @import("cpu.zig");
pub const process = @import("process.zig");
pub const process_api = @import("process_api.zig");
pub const os_api = @import("os_api.zig");
pub const linux_ids = @import("linux_ids.zig");
pub const sizes = @import("sizes.zig");
pub const sandbox_defaults = @import("sandbox_defaults.zig");

/// Inline struct mirroring `struct sockaddr_in` for Zig 0.17 which
/// removed `std.posix.sockaddr_in` from the public API.
const sockaddr_in = extern struct {
    sin_family: u16,
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8 = undefined,
};

/// Host-to-network short (16-bit). Zig 0.17 removed std.posix.ntohs and
/// std.mem.hostToNetwork.  Inline byte swap works because we know this is
/// little-endian on x86_64 and the struct fields expect network byte order.
fn htons(x: u16) u16 {
    return (x >> 8) | (x << 8);
}

/// Check whether a TCP port is already bound on localhost.
/// Returns true if `bind()` fails (port in use or TIME_WAIT), false otherwise (port free).
///
/// This is used by `metricPort()` to skip ports still in TIME_WAIT
/// from a previous test run.  We use TCP sockets because the metric
/// tile's HTTP server binds TCP — a UDP bind check would miss TCP
/// TIME_WAIT ports.
///
/// NOTE: bind() succeeds when the port is FREE — we want the inverse:
/// return false on success (free) and true on failure (in use).
pub fn portIsInUse(port: u16) bool {
    if (builtin.os.tag == .windows) return c_abi.os.portIsInUse(port);
    const fd_i = std.posix.system.socket(
        std.posix.system.AF.INET,
        std.posix.system.SOCK.STREAM,
        0, // TCP (protocol 6)
    );

    // SO_REUSEADDR allows re-binding even in TIME_WAIT, but we want
    // to *detect* TIME_WAIT ports, so we intentionally do NOT set it.
    // If bind() fails here, the port is truly busy.

    var bind_addr: sockaddr_in = undefined;
    @setEvalBranchQuota(10000);
    bind_addr = sockaddr_in{
        .sin_family = @as(u16, @intCast(std.posix.system.AF.INET)),
        .sin_port = htons(port),
        .sin_addr = 0, // INADDR_ANY (0.0.0.0)
        .sin_zero = undefined,
    };
    const sin_size: std.posix.socklen_t = @intCast(@sizeOf(sockaddr_in));

    // Zig 0.17's Windows C socket declaration returns c_int while the
    // corresponding bind/close declarations require a Windows HANDLE. The
    // c_int is the Winsock SOCKET value; convert it only at that boundary.
    if (builtin.os.tag == .windows) {
        if (fd_i == -1) return true; // socket() failed, treat as busy
        const fd: std.posix.fd_t = @ptrFromInt(@as(usize, @intCast(fd_i)));
        defer _ = std.posix.system.close(fd);
        return (std.posix.system.bind(fd, @ptrCast(&bind_addr), sin_size) != 0);
    } else {
        if (fd_i < 0) return true; // socket() failed, treat as busy
        const fd: std.posix.fd_t = @intCast(fd_i);
        defer _ = std.posix.system.close(fd);
        return (std.posix.system.bind(fd, @ptrCast(&bind_addr), sin_size) != 0);
    }
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

/// Shared port counter for integration tests.
///
/// Auto-increments from 7999 (Firedancer default) on each call.  All
/// integration test modules import this same util module, so the counter
/// advances across all tests in a single binary, preventing EADDRINUSE
/// when tests run in parallel or back-to-back with TIME_WAIT sockets.
/// Port step of 100 ensures that even with aggressive TIME_WAIT recycling,
/// consecutive test runs never collide — TIME_WAIT holds sockets for up to
/// 60 s, so 100-port spacing gives ~60 tests of headroom before wrapping.
const _metric_port_step: u16 = 100;

var _metric_port_counter: u16 = 7999;
pub fn metricPort() u16 {
    while (true) {
        const result = _metric_port_counter;
        _metric_port_counter = _metric_port_counter +% _metric_port_step;

        // Skip privileged ports (< 1024) — require root to bind.
        // Counter can wrap from u16 max; unprivileged ports are
        // (1024..=65535), so wrapping through 0..1023 is harmless.
        if (result < 1024) continue;

        // Skip ports still in TIME_WAIT from prior test runs.
        if (!portIsInUse(result)) return result;
    }
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
    const cwd = std.Io.Dir.cwd();

    const base_path = blk: {
        var buf: [1024]u8 = undefined;
        const env = c.getenv("ZIG_LOCAL_CACHE_DIR");
        if (env) |raw| {
            const path = std.mem.sliceTo(raw, 0);
            const n = std.fmt.bufPrint(&buf, "{s}/tmp", .{path}) catch
                @panic("util.tmpDir: base path too long");
            break :blk buf[0..n.len];
        } else {
            const n = std.fmt.bufPrint(&buf, ".zig-cache/tmp", .{}) catch
                @panic("util.tmpDir: base path too long");
            break :blk buf[0..n.len];
        }
    };

    // Create directory hierarchy following std.testing.tmpDir() pattern:
    // cwd -> .zig-cache -> tmp -> unique_subdir
    var cache_dir = cwd.createDirPathOpen(io, ".zig-cache", .{}) catch
        @panic("util.tmpDir: failed to create .zig-cache");
    const parent_dir = cache_dir.createDirPathOpen(io, "tmp", .{}) catch
        @panic("util.tmpDir: failed to create tmp dir");

    // Generate unique subdirectory name (12 base64 chars from 12 random bytes)
    var random_bytes: [12]u8 = undefined;
    std.Io.random(io, &random_bytes);
    var sub_path: [16]u8 = undefined;
    _ = std.base64.url_safe.Encoder.encode(&sub_path, &random_bytes);

    const dir = parent_dir.createDirPathOpen(io, sub_path[0..12], .{}) catch
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
        self.parent_dir.deleteTree(io, self.sub_path[0..12]) catch {};
        self.parent_dir.close(io);
        self.cache_dir.close(io);
        self.* = undefined;
    }
};
