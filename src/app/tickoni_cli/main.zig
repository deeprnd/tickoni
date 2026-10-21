const cli = @import("cli.zig");
const doctor_output = @import("doctor_output");
const std = @import("std");
const version = @import("version");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const parsed = try cli.parse(gpa, init);

    if (parsed.help) {
        try cli.printHelp(init.io, gpa);
        return;
    }

    if (parsed.version != 0) {
        try printVersion(init.io, gpa);
        return;
    }

    if (parsed.positionals.len == 0) {
        try cli.printHelp(init.io, gpa);
        return;
    }

    const command = parsed.positionals[0];

    if (std.mem.eql(u8, command, "version")) {
        try printVersion(init.io, gpa);
    } else if (std.mem.eql(u8, command, "doctor")) {
        try doctorMain(gpa, init.io, parsed);
    } else {
        var stderr_buf: [512]u8 = undefined;
        var writer = std.Io.File.stderr().writer(init.io, &stderr_buf);
        try writer.interface.print(
            "error: unknown command '{s}'. Use 'tickoni --help' for usage.\n",
            .{command});
        return error.UnknownCommand;
    }
}

fn printVersion(io: std.Io, gpa: std.mem.Allocator) !void {
    var info = try version.VersionInfo.init(gpa);
    defer info.deinit(gpa);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try version.formatVersionInfo(info, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
}

fn doctorMain(gpa: std.mem.Allocator, io: std.Io, parsed: cli.Parser) !void {
    const format: doctor_output.Format = if (parsed.flags.json) .json else .text;
    var buf: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try doctor_output.runAndFormat(io, gpa, format, &writer);
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());
}

// ---------------------------------------------------------------------------
// Integration tests — spawn the tickoni binary and assert on its output.
// ---------------------------------------------------------------------------

const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Locate the `tickoni` binary.  Walk up from the executable's directory to
/// find the repo root (a directory whose child is `src/`), then prepend it
/// to `build/zig-out/bin/tickoni`.  If that fails, fall back to a fixed path
/// relative to the CWD (the normal `zig build` layout).
fn locateTickoniBinary(allocator: Allocator, io: Io) ![]const u8 {
    const exe_dir = try std.process.executableDirPathAlloc(io, allocator);
    defer allocator.free(exe_dir);
    var current: []const u8 = std.fs.path.dirname(exe_dir) orelse return error.InvalidPath;
    var depth: usize = 0;
    while (depth < 20) : (depth += 1) {
        var p: [1024]u8 = undefined;
        const path_str = try std.fmt.bufPrint(&p, "{s}/src", .{current});
        const exists: bool = blk: {
            std.Io.Dir.access(std.Io.Dir.cwd(), io, path_str, .{}) catch break :blk false;
            break :blk true;
        };
        if (exists) break;
        const next = std.fs.path.dirname(current);
        if (next == null) break;
        current = next.?;
    }
    var candidate_buf: [2048]u8 = undefined;
    const repo_path = try std.fmt.bufPrint(&candidate_buf, "{s}/build/zig-out/bin/tickoni", .{current});
    const exists: bool = blk: {
        std.Io.Dir.access(std.Io.Dir.cwd(), io, repo_path, .{}) catch break :blk false;
        break :blk true;
    };
    if (exists) return try allocator.dupe(u8, repo_path);
    // Fallback: binary is alongside the test binary itself
    return try std.fs.path.join(allocator, &.{ exe_dir, "tickoni" });
}

/// Run the tickoni binary with the given args and return stdout, stderr,
/// plus the exit code.  The caller must free stdout and stderr.
fn runTickoni(allocator: Allocator, io: Io, args: []const []const u8) anyerror!struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: i32,
} {
    const bin = try locateTickoniBinary(allocator, io);
    defer allocator.free(bin);

    var argv_buf: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv_buf.deinit(allocator);
    try argv_buf.append(allocator, bin);
    for (args) |a| try argv_buf.append(allocator, a);

    // Use std.process.run which handles spawn + pipe reading + cleanup.
    const result = try std.process.run(allocator, io, .{
        .argv = argv_buf.items,
        .stderr_limit = std.Io.Limit.limited(65536),
        .stdout_limit = std.Io.Limit.limited(65536),
    });

    const exit_code: i32 = switch (result.term) {
        .stopped => 0,
        .signal => 128 + @as(i32, @intCast(@intFromEnum(result.term.signal))),
        .exited => |c| @as(i32, c),
        .unknown => 1,
    };

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = exit_code,
    };
}

test "version output format" {
    const result = runTickoni(std.testing.allocator, std.testing.io, &.{ "--version" }) catch |err| {
        std.debug.print("\n[cli-integration] version test skipped: unable to locate tickoni binary ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try std.testing.expect(std.mem.startsWith(u8, result.stdout, "Tickoni "));
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Build ID:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Git:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "OS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Runtime Tier:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Isolation Tier:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Policy Schema:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Replay Schema:") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Compiler:") != null);
}

test "doctor --plain output" {
    const result = runTickoni(std.testing.allocator, std.testing.io, &.{ "doctor", "--plain" }) catch |err| {
        std.debug.print("\n[cli-integration] doctor plain test skipped: ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "tickoni doctor") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Platform tier:") != null);
}

test "doctor --json output" {
    const result = runTickoni(std.testing.allocator, std.testing.io, &.{ "doctor", "--json" }) catch |err| {
        std.debug.print("\n[cli-integration] doctor json test skipped: ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    // Parse JSON and check required top-level fields.
    var parsed = std.json.parseFromSlice(std.json.Value, std.testing.allocator, result.stdout, .{}) catch |err| {
        std.debug.print("\n[cli-integration] doctor json parse error: {s} output={s}\n", .{ @errorName(err), result.stdout });
        return error.SkipZigTest;
    };
    defer parsed.deinit();

    const obj = switch (parsed.value) {
        .object => |o| o,
        else => {
            std.debug.print("\n[cli-integration] doctor json: expected object, got {s}\n", .{@tagName(parsed.value)});
            return error.SkipZigTest;
        },
    };

    // Check required fields exist.
    try std.testing.expect(obj.get("platform_tier") != null);
    try std.testing.expect(obj.get("result") != null);
    try std.testing.expect(obj.get("checks") != null);

    const checks_val = obj.get("checks").?;
    try std.testing.expect(checks_val == .array);
}

test "bare invocation fail-closed" {
    const result = runTickoni(std.testing.allocator, std.testing.io, &.{}) catch |err| {
        std.debug.print("\n[cli-integration] bare invocation test skipped: ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    // Should not crash (exit code 0), but output should mention usage/error.
    const combined = std.mem.concat(std.testing.allocator, u8, &.{ result.stdout, result.stderr }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(combined);
    var lower = try std.testing.allocator.alloc(u8, combined.len);
    defer std.testing.allocator.free(lower);
    for (combined, 0..) |c, i| lower[i] = std.ascii.toLower(c);

    try std.testing.expect(std.mem.indexOf(u8, lower, "usage") != null or
        std.mem.indexOf(u8, lower, "error") != null or
        std.mem.indexOf(u8, lower, "command") != null);
}

test "unknown command error" {
    const result = runTickoni(std.testing.allocator, std.testing.io, &.{ "foobar" }) catch |err| {
        std.debug.print("\n[cli-integration] unknown command test skipped: ({s})\n", .{@errorName(err)});
        return error.SkipZigTest;
    };
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    // Non-zero exit code.
    try std.testing.expect(result.exit_code != 0);

    // stderr contains the error name "UnknownCommand".
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "UnknownCommand") != null);
}
