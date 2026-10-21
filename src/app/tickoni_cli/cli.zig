const std = @import("std");
const array_list = std.array_list;

/// Minimal CLI parser to replace clap 0.12.0 (incompatible with Zig 0.17).
pub const Parser = struct {
    const Self = @This();

    help: bool = false,
    version: u32 = 0,
    flags: Flags = .{},
    values: Values = .{},
    positionals: []const []const u8 = &.{},

    pub const Flags = struct {
        json: bool = false,
        plain: bool = false,
        manifest: bool = false,
    };

    pub const Values = struct {
        thesis: ?[]const u8 = null,
        endpoint: ?[]const u8 = null,
        model: ?[]const u8 = null,
        manifest: ?[]const u8 = null,
    };

    /// Free allocated strings in the parsed result.
    pub fn deinit(self: *Parser, allocator: std.mem.Allocator) void {
        if (self.values.thesis) |t| allocator.free(t);
        if (self.values.endpoint) |e| allocator.free(e);
        if (self.values.model) |m| allocator.free(m);
        if (self.values.manifest) |m| allocator.free(m);
    }
};

/// Parse args and return a Parser with resolved flags/values.
/// `init` is std.process.Init from main's entry point.
pub fn parse(gpa: std.mem.Allocator, init: std.process.Init) !Parser {
    var raw_it = try std.process.Args.iterateAllocator(init.minimal.args, gpa);
    defer raw_it.deinit();

    var args_buf = array_list.Aligned([]const u8, null).initCapacity(gpa, 32) catch return .{};
    defer args_buf.deinit(gpa);

    while (true) {
        const entry = raw_it.next() orelse break;
        if (entry.len > 0) {
            try args_buf.append(gpa, entry);
        }
    }
    const args = try args_buf.toOwnedSlice(gpa);
    return parseFromSlice(gpa, args);
}

/// Core parsing logic — used by both parse() and unit tests.
/// `gpa` is used for allocating value strings (thesis, endpoint, etc.).
/// `args` is the input slice; positionals always point into it.
fn parseFromSlice(gpa: std.mem.Allocator, args: []const []const u8) Parser {
    var result = Parser{};
    var pos_start: usize = 0;
    var pos_end: usize = 0;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
            break;
        }
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = 1;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            pos_start = i + 1;
            pos_end = args.len;
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            // Long flag — end positionals if we've started them
            if (pos_start > 0 and pos_end == 0) {
                pos_end = i;
            }
            const rest = arg[2..];
            const eq = std.mem.indexOfScalar(u8, rest, '=');
            const eq_idx = eq orelse rest.len;
            const key = rest[0..eq_idx];
            const value = if (eq_idx == rest.len) "" else rest[eq_idx + 1 ..];

            if (std.mem.eql(u8, key, "json")) {
                result.flags.json = true;
            } else if (std.mem.eql(u8, key, "plain")) {
                result.flags.plain = true;
            } else if (std.mem.eql(u8, key, "thesis")) {
                var val = value;
                if (val.len == 0 and i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    val = args[i + 1];
                    i += 1;
                }
                if (val.len > 0) {
                    result.values.thesis = gpa.dupe(u8, val) catch continue;
                }
            } else if (std.mem.eql(u8, key, "endpoint")) {
                var val = value;
                if (val.len == 0 and i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    val = args[i + 1];
                    i += 1;
                }
                if (val.len > 0) {
                    result.values.endpoint = gpa.dupe(u8, val) catch continue;
                }
            } else if (std.mem.eql(u8, key, "model")) {
                var val = value;
                if (val.len == 0 and i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    val = args[i + 1];
                    i += 1;
                }
                if (val.len > 0) {
                    result.values.model = gpa.dupe(u8, val) catch continue;
                }
            } else if (std.mem.eql(u8, key, "manifest")) {
                var val = value;
                if (val.len == 0 and i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                    val = args[i + 1];
                    i += 1;
                }
                if (val.len > 0) {
                    result.values.manifest = gpa.dupe(u8, val) catch continue;
                }
            }
            continue;
        }

        // Short flags (only -h supported)
        if (std.mem.startsWith(u8, arg, "-") and arg.len == 2 and arg[1] != '-') {
            if (std.mem.eql(u8, arg, "-h")) {
                result.help = true;
                break;
            }
            if (pos_start > 0 and pos_end == 0) {
                pos_end = i;
            }
            continue;
        }

        // Positional: non-flag arg after index 0 (skip program name)
        if (i > 0) {
            if (pos_start == 0) {
                pos_start = i;
            }
            pos_end = i + 1;
        }
    }

    // If positionals started but never ended, extend to end
    if (pos_start > 0 and pos_end == 0) {
        pos_end = args.len;
    }

    if (pos_start > 0) {
        result.positionals = args[pos_start..pos_end];
    }

    return result;
}

/// Print help text to stdout.
pub fn printHelp(io: std.Io, gpa: std.mem.Allocator) !void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writer.writeAll("tickoni - AI harness for agentic finance\n");
    try writer.writeAll("\n");
    try writer.writeAll("USAGE:\n");
    try writer.writeAll("    tickoni <command> [options]\n");
    try writer.writeAll("\n");
    try writer.writeAll("COMMANDS:\n");
    try writer.writeAll("    version     Show version info\n");
    try writer.writeAll("    doctor      Run health checks\n");
    try writer.writeAll("\n");
    try writer.writeAll("GLOBAL OPTIONS:\n");
    try writer.writeAll("    -h, --help        Display this and exit\n");
    try writer.writeAll("    -v, --version     Display version and exit\n");
    try writer.writeAll("\n");
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());

    _ = gpa;
}

