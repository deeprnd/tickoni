/// Root of the tickoni util module: generic, Tickoni-domain-free Linux
/// utility bindings (CPU affinity, clock, process primitives). Nothing here
/// knows about tiles, topology, or any other Tickoni framework concept —
/// see src/tickoni/runtime/ for that layer.
/// Import as @import("util") in files that use the build module system.
const std = @import("std");
const c = std.c;
pub const cpu = @import("cpu.zig");
pub const process = @import("process.zig");
pub const process_api = @import("process_api.zig");
pub const os_api = @import("os_api.zig");
pub const linux_ids = @import("linux_ids.zig");
pub const sizes = @import("sizes.zig");
pub const sandbox_defaults = @import("sandbox_defaults.zig");

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
