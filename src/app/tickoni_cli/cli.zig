const std = @import("std");
const array_list = std.array_list;

/// Minimal CLI parser to replace clap 0.12.0 (incompatible with Zig 0.17).
pub const Parser = struct {
    const Self = @This();

    help: bool = false,
    version: u32 = 0,
    flags: Flags = .{},
    values: Values = .{},
    positionals: [][]const u8 = &.{},

    pub const Flags = struct {
        json: bool = false,
        plain: bool = false,
        fixture: bool = false,
    };

    pub const Values = struct {
        thesis: ?[]const u8 = null,
        endpoint: ?[]const u8 = null,
        model: ?[]const u8 = null,
    };
};

/// Parse args and return a Parser with resolved flags/values.
/// `init` is std.process.Init from main's entry point.
pub fn parse(gpa: std.mem.Allocator, init: std.process.Init) !Parser {
    var result = Parser{};
    var pos_start: usize = 0;

    // Collect args into an ArrayList
    var args_buf = array_list.Aligned([]const u8, null).initCapacity(gpa, 32) catch return result;
    defer args_buf.deinit(gpa);

    var raw_it = std.process.Args.iterate(init.minimal.args);
    while (true) {
        const entry = raw_it.next() orelse break;
        if (entry.len > 0) {
            try args_buf.append(gpa, entry);
        }
    }
    const args = try args_buf.toOwnedSlice(gpa);

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
            continue;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            const rest = arg[2..];
            const eq = std.mem.indexOfScalar(u8, rest, '=');
            const eq_idx = eq orelse rest.len;
            const key = rest[0..eq_idx];
            const value = if (eq_idx == rest.len) "" else rest[eq_idx + 1 ..];

            if (std.mem.eql(u8, key, "json")) {
                result.flags.json = true;
            } else if (std.mem.eql(u8, key, "plain")) {
                result.flags.plain = true;
            } else if (std.mem.eql(u8, key, "fixture")) {
                result.flags.fixture = true;
            } else if (std.mem.eql(u8, key, "thesis")) {
                if (value.len > 0) {
                    result.values.thesis = gpa.dupe(u8, value) catch continue;
                }
            } else if (std.mem.eql(u8, key, "endpoint")) {
                if (value.len > 0) {
                    result.values.endpoint = gpa.dupe(u8, value) catch continue;
                }
            } else if (std.mem.eql(u8, key, "model")) {
                if (value.len > 0) {
                    result.values.model = gpa.dupe(u8, value) catch continue;
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
            continue;
        }

        // Positional (after -- or non-flag)
    }

    // Collect positionals
    for (0..args.len) |j| {
        if (std.mem.eql(u8, args[j], "--")) {
            pos_start = j + 1;
            break;
        }
    }
    if (pos_start > 0) {
        result.positionals = args[pos_start..];
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
    try writer.writeAll("    demo        Run demo pipeline\n");
    try writer.writeAll("    version     Show version info\n");
    try writer.writeAll("    doctor      Run health checks\n");
    try writer.writeAll("\n");
    try writer.writeAll("GLOBAL OPTIONS:\n");
    try writer.writeAll("    -h, --help        Display this help and exit\n");
    try writer.writeAll("    -v, --version     Display version and exit\n");
    try writer.writeAll("\n");
    try std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, writer.buffered());

    _ = gpa;
}

/// Print help for a specific command.
pub fn printHelpForCommand(io: std.Io, gpa: std.mem.Allocator, command: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    if (std.mem.eql(u8, command, "demo")) {
        try writer.writeAll("USAGE:\n");
        try writer.writeAll("    tickoni demo investment [options]\n");
        try writer.writeAll("\n");
        try writer.writeAll("OPTIONS:\n");
        try writer.writeAll("    --thesis <str>    Plain-English demo thesis input\n");
        try writer.writeAll("    --endpoint <str>  OpenAI-compatible endpoint\n");
        try writer.writeAll("    --model <str>     Allowed model id\n");
        try writer.writeAll("    --json            Emit machine-readable JSON\n");
        try writer.writeAll("    --fixture         Use deterministic fixture response\n");
    } else if (std.mem.eql(u8, command, "doctor")) {
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

/// Free allocated strings in the parsed result.
pub fn deinit(self: *Parser, allocator: std.mem.Allocator) void {
    if (self.values.thesis) |t| allocator.free(t);
    if (self.values.endpoint) |e| allocator.free(e);
    if (self.values.model) |m| allocator.free(m);
}
