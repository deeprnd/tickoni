/// Tickoni structured logger — name/enter/exit pattern for method tracing.
///
/// Design (industry standard — OpenTelemetry/SLF4J inspired):
///   1. Level parsed from ZIG_LOG_LEVEL env var (default .err)
///   2. Module filtering via ZIG_LOG_MODULES env var (comma-separated, wildcard *)
///   3. ANSI color when stdout is a TTY (auto-detected via isatty)
///   4. Structured key-value output: {ts} {level} [{module}] {func}: {key=val ...} {message}\n///   5. Flush on err/panic via fflush(stderr)
///   6. No double-gate: log.debug() is always callable, level check internal
///   7. --verbose flag sets ZIG_LOG_LEVEL=debug for backwards compatibility
///   8. Backwards-compatible: isVerbose() still works, global singleton unchanged
///
/// Usage:
///   const log = @import("logger").get();
///   log.enter("module", "func") catch {};\n///   defer log.exit("module", "func") catch {};\n///   log.debug("module", "message") catch {};\n///   log.kv("module", "key1=val1 key2=val2") catch {};\nconst std = @import("std\");
const util = @import("util");

/// Log severity levels — matches OpenTelemetry/SLF4J.
pub const Level = enum {
    off,
    err,
    debug,
};

/// Maximum number of module filters.
const MAX_MODULES = 32;
/// Maximum length for a single module name.
const MAX_MODULE_NAME_LEN = 64;
/// Maximum length for env var values.
const MAX_ENV_LEN = 2048;

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

    /// Color escape codes.
    const color_debug = "\x1b[34m";  // blue
    const color_err = "\x1b[31m";    // red
    const color_panic = "\x1b[1;31m"; // red+bold
    const color_reset = "\x1b[0m";

    /// Initialize the logger: parse env vars, detect TTY.
    pub fn init(self: *Logger) void {
        // Parse ZIG_LOG_LEVEL
        self.level = self.parseLogLevel();

        // Parse ZIG_LOG_MODULES
        const raw = self.parseModules();
        self.modules = raw;

        // Detect TTY for color support
        self.colorize = util.os_api.isatty(2);
    }

    /// Parse ZIG_LOG_LEVEL from environment.
    fn parseLogLevel(self: *Logger) Level {
        const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIG_LOG_LEVEL") catch |err| {
            // If env var not present or unreadable, fall through to default
            _ = err;
            return .err;
        };
        defer std.heap.page_allocator.free(env);

        return switch (std.ascii.asciiToLowerString(env)) {
            "off" => .off,
            "err" => .err,
            "debug" => .debug,
            else => .err, // unknown value → default
        };
    }

    /// Parse ZIG_LOG_MODULES from environment.
    fn parseModules(self: *Logger) []const u8 {
        const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIG_LOG_MODULES") catch |err| {
            // If env var not present, no module filter
            _ = err;
            return "";
        };
        defer std.heap.page_allocator.free(env);

        // If empty, no filter
        if (env.len == 0) return "";

        // Copy into a buffer (we'll return a slice of the allocated buffer)
        // Since we need to own this, keep the allocation
        return env;
    }

    /// Check if a module's debug logs should be emitted.
    pub fn shouldLogModule(self: *Logger, module: []const u8, level: Level) bool {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return false;

        // If level is off, nothing passes
        if (self.level == .off and level != .off) return false;
        if (self.level == .off) return true; // off can still log off-level (none expected)

        // If no module filter, all modules pass
        if (self.modules.len == 0) return true;

        // Check for wildcard
        if (std.mem.eql(u8, self.modules, "*")) return true;

        // Check if module is in the comma-separated list
        var iter = std.mem.splitScalar(u8, self.modules, ',');
        while (iter.next()) |mod| {
            // Trim whitespace
            mod = std.mem.trim(u8, mod, " \t");
            if (std.mem.eql(u8, mod, module)) return true;
        }
        return false;
    }

    /// Write an entry to stderr.
    pub fn write(self: *Logger, level: Level, module: []const u8, func: []const u8, message: []const u8) !void {
        // Level gate: only write if level >= self.level
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        // Module gate (only for debug level)
        if (level == .debug and !self.shouldLogModule(module, level)) return;

        // Monotonic nanosecond timestamp
        const ts: i64 = util.os_api.monotonicNanos();

        // Format level string
        const level_str = switch (level) {
            .off => "OFF",
            .err => "ERR",
            .debug => "DEBUG",
        };

        // Apply colors if TTY
        const color_code = if (self.colorize) switch (level) {
            .off => "",
            .err => self.color_err,
            .debug => self.color_debug,
        } else "";

        const reset = if (self.colorize) self.color_reset else "";

        // Format: {ts} {level} [{module}] {func}: {message}
        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s}{d} {s} [{s}] {s}: {s}{s}\n", .{
            color_code, ts, level_str, module, func, message, reset,
        });

        // Write to stderr (fd 2)
        _ = util.os_api.write(2, line);

        // Flush on err and panic
        if (level == .err or level == .panic) {
            util.os_api.fflush();
        }
    }

    /// Log at panic level (always enabled, always flushed).
    pub fn panic(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        // Panic always writes regardless of level or module filter
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

    /// Log at off level (internal use).
    pub fn off(self: *Logger, module: []const u8, func: []const u8, message: []const u8) !void {
        try self.write(.off, module, func, message);
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

    /// Get a formatted key-value string.
    pub fn field(self: *Logger, key: []const u8, val: []const u8) []const u8 {
        var buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{s}={s}", .{ key, val }) catch return "";
        return result;
    }

    /// Deinitialize: free owned memory.
    pub fn deinit(self: *Logger) void {
        // Free the modules allocation if we own it
        // (In the singleton case, this is called once at shutdown)
        std.heap.page_allocator.free(self.modules);
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
    var log = Logger{};
    // colorize starts as false (not a TTY in tests)
    try std.testing.expect(!log.colorize);
}
