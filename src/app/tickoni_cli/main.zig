const cli = @import("cli.zig");
const demo = @import("investment_demo");
const doctor_output = @import("doctor_output");
const std = @import("std");
const version = @import("version");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const parsed = cli.parse(gpa, init);

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

    if (std.mem.eql(u8, command, "demo")) {
        try demoMain(gpa, init.io, parsed);
    } else if (std.mem.eql(u8, command, "version")) {
        try printVersion(init.io, gpa);
    } else if (std.mem.eql(u8, command, "doctor")) {
        try doctorMain(gpa, init.io, parsed);
    } else {
        try std.Io.File.stderr().writer(init.io, undefined).writeAll(
            "error: unknown command '{}'. Use 'tickoni --help' for usage.\n",
            .{command},
        );
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

fn demoMain(gpa: std.mem.Allocator, io: std.Io, parsed: cli.Parser) !void {
    if (parsed.positionals.len < 2) {
        try cli.printHelpForCommand(io, gpa, "demo");
        return;
    }

    const subcommand = parsed.positionals[1];

    if (std.mem.eql(u8, subcommand, "investment")) {
        const thesis_text = parsed.values.thesis orelse
            return error.MissingThesis;

        const endpoint = if (parsed.values.endpoint) |value|
            value
        else
            try demo.envOrDefault(gpa, "TK_LLM_ENDPOINT", demo.default_endpoint);
        defer gpa.free(endpoint);

        const model_id = if (parsed.values.model) |value|
            value
        else
            try demo.envOrDefault(gpa, "TK_LLM_MODEL_ID", demo.default_model_id);
        defer gpa.free(model_id);

        var report = try demo.runCliDemo(gpa, io, .{
            .endpoint = endpoint,
            .model_id = model_id,
            .use_fixture = parsed.flags.fixture,
        }, thesis_text);
        defer report.deinit(gpa);

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
        if (parsed.flags.json) {
            try demo.writeCliReportJson(gpa, &stdout_writer.interface, report);
        } else {
            try demo.writeCliReportText(&stdout_writer.interface, report);
        }
        try stdout_writer.flush();
    } else {
        try std.Io.File.stderr().writeAll(io, std.Io.File.writeOptions{},
            "error: unknown demo subcommand '{}'. Use 'tickoni demo --help'.\n",
            .{subcommand});
        return error.UnknownDemoSubcommand;
    }
}
