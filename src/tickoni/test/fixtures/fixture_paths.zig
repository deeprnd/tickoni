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
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) ![]u8 {
    if (std.mem.startsWith(u8, path, "src/")) {
        const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
        defer allocator.free(exe_dir);
        var current = std.fs.path.dirname(exe_dir) orelse return error.InvalidPath;
        var repo_root_path: ?[]u8 = null;
        defer {
            if (repo_root_path) |rp| allocator.free(rp);
        }
        for (0..20) |_| {
            var p: [1024]u8 = undefined;
            const path_str = try std.fmt.bufPrint(&p, "{s}/src", .{current});
            if (std.fs.cwd().access(path_str, .{})) {
                repo_root_path = try allocator.dupe(u8, current);
                break;
            }
            const next = std.fs.path.dirname(current);
            if (next == null) break;
            current = next.?;
        }
        const root = repo_root_path orelse return error.InvalidPath;
        const resolved = try allocator.alloc(u8, root.len + 1 + path.len);
        @memcpy(resolved[0 .. root.len], root);
        resolved[root.len] = '/';
        @memcpy(resolved[root.len + 1 ..], path);
        return resolved;
    }
    return allocator.dupe(u8, path);
}

/// Resolve a full file path (directory + filename) for fixture loading.
/// Returns the absolute path; caller must free.
pub fn resolveFixtureFile(
    allocator: std.mem.Allocator,
    io: std.Io,
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
    allocator: std.mem.Allocator,
    io: std.Io,
    fixture_dir: []const u8,
    filename: []const u8,
    limit: usize,
) ![]u8 {
    const resolved = try resolveFixtureFile(allocator, io, fixture_dir, filename);
    defer allocator.free(resolved);
    return std.fs.cwd().readFileAlloc(io, resolved, allocator, .limited(limit));
}

/// Read a fixture file given a full repo-relative path (e.g. "src/.../file.proto").
/// Same semantics as std.Io.Dir.cwd().readFileAlloc but works when the
/// binary runs from .zig-cache/o/...
pub fn readFixturePath(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    limit: usize,
) ![]u8 {
    const resolved = try resolveFixturePath(allocator, io, path);
    defer allocator.free(resolved);
    return std.fs.cwd().readFileAlloc(io, resolved, allocator, .limited(limit));
}
