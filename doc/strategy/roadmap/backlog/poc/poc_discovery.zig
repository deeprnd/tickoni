// Standalone POC: directory walker that returns files minus exclusions.
// Uses std.Io.Threaded for real file I/O in non-test code.
// Build & run with: zig build-exe poc_discovery.zig -O Debug && ./poc_discovery

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const FileEntry = struct {
    path: []const u8,
};

pub fn discoverFiles(
    allocator: Allocator,
    include_dirs: []const []const u8,
    exclude_prefixes: []const []const u8,
) Allocator.Error!std.ArrayList(FileEntry) {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var files: std.ArrayList(FileEntry) = .empty;
    errdefer files.deinit(allocator);

    const cwd = Io.Dir.cwd();

    for (include_dirs) |dir_name| {
        var dir = cwd.openDir(io, dir_name, .{ .iterate = true }) catch continue;
        defer dir.close(io);

        var walker = dir.walk(allocator) catch continue;
        defer walker.deinit();

        // walker.next(io) returns I/O errors (AccessDenied, Canceled, etc.)
        // We catch those locally; only Allocator.Error propagates
        while (true) {
            const maybe_entry = (walker.next(io)) catch continue;
            if (maybe_entry == null) break;

            const e = maybe_entry.?;
            if (e.kind != .file) continue;

            // Use e.path (relative path in walked dir) not e.basename (just filename)
            const ext = std.fs.path.extension(e.path);
            if (!std.mem.eql(u8, ext, ".zig")) continue;

            const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir_name, e.path });

            var excluded = false;
            for (exclude_prefixes) |prefix| {
                if (std.mem.startsWith(u8, full_path, prefix)) {
                    excluded = true;
                    break;
                }
            }
            if (excluded) {
                allocator.free(full_path);
                continue;
            }

            try files.append(allocator, .{ .path = full_path });
        }
    }

    return files;
}

pub fn main() anyerror!void {
    const allocator = std.heap.page_allocator;

    const includes = [_][]const u8{
        "src/tickoni/util/",
        "src/tickoni/runtime/",
        "src/tickoni/c_abi/",
        "src/tickoni/tiles/",
        "src/tickoni/test/mocks/",
        "src/tickoni/test/fixtures/",
    };
    const excludes = [_][]const u8{
        "src/tickoni/test/integration/",
        "src/tickoni/test/system/",
        "src/tickoni/test/fixture/",
        "src/tickoni/test/fixtures/investment/scenarios/.zig-global-cache",
    };

    var result = try discoverFiles(allocator, &includes, &excludes);
    defer result.deinit(allocator);

    std.debug.print("Discovered {d} files:\n", .{result.items.len});
    for (result.items) |f| {
        std.debug.print("  {s}\n", .{f.path});
    }

    // Verify: no excluded paths should appear
    for (result.items) |entry| {
        for (excludes) |excl| {
            if (std.mem.startsWith(u8, entry.path, excl)) {
                std.debug.print("FAIL: excluded path found: {s}\n", .{entry.path});
                return;
            }
        }
    }
    std.debug.print("\nAll exclusions verified OK.\n", .{});
}
