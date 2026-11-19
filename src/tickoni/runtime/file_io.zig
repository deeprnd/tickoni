/// Generic file I/O helpers for Tickoni's binary serialization.
///
/// Zig 0.17's std.Io.Dir.{openFile,createFile} treat absolute paths
/// (starting with '/') as relative to the supplied Dir.  Use the
/// helpers below to get true filesystem-root resolution when needed.
const std = @import("std");
const util = @import("util");

/// Open a file for reading.  Absolute sub_paths go through
/// openFileAbsolute; relative ones go through dir.openFile.
pub fn openFile(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
) !std.Io.File {
    if (sub_path.len > 0 and sub_path[0] == '/')
        return std.Io.Dir.openFileAbsolute(io, sub_path, .{});
    return dir.openFile(io, sub_path, .{});
}

/// Create (or truncate) a file for writing.  Absolute sub_paths go
/// through createFileAbsolute; relative ones go through dir.createFile.
pub fn createFile(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
) !std.Io.File {
    if (sub_path.len > 0 and sub_path[0] == '/')
        return std.Io.Dir.createFileAbsolute(io, sub_path, .{});
    return dir.createFile(io, sub_path, .{});
}

/// Create (or truncate) a file that only its owner can read or write (0600 where
/// the platform has POSIX modes), for files that hold captured replay material.
/// The mode is also applied to a file that already existed, so a stale file with
/// wider access is narrowed rather than reused as it was.
pub fn createOwnerOnlyFile(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
) !std.Io.File {
    const Permissions = std.Io.File.Permissions;
    const owner_only: Permissions = if (@hasDecl(Permissions, "fromMode")) Permissions.fromMode(0o600) else .default_file;
    var file = if (sub_path.len > 0 and sub_path[0] == '/')
        try std.Io.Dir.createFileAbsolute(io, sub_path, .{ .permissions = owner_only })
    else
        try dir.createFile(io, sub_path, .{ .permissions = owner_only });
    errdefer file.close(io);
    try file.setPermissions(io, owner_only);
    return file;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// These exercise the absolute-vs-relative branch in each helper, which is the
// whole reason the module exists (see the module doc). They use util.tmpDir()
// and the positional read/write API, matching the rest of the runtime tests.

/// Absolute path of a TmpDir, for the absolute-path branches below.
fn tmpRealPath(tmp: *util.TmpDir, buf: []u8) ![]const u8 {
    const len = try tmp.dir.realPath(std.testing.io, buf);
    return buf[0..len];
}

test "openFile resolves an absolute path against the filesystem root" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmpRealPath(&tmp, &dir_buf);

    var marker_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const marker_path = try std.fmt.bufPrint(&marker_path_buf, "{s}/marker", .{dir_path});

    var file = try std.Io.Dir.createFileAbsolute(std.testing.io, marker_path, .{});
    try file.writePositionalAll(std.testing.io, "test", 0);
    file.close(std.testing.io);

    // cwd is deliberately unrelated to marker_path: only root resolution finds it.
    var read_back = try openFile(std.testing.io, std.Io.Dir.cwd(), marker_path);
    defer read_back.close(std.testing.io);

    var buf: [4]u8 = undefined;
    const n = try read_back.readPositionalAll(std.testing.io, &buf, 0);
    try std.testing.expectEqualStrings("test", buf[0..n]);
}

test "openFile resolves a relative path against the supplied dir" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var file = try tmp.dir.createFile(std.testing.io, "rel", .{});
    try file.writePositionalAll(std.testing.io, "rel_test", 0);
    file.close(std.testing.io);

    var read_back = try openFile(std.testing.io, tmp.dir, "rel");
    defer read_back.close(std.testing.io);

    var buf: [8]u8 = undefined;
    const n = try read_back.readPositionalAll(std.testing.io, &buf, 0);
    try std.testing.expectEqualStrings("rel_test", buf[0..n]);
}

test "createFile resolves an absolute path against the filesystem root" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try tmpRealPath(&tmp, &dir_buf);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&path_buf, "{s}/abs_create", .{dir_path});

    var file = try createFile(std.testing.io, std.Io.Dir.cwd(), abs_path);
    try file.writePositionalAll(std.testing.io, "abs_write", 0);
    file.close(std.testing.io);

    // Reading it back through tmp.dir by its bare name proves createFile wrote
    // to the absolute location, not to a path under cwd.
    var read_back = try openFile(std.testing.io, tmp.dir, "abs_create");
    defer read_back.close(std.testing.io);

    var buf: [9]u8 = undefined;
    const n = try read_back.readPositionalAll(std.testing.io, &buf, 0);
    try std.testing.expectEqualStrings("abs_write", buf[0..n]);
}

test "createFile resolves a relative path against the supplied dir" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var file = try createFile(std.testing.io, tmp.dir, "rel_create");
    try file.writePositionalAll(std.testing.io, "rel_write", 0);
    file.close(std.testing.io);

    var read_back = try openFile(std.testing.io, tmp.dir, "rel_create");
    defer read_back.close(std.testing.io);

    var buf: [9]u8 = undefined;
    const n = try read_back.readPositionalAll(std.testing.io, &buf, 0);
    try std.testing.expectEqualStrings("rel_write", buf[0..n]);
}

test "createOwnerOnlyFile makes the file readable and writable by its owner only" {
    if (!@hasDecl(std.Io.File.Permissions, "toMode")) return error.SkipZigTest;
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    // A file that already exists with wide access is narrowed, not reused as is.
    var wide = try tmp.dir.createFile(std.testing.io, "stale", .{ .permissions = std.Io.File.Permissions.fromMode(0o666) });
    try wide.setPermissions(std.testing.io, std.Io.File.Permissions.fromMode(0o666));
    wide.close(std.testing.io);

    inline for (.{ "fresh", "stale" }) |name| {
        var file = try createOwnerOnlyFile(std.testing.io, tmp.dir, name);
        try file.writePositionalAll(std.testing.io, "capture", 0);
        const stat = try file.stat(std.testing.io);
        file.close(std.testing.io);
        try std.testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
    }
}