/// Print help for a specific command.
pub fn printHelpForCommand(io: std.Io, gpa: std.mem.Allocator, command: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    if (std.mem.eql(u8, command, "doctor")) {
        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    tickoni doctor [options]\n");
        try writer.writeAll("\n");
        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    --json   Emit machine-readable JSON\n");
        try writer.writeAll("    --plain  Emit human-readable text output\n");
    }
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());

    _ = gpa;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Build a Parser from a slice of string args using an arena allocator.
/// The caller must keep the arena alive while accessing `result.positionals`
/// and MUST NOT call `result.deinit()` — arena cleanup handles everything.
fn makeParseArgs(args: []const []const u8, gpa: std.mem.Allocator) !struct {
    result: Parser,
    arena: std.heap.ArenaAllocator,
} {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const arena_gpa = arena.allocator();
    const args_buf = try arena_gpa.dupe([]const u8, args);
    const result = parseFromSlice(arena_gpa, args_buf);
    return .{ .result = result, .arena = arena };
}

/// Build a Parser from a slice of string args using the real allocator.
/// Caller must call `result.deinit(allocator)` and `gpa.free(args_buf)`.
fn makeParseArgsWithDeinit(args: []const []const u8, gpa: std.mem.Allocator) !Parser {
    const args_buf = try gpa.dupe([]const u8, args);
    const result = parseFromSlice(gpa, args_buf);
    return result;
}

test "parse --help flag" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--help" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.help);
    try std.testing.expectEqual(@as(u32, 0), parsed.result.version);
    try std.testing.expectEqual(@as(usize, 0), parsed.result.positionals.len);
}

test "parse -h flag" {
    var parsed = try makeParseArgs(&.{ "tickoni", "-h" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.help);
    try std.testing.expectEqual(@as(u32, 0), parsed.result.version);
}

test "parse -v flag" {
    var parsed = try makeParseArgs(&.{ "tickoni", "-v" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.result.version);
    try std.testing.expect(!parsed.result.help);
}

test "parse --version flag" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--version" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.result.version);
    try std.testing.expect(!parsed.result.help);
}

test "parse unknown command" {
    var parsed = try makeParseArgs(&.{ "tickoni", "foobar" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.result.positionals.len);
    try std.testing.expectEqualStrings("foobar", parsed.result.positionals[0]);
}

test "parse bare invocation" {
    var parsed = try makeParseArgs(&.{ "tickoni" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(!parsed.result.help);
    try std.testing.expectEqual(@as(u32, 0), parsed.result.version);
    try std.testing.expectEqual(@as(usize, 0), parsed.result.positionals.len);
}

test "parse version command" {
    var parsed = try makeParseArgs(&.{ "tickoni", "version" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.result.positionals.len);
    try std.testing.expectEqualStrings("version", parsed.result.positionals[0]);
}

test "parse doctor --plain" {
    var parsed = try makeParseArgs(&.{ "tickoni", "doctor", "--plain" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.result.positionals.len);
    try std.testing.expectEqualStrings("doctor", parsed.result.positionals[0]);
    try std.testing.expect(parsed.result.flags.plain);
    try std.testing.expect(!parsed.result.flags.json);
}

test "parse doctor --json" {
    var parsed = try makeParseArgs(&.{ "tickoni", "doctor", "--json" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.result.positionals.len);
    try std.testing.expectEqualStrings("doctor", parsed.result.positionals[0]);
    try std.testing.expect(parsed.result.flags.json);
    try std.testing.expect(!parsed.result.flags.plain);
}

test "parse --thesis=macro (equals)" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--thesis=macro" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.values.thesis != null);
    try std.testing.expectEqualStrings("macro", parsed.result.values.thesis.?);
}

test "parse --thesis macro (space)" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--thesis", "macro" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.values.thesis != null);
    try std.testing.expectEqualStrings("macro", parsed.result.values.thesis.?);
}

test "parse --endpoint=value" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--endpoint=http://local" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqualStrings("http://local", parsed.result.values.endpoint.?);
}

test "parse --model=value" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--model=gemma4" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqualStrings("gemma4", parsed.result.values.model.?);
}

test "parse --manifest=value" {
    var parsed = try makeParseArgs(&.{
        "tickoni", "--manifest=/path/to/manifest",
    }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqualStrings("/path/to/manifest", parsed.result.values.manifest.?);
}

test "parse deinit frees thesis" {
    const args = &.{ "tickoni", "--thesis=test" };
    const gpa = std.testing.allocator;
    const args_buf = try gpa.dupe([]const u8, args);
    var result = parseFromSlice(gpa, args_buf);
    try std.testing.expect(result.values.thesis != null);
    const thesis_before = result.values.thesis.?;
    result.deinit(gpa);
    // Verify thesis memory was freed (leak detection via std.testing.allocator)
    _ = thesis_before;
    gpa.free(args_buf);
}

test "parse short -h wins" {
    var parsed = try makeParseArgs(&.{
        "tickoni", "-h", "--version", "doctor",
    }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.help);
    try std.testing.expectEqual(@as(u32, 0), parsed.result.version); // -h short-circuits, version stays 0
}

test "parse double dash separator" {
    var parsed = try makeParseArgs(&.{
        "tickoni", "--", "version", "doctor",
    }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.result.positionals.len);
    try std.testing.expectEqualStrings("version", parsed.result.positionals[0]);
    try std.testing.expectEqualStrings("doctor", parsed.result.positionals[1]);
}

test "parse empty string values" {
    var parsed = try makeParseArgs(&.{ "tickoni", "--thesis=" }, std.testing.allocator);
    defer parsed.arena.deinit();
    try std.testing.expect(parsed.result.values.thesis == null);
}
