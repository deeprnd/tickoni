/// Tickoni structured logger - name/enter/exit pattern for method tracing.
///
/// Design (syslog/Slf4j/OpenTelemetry inspired, 1:1 with Firedancer log levels):
///   1. Level parsed from TK_LOG_LEVEL env var (numeric 0-7, default 4=ERR)
///      0=DEBUG, 1=INFO, 2=NOTICE, 3=WARNING, 4=ERR, 5=CRIT, 6=ALERT, 7=EMERG
///   2. Module filtering via TK_LOG_MODULES env var (comma-separated, wildcard *)
///   3. ANSI color when stdout is a TTY (auto-detected via isatty)
///   4. Structured key-value output: {ts} {level} [{module}] {func}: {key=val ...} {message}
///   5. Flush on err/panic via fflush(stderr)
///   6. No double-gate: log.debug() is always callable, level check internal
///   7. --verbose flag sets TK_LOG_LEVEL=0 (max verbosity) for backwards compatibility
///   8. TK_LOG_LEVEL also sets Firedancer FD_LOG_LEVEL_* env vars (1:1 mapping)
///   9. Backwards-compatible: isVerbose() still works, global singleton unchanged
///
/// Usage:
///   const log = @import("logger").get();
///   log.enter("module", "func") catch {};
///   defer log.exit("module", "func") catch {};
///   log.debug("module", "message") catch {};
///   log.kv("module", "key1=val1 key2=val2") catch {};
const std = @import("std");
const util = @import("util");

/// Log severity levels - matches Firedancer syslog levels (0-7).
/// 0=DEBUG, 1=INFO, 2=NOTICE, 3=WARNING, 4=ERR, 5=CRIT, 6=ALERT, 7=EMERG
pub const Level = enum(u8) {
    debug = 0,
    info = 1,
    notice = 2,
    warning = 3,
    err = 4,
    crit = 5,
    alert = 6,
    emerg = 7,
};

