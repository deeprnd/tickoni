/// Fixture path resolution helpers.
///
/// Replaces runtime `cwd().readFileAlloc` + `@src().file` patterns that fail
/// when the binary runs from `.zig-cache/o/...`.  See
/// doc/execution/plans/v2.10-s2-6.md.
///
/// Strategy: walk up from the executable's directory to find the repo root
/// (a directory whose child is `src/`), then prepend it to the comptime
/// fixture path.
const std = @import("std");
const build_options = @import("build_options");

const Io = std.Io;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

// ---------------------------------------------------------------------------
// Comptime fixture directory constants
// ---------------------------------------------------------------------------

pub const investment_scenarios = build_options.FIXTURE_INVESTMENT_SCENARIOS;
pub const portfolio = build_options.FIXTURE_PORTFOLIO;

// Proto files used by schema tests
pub const classification_proto = build_options.FIXTURE_CLASSIFICATION_PROTO;
pub const thesis_proto = build_options.FIXTURE_THESIS_PROTO;
pub const basket_proto = build_options.FIXTURE_BASKET_PROTO;

// ---------------------------------------------------------------------------
// Runtime path resolution
// ---------------------------------------------------------------------------

/// Resolve a repo-relative path (starting with "src/") against the
/// executable's location by walking up the tree to find the repo root
/// (a directory whose child is "src/").  Caller must free the returned
/// slice.
pub fn resolveFixturePath(
    allocator: Allocator,
    io: Io,
    path: []const u8,
) ![]u8 {
    if (!std.mem.startsWith(u8, path, "src/")) {
        return allocator.dupe(u8, path);
    }

    const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(exe_dir);
    var current: []const u8 = std.fs.path.dirname(exe_dir) orelse return error.InvalidPath;

    // Walk up from executable dir to find repo root (a directory whose child
    // is `src/`).  If the walk reaches the filesystem root without finding
    // `src/` (e.g. cov binaries installed to /tmp/...), fall back to the
    // current working directory which should be the repo root.
    var repo_root_path: ?[]u8 = null;
    var repo_root_found: bool = false;
    errdefer {
        if (repo_root_path) |rp| allocator.free(rp);
    }

    var depth: usize = 0;
    while (depth < 20) : (depth += 1) {
        var p: [1024]u8 = undefined;
        const path_str = try std.fmt.bufPrint(&p, "{s}/src", .{current});
        const exists = blk: {
            Dir.access(Dir.cwd(), io, path_str, .{}) catch break :blk false;
            break :blk true;
        };
        if (exists) {
            repo_root_path = try allocator.dupe(u8, current);
            repo_root_found = true;
            break;
        }
        const next = std.fs.path.dirname(current);
        if (next == null) break;
        current = next.?;
    }

    // Fallback: if walk-up failed (e.g. cov output outside repo tree),
    // check if the CWD itself is the repo root.
    const root = if (repo_root_found) repo_root_path.? else (
        blk: {
            var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
            const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.InvalidPath;
            var cwd_len: usize = 0;
            while (cwd_ptr[cwd_len] != 0) : (cwd_len += 1) {}
            const cwd_path = cwd_ptr[0..cwd_len];
            var p: [1024]u8 = undefined;
            const path_str = try std.fmt.bufPrint(&p, "{s}/src", .{cwd_path});
            const src_exists = blk2: {
                Dir.accessAbsolute(io, path_str, .{}) catch break :blk2 false;
                break :blk2 true;
            };
            if (src_exists) {
                break :blk try allocator.dupe(u8, cwd_path);
            } else return error.InvalidPath;
        }
    );
    const resolved = try allocator.alloc(u8, root.len + 1 + path.len);
    @memcpy(resolved[0..root.len], root);
    allocator.free(root);
    resolved[root.len] = '/';
    @memcpy(resolved[root.len + 1 ..], path);
    return resolved;
}

/// Resolve a full file path (directory + filename) for fixture loading.
/// Returns the absolute path; caller must free.
pub fn resolveFixtureFile(
    allocator: Allocator,
    io: Io,
    fixture_dir: []const u8,
    filename: []const u8,
) ![]u8 {
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ fixture_dir, filename });
    return resolveFixturePath(allocator, io, path);
}

/// Read a fixture file using resolved paths.
/// Same semantics as std.Io.Dir.cwd().readFileAlloc but works when the
/// binary runs from .zig-cache/o/...
pub fn readFixtureFile(
    allocator: Allocator,
    io: Io,
    fixture_dir: []const u8,
    filename: []const u8,
    limit: usize,
) ![]u8 {
    const resolved = try resolveFixtureFile(allocator, io, fixture_dir, filename);
    defer allocator.free(resolved);
    const cwd = Dir.cwd();
    return Dir.readFileAlloc(cwd, io, resolved, allocator, .limited(limit));
}

/// Read a fixture file given a full repo-relative path (e.g. "src/.../file.proto").
/// Same semantics as std.Io.Dir.cwd().readFileAlloc but works when the
/// binary runs from .zig-cache/o/...
pub fn readFixturePath(
    allocator: Allocator,
    io: Io,
    path: []const u8,
    limit: usize,
) ![]u8 {
    const resolved = try resolveFixturePath(allocator, io, path);
    defer allocator.free(resolved);
    const cwd = Dir.cwd();
    return Dir.readFileAlloc(cwd, io, resolved, allocator, .limited(limit));
}
