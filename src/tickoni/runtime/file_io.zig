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

test "openFile handles absolute paths" {
    var tmp = std.Io.getStdTempDir(.{});
    defer tmp.cleanup();

    // Write a marker file so we can verify openFile can find it.
    var marker_path_buf: [256]u8 = undefined;
    const marker_path = try std.fmt.bufPrint(&marker_path_buf, "{s}/marker", .{tmp.dir.realpath(std.testing.io, ".") catch unreachable});
    var file = try std.Io.Dir.createFileAbsolute(std.testing.io, marker_path, .{});
    try file.writeAll(std.testing.io, "test");
    file.close(std.testing.io);

    // openFile should read it back.
    file = try openFile(std.testing.io, std.Io.Dir.cwd(), marker_path);
    defer file.close(std.testing.io);

    var buf: [4]u8 = undefined;
    const n = try file.readAll(std.testing.io, &buf);
    try std.testing.expectEqualStrings("test", buf[0..n]);
}

test "openFile handles relative paths" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    // Create a file with relative path.
    var file = try tmp.dir.createFile(std.testing.io, "rel", .{});
    try file.writeAll(std.testing.io, "rel_test");
    file.close(std.testing.io);

    // openFile should read it back.
    file = try openFile(std.testing.io, tmp.dir, "rel");
    defer file.close(std.testing.io);

    var buf: [8]u8 = undefined;
    const n = try file.readAll(std.testing.io, &buf);
    try std.testing.expectEqualStrings("rel_test", buf[0..n]);
}

test "createFile handles absolute paths" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const abs_path = try std.fmt.bufPrint(&path_buf, "{s}/abs_create", .{tmp.cwd.realpath(std.testing.io, ".") catch unreachable});

    var file = try createFile(std.testing.io, std.Io.Dir.cwd(), abs_path);
    try file.writeAll(std.testing.io, "abs_write");
    file.close(std.testing.io);

    // Verify the file exists and has the right content.
    file = try openFile(std.testing.io, std.Io.Dir.cwd(), abs_path);
    defer file.close(std.testing.io);

    var buf: [9]u8 = undefined;
    const n = try file.readAll(std.testing.io, &buf);
    try std.testing.expectEqualStrings("abs_write", buf[0..n]);
}

test "createFile handles relative paths" {
    var tmp = util.tmpDir();
    defer tmp.cleanup();

    var file = try createFile(std.testing.io, tmp.dir, "rel_create");
    try file.writeAll(std.testing.io, "rel_write");
    file.close(std.testing.io);

    // Verify.
    file = try openFile(std.testing.io, tmp.dir, "rel_create");
    defer file.close(std.testing.io);

    var buf: [9]u8 = undefined;
    const n = try file.readAll(std.testing.io, &buf);
    try std.testing.expectEqualStrings("rel_write", buf[0..n]);
}