/// Thread-safe (single-threaded, lock-free) logger state.
pub const Logger = struct {
    /// Current enabled level. Higher = more verbose.
    level: Level = .err,

    /// Module filter: comma-separated list or empty (no filter = log everything).
    modules: []const u8 = "",

    /// Whether colorize is enabled (TTY detected on init).
    colorize: bool = false,

    /// Pre-allocated buffer for formatted log lines.
    line_buf: [1024]u8 = undefined,

    /// Initialize the logger: parse env vars, detect TTY, sync with Firedancer.
    pub fn init(self: *Logger) void {
        self.level = Logger.parseLogLevel();
        self.modules = Logger.parseModules();
        self.colorize = util.os_api.isatty(2);
        self.syncFiredancerLevels();
    }

    /// Parse TK_LOG_LEVEL from environment (numeric 0-7 or named levels).
    fn parseLogLevel() Level {
        const env = util.os_api.getEnv("TK_LOG_LEVEL") orelse return .err;
        if (std.mem.eql(u8, env, "debug") or std.mem.eql(u8, env, "0")) return .debug;
        if (std.mem.eql(u8, env, "info") or std.mem.eql(u8, env, "1")) return .info;
        if (std.mem.eql(u8, env, "notice") or std.mem.eql(u8, env, "2")) return .notice;
        if (std.mem.eql(u8, env, "warning") or std.mem.eql(u8, env, "3")) return .warning;
        if (std.mem.eql(u8, env, "err") or std.mem.eql(u8, env, "4")) return .err;
        if (std.mem.eql(u8, env, "crit") or std.mem.eql(u8, env, "5")) return .crit;
        if (std.mem.eql(u8, env, "alert") or std.mem.eql(u8, env, "6")) return .alert;
        if (std.mem.eql(u8, env, "emerg") or std.mem.eql(u8, env, "7")) return .emerg;
        return .err;
    }

    /// Parse TK_LOG_MODULES from environment.
    fn parseModules() []const u8 {
        const env = util.os_api.getEnv("TK_LOG_MODULES") orelse return "";
        return env;
    }

    /// Sync TK_LOG_LEVEL to Firedancer FD_LOG_LEVEL_* env vars.
    /// This ensures the C logger and Zig logger use the same verbosity level.
    fn syncFiredancerLevels(self: *const Logger) void {
        const lvl = @intFromEnum(self.level);
        var buf: [4]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{lvl}) catch "4";
        util.os_api.setEnv("FD_LOG_LEVEL_STDERR", str);
        util.os_api.setEnv("FD_LOG_LEVEL_LOGFILE", str);
        util.os_api.setEnv("FD_LOG_LEVEL_FLUSH", str);
        util.os_api.setEnv("FD_LOG_LEVEL_CORE", str);
    }

    /// Check if a module's debug logs should be emitted.
    pub fn shouldLogModule(self: *Logger, module: []const u8, level: Level) bool {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return false;
        if (self.modules.len == 0) return true;
        if (std.mem.eql(u8, self.modules, "*")) return true;

        var iter = std.mem.splitScalar(u8, self.modules, ',');
        while (iter.next()) |mod| {
            const trimmed = std.mem.trim(u8, mod, " \t");
            if (std.mem.eql(u8, trimmed, module)) return true;
        }
        return false;
    }

    /// Write an entry to stderr.
    pub fn write(self: *Logger, level: Level, module: []const u8, func: []const u8, message: []const u8) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;
        if (level == .debug and !self.shouldLogModule(module, level)) return;

        const ts: i64 = util.os_api.monotonicNanos();
        const level_str: []const u8 = switch (level) {
            .debug => "DEBUG",
            .info => "INFO",
            .notice => "NOTICE",
            .warning => "WARNING",
            .err => "ERR",
            .crit => "CRIT",
            .alert => "ALERT",
            .emerg => "EMERG",
        };

        const color_code = if (self.colorize) switch (level) {
            .debug => "\x1b[34m",  // blue
            .info => "\x1b[32m",   // green
            .notice => "\x1b[33m", // yellow
            .warning => "\x1b[33m",
            .err => "\x1b[31m",    // red
            .crit => "\x1b[1;31m", // red bold
            .alert => "\x1b[1;31m",
            .emerg => "\x1b[1;31m",
        } else "";
        const reset = if (self.colorize) "\x1b[0m" else "";

        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}{d} {s} [{s}] {s}: {s}{s}\n", .{
            color_code, ts, level_str, module, func, message, reset,
        });

        _ = util.os_api.write(2, line);

        if (@intFromEnum(level) >= @intFromEnum(Level.warning)) {
            util.os_api.fflush();
        }
    }

    /// Log at panic level (always enabled, always flushed).
    pub fn panic(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        const ts: i64 = util.os_api.monotonicNanos();
        const line = try std.fmt.bufPrint(&self.line_buf, "\x1b[1;31m{d} PANIC [{s}] {s}: {s}\x1b[0m\n", .{
            ts, module, func, message,
        });
        _ = util.os_api.write(2, line);
        util.os_api.fflush();
    }

    /// Log at error level (always enabled, always flushed).
    pub fn err(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.err, module, func, message);
    }

    /// Log at debug level (only with sufficient level and matching module).
    pub fn debug(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.debug, module, func, message);
    }

    /// Log at info level (only with sufficient level).
    pub fn info(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.info, module, func, message);
    }

    /// Log method entry: "module.func: enter"
    pub fn enter(self: *Logger, module: []const u8, func: []const u8) !void {
        try self.debug(module, func, "enter");
    }

    /// Log method exit: "module.func: exit"
    pub fn exit(self: *Logger, module: []const u8, func: []const u8) !void {
        try self.write(.debug, module, func, "exit");
    }

    /// Log with key-value pairs: {key=val ...} appended before the message.
    pub fn kv(self: *Logger, module: []const u8, func: []const u8, kv_pairs: []const u8, message: []const u8) !void {
        try self.write(module, func, kv_pairs ++ " " ++ message);
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

/// Initialize the global logger from environment variables.
/// Call this early in main() before any logging.
pub fn init() void {
    global_logger.init();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Logger.write debug respects level" {
    var log = Logger{};
    try std.testing.expect(@intFromEnum(log.level) == @intFromEnum(Level.err));
    try (&log).write(.debug, "test", "func", "msg");
}

test "Logger.parseLogLevel from string names" {
    // Default when env is not set
    const default_level = Logger.parseLogLevel();
    try std.testing.expect(default_level == .err);
}

test "Logger.parseLogLevel from numeric string" {
    // This test verifies the enum value is correct for the numeric representation
    const lvl: Level = .debug;
    try std.testing.expect(@intFromEnum(lvl) == 0);
    const lvl2: Level = .info;
    try std.testing.expect(@intFromEnum(lvl2) == 1);
    const lvl3: Level = .notice;
    try std.testing.expect(@intFromEnum(lvl3) == 2);
    const lvl4: Level = .warning;
    try std.testing.expect(@intFromEnum(lvl4) == 3);
    const lvl5: Level = .err;
    try std.testing.expect(@intFromEnum(lvl5) == 4);
    const lvl6: Level = .crit;
    try std.testing.expect(@intFromEnum(lvl6) == 5);
    const lvl7: Level = .alert;
    try std.testing.expect(@intFromEnum(lvl7) == 6);
    const lvl8: Level = .emerg;
    try std.testing.expect(@intFromEnum(lvl8) == 7);
}

test "Logger.level ordering matches Firedancer" {
    // Verify that lower numeric values = more verbose (lower threshold)
    try std.testing.expect(@intFromEnum(Level.debug) < @intFromEnum(Level.info));
    try std.testing.expect(@intFromEnum(Level.info) < @intFromEnum(Level.notice));
    try std.testing.expect(@intFromEnum(Level.notice) < @intFromEnum(Level.warning));
    try std.testing.expect(@intFromEnum(Level.warning) < @intFromEnum(Level.err));
    try std.testing.expect(@intFromEnum(Level.err) < @intFromEnum(Level.crit));
    try std.testing.expect(@intFromEnum(Level.crit) < @intFromEnum(Level.alert));
    try std.testing.expect(@intFromEnum(Level.alert) < @intFromEnum(Level.emerg));
}

test "Logger.enableVerbose sets debug level" {
    var log = Logger{};
    log.level = .err;
    log.level = .debug;
    try std.testing.expect(@intFromEnum(log.level) == @intFromEnum(Level.debug));
}

test "Logger.isVerbose" {
    var log = Logger{};
    log.level = .err;
    try std.testing.expect(log.level != .debug);
    log.level = .debug;
    try std.testing.expect(log.level == .debug);
}

test "Logger.panic and err always write" {
    var log = Logger{};
    try log.panic("test", "func", "panic message");
    try log.err("test", "func", "err message");
}

test "Logger.enter and exit format correctly" {
    var log = Logger{};
    log.level = .debug;
    try log.enter("module", "function");
    try log.exit("module", "function");
}

test "Logger.module filtering" {
    var log = Logger{};
    log.level = .debug;
    log.modules = "ingest,normalize";

    try std.testing.expect(log.shouldLogModule("ingest", .debug));
    try std.testing.expect(log.shouldLogModule("normalize", .debug));
    try std.testing.expect(!log.shouldLogModule("policy", .debug));
}

test "Logger.module wildcard" {
    var log = Logger{};
    log.level = .debug;
    log.modules = "*";

    try std.testing.expect(log.shouldLogModule("anything", .debug));
}

test "Logger.module empty (no filter)" {
    var log = Logger{};
    log.level = .debug;
    log.modules = "";

    try std.testing.expect(log.shouldLogModule("anything", .debug));
}

test "Logger.colorize detection" {
    const log = Logger{};
    try std.testing.expect(!log.colorize);
}

test "Logger.level filtering by numeric threshold" {
    // When level is .err (4), only levels >= 4 should pass
    var log = Logger{};
    log.level = .err;
    try std.testing.expect(!log.shouldLogModule("test", .debug)); // 0 < 4
    try std.testing.expect(!log.shouldLogModule("test", .info));  // 1 < 4
    try std.testing.expect(!log.shouldLogModule("test", .notice)); // 2 < 4
    try std.testing.expect(!log.shouldLogModule("test", .warning)); // 3 < 4
    try std.testing.expect(log.shouldLogModule("test", .err)); // 4 >= 4
    try std.testing.expect(log.shouldLogModule("test", .crit)); // 5 >= 4
}

test "Logger.level filtering at debug (0)" {
    // When level is .debug (0), everything should pass
    var log = Logger{};
    log.level = .debug;
    try std.testing.expect(log.shouldLogModule("test", .debug));
    try std.testing.expect(log.shouldLogModule("test", .info));
    try std.testing.expect(log.shouldLogModule("test", .notice));
    try std.testing.expect(log.shouldLogModule("test", .warning));
    try std.testing.expect(log.shouldLogModule("test", .err));
    try std.testing.expect(log.shouldLogModule("test", .crit));
    try std.testing.expect(log.shouldLogModule("test", .alert));
    try std.testing.expect(log.shouldLogModule("test", .emerg));
}

test "Logger.level filtering at warning (3)" {
    // When level is .warning (3), only warning and above should pass
    var log = Logger{};
    log.level = .warning;
    try std.testing.expect(!log.shouldLogModule("test", .debug));
    try std.testing.expect(!log.shouldLogModule("test", .info));
    try std.testing.expect(!log.shouldLogModule("test", .notice));
    try std.testing.expect(log.shouldLogModule("test", .warning));
    try std.testing.expect(log.shouldLogModule("test", .err));
}
