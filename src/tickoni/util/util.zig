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

/// Convert a `[]const u8` slice to a null-terminated pointer suitable for
/// C FFI. Caller supplies the buffer — the returned pointer is valid as long
/// as the buffer outlives the call (never returns a dangling pointer).
///
/// Usage:
///   var buf: [8]u8 = undefined;
///   const z = util.toZ(&buf, some_slice);
pub fn toZ(buf: []u8, s: []const u8) [*:0]const u8 {
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return @ptrCast(&buf[0]);
}

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

/// Generate a free unprivileged port for integration tests.
///
/// A counter seeded from getpid() picks a candidate in [30000, 65535] and
/// each call advances it, so successive calls within one process never
/// collide.  The pid seed alone is NOT sufficient across processes: the
/// integration lane runs its test binaries sequentially
/// (build-lib/lanes/integration.zig chains the run steps), consecutive
/// binaries get nearby pids, and a single binary consumes one port per
/// pipeline start — up to 12 in test_metric_tile_integration.zig.  Nearby
/// seeds therefore produce OVERLAPPING ranges, and a candidate can still be
/// held by a metric tile from an earlier binary (or sit in TIME_WAIT).
///
/// So each candidate is probed with `portIsInUse` and skipped when bound,
/// which is what this function's contract has always been (see
/// `portIsInUse` above: "used by nextMetricPort() to skip ports still in
/// TIME_WAIT from a previous test run").  Binding the port is fatal for the
/// metric tile — fd_metric_tile.c's listen failure is an FD_LOG_ERR, which
/// aborts the tile and surfaces as a `.crashed` tile in otherwise unrelated
/// supervisor tests — so handing out an occupied port fails the suite
/// nondeterministically.
///
/// This probe leaves a TOCTOU window: the caller binds later, so a port that
/// was free here can be taken in between.  The window is unavoidable without
/// passing the bound socket down into the tile, and it is not the failure
/// mode seen in practice (that one is a port still held for the whole
/// lifetime of an earlier test's metric tile), which this does eliminate.
var _metric_port_counter: u16 = 0;

/// Bound on candidates probed before giving up.  Reaching it means ~1024
/// consecutive ports are bound, which is an environment problem, not a
/// collision this helper can retry its way out of.
const metric_port_max_probes: u16 = 1024;

pub fn nextMetricPort() u16 {
    const low: u16 = 30000;
    const span: u16 = 35536; // 65535 - 30000 + 1

    // Seed the counter once per process using pid (unique per test run).
    if (_metric_port_counter == 0) {
        _metric_port_counter = @as(u16, @intCast(c_abi.sandbox.getpid() & 0xFFFF));
    }

    var probes: u16 = 0;
    while (probes < metric_port_max_probes) : (probes += 1) {
        // Map into [low, low+span)
        const port: u16 = @intCast(@as(u32, low) + (_metric_port_counter % span));
        _metric_port_counter +%= 1;
        // Re-seeding on a 0 counter is the sentinel above, so never leave it
        // at 0 — that would redo the pid seed and replay this same range.
        if (_metric_port_counter == 0) _metric_port_counter = 1;
        if (!portIsInUse(port)) return port;
    }

    // Fail closed and loudly: silently returning a bound port would show up
    // as an unrelated tile crash much later in the run.
    std.debug.panic(
        "nextMetricPort: no free port in [{d}, {d}] after {d} probes",
        .{ @as(u32, low), @as(u32, low) + @as(u32, span) - 1, metric_port_max_probes },
    );
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
            break :blk2 std.Io.Dir.openDir(std.Io.Dir.cwd(), io, parent, .{
                .access_sub_paths = true,
            }) catch @panic("util.tmpDir: failed to open parent dir");
        }
        // Relative path: open each component progressively (openDir doesn't
        // support multi-component relative paths)
        var dir = std.Io.Dir.cwd();
        var remaining = parent;
        while (remaining.len > 0) {
            const slash = std.mem.indexOfScalar(u8, remaining, '/') orelse {
                dir = dir.createDirPathOpen(io, remaining, .{}) catch
                    @panic("util.tmpDir: failed to open parent dir");
                break;
            };
            const comp = remaining[0..slash];
            dir = dir.createDirPathOpen(io, comp, .{}) catch
                @panic("util.tmpDir: failed to open parent dir");
            remaining = remaining[slash + 1 ..];
        }
        break :blk2 dir;
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
            self.parent_dir.deleteTree(io, self.sub_path[0..12]) catch |err| std.log.err("defer deleteTree: {any}", .{err});
        }
        self.parent_dir.close(io);
        self.cache_dir.close(io);
        self.* = undefined;
    }
};
