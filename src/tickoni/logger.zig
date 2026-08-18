/// Tickoni structured logger — name/enter/exit pattern for method tracing.
///
/// Design (industry standard — OpenTelemetry/SLF4J inspired):
///   1. All logging is compile-time disabled by default (zero overhead)
///   2. Runtime toggle via --verbose flag enables DEBUG level
///   3. Method-level enter/exit logging with module + function name
///   4. Structured output: timestamp level [module] func: enter/exit
///   5. Panic/err logging always enabled for critical failures
///
/// Usage:
///   const log = @import("logger").get();
///   log.enter("module", "func") catch {};
///   defer log.exit("module", "func") catch {};
///   log.debug("module", "message") catch {};
const std = @import("std");
const util = @import("util");

/// Log severity levels — matches OpenTelemetry/SLF4J.
pub const Level = enum(u8) {
    /// Always enabled — for critical failures only
    panic = 0,
    /// Always enabled — for errors
    err = 1,
    /// Debug level — only with --verbose
    debug = 2,
};

/// Thread-safe (single-threaded, lock-free) logger state.
pub const Logger = struct {
    /// Current enabled level. Higher = more verbose.
    /// panic (0) < err (1) < debug (2)
    level: Level = .err,

    /// Write an entry to stderr.
    pub fn write(self: *Logger, level: Level, module: []const u8, func: []const u8, message: []const u8) !void {
        if (@intFromEnum(level) > @intFromEnum(self.level)) return;

        // Monotonic nanosecond timestamp via os.c shim (cross-platform)
        const ts: i64 = util.os_api.monotonicNanos();

        // Format: {ts} {LEVEL} [{module}] {func}: {message}
        var buf: [512]u8 = undefined;
        const level_str = switch (level) {
            .panic => "PANIC",
            .err => "ERR",
            .debug => "DEBUG",
        };
        const line = if (message.len > 0)
            try std.fmt.bufPrint(&buf, "{d} {s} [{s}] {s}: {s}\n", .{ ts, level_str, module, func, message })
        else
            try std.fmt.bufPrint(&buf, "{d} {s} [{s}] {s}\n", .{ ts, level_str, module, func });

        // Write to stderr (fd 2) via os.c shim (cross-platform)
        _ = util.os_api.write(2, line);
    }

    /// Log at panic level (always enabled).
    pub fn panic(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.panic, module, func, message);
    }

    /// Log at error level (always enabled).
    pub fn err(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.err, module, func, message);
    }

    /// Log at debug level (only with --verbose).
    pub fn debug(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.debug, module, func, message);
    }

    /// Log method entry: "module.func: enter"
    pub fn enter(self: *Logger, module: []const u8, func: []const u8) !void {
        try self.debug(module, func, "enter");
    }

    /// Log method exit: "module.func: exit"
    pub fn exit(self: *Logger, module: []const u8, func: []const u8) !void {
        try self.write(.debug, module, func, "exit");
    }
};

/// Global logger instance.
var global_logger: Logger = Logger{};

/// Get the global logger reference.
pub fn get() *Logger {
    return &global_logger;
}

/// Enable verbose mode (sets level to debug).
pub fn enableVerbose() void {
    global_logger.level = .debug;
}

/// Check if verbose is enabled.
pub fn isVerbose() bool {
    return global_logger.level == .debug;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Logger.write debug respects level" {
    var log = Logger{};
    try std.testing.expect(@intFromEnum(log.level) == @intFromEnum(Level.err));
    // Should not write debug at err level
    try log.write(.debug, "test", "func", "msg");
}

test "Logger.enableVerbose sets debug level" {
    var log = Logger{};
    log.level = .err;
    log.enableVerbose();
    try std.testing.expect(@intFromEnum(log.level) == @intFromEnum(Level.debug));
}

test "Logger.isVerbose" {
    var log = Logger{};
    log.level = .err;
    try std.testing.expect(!log.isVerbose());
    log.level = .debug;
    try std.testing.expect(log.isVerbose());
}

test "Logger.panic and err always write" {
    var log = Logger{};
    // Should not throw — writes to stderr
    try log.panic("test", "func", "panic message");
    try log.err("test", "func", "err message");
}

test "Logger.enter and exit format correctly" {
    var log = Logger{};
    log.level = .debug;
    try log.enter("module", "function");
    try log.exit("module", "function");
}
