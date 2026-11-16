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
