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
