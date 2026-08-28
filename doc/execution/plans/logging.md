Plan: Improve Tickoni Zig Logging System

Current Problems

1. Silent debug logs — Logger.level defaults to .err. All log.debug() calls (payment pipeline stages, supervisor, tile_main) are silently dropped unless --verbose is passed. Test binaries never pass it.

2. No env var support — FD_LOG_LEVEL_STDERR=1 is set by helpers.zig:167 but the Zig logger ignores it. Only CLI flag --verbose works.

3. Redundant guards — Tile code writes both if (logger.isVerbose()) AND calls log.debug(), which itself checks @backingInt(level) > @backingInt(self.level). Double gate.

4. No per-module filtering — Can't do TK_LOG_DEBUG=ingest to see only ingest logs. Everything is all-or-nothing debug/off.

5. No structured fields — Single flat string: {ts} {LEVEL} [{module}] {func}: {message}\n. No key-value pairs for querying/grepping.

6. No flush mechanism — util.os_api.write(2, ...) has no flush. Output may sit in kernel buffer and disappear if process crashes.

7. No color support — Firedancer C logger has ANSI colors. Our Zig logger has none.

Design Goals

1. ZIG_LOG_LEVEL=debug (or TK_LOG_LEVEL=debug) works everywhere — CLI, env, test
2. Per-module filtering via ZIG_LOG_MODULE=ingest,normalize
3. Structured output: {ts} {level} [{module}] {func}: {key=val ...} {message}
4. ANSI colors when stdout is a TTY
5. Flush on err/panic, optional flush on debug
6. No double-gate: log.debug() is always a function call, the level check is inside
7. Backwards compatible: --verbose still works as alias for ZIG_LOG_LEVEL=debug

Implementation Steps

1. Add env var parsing to Logger struct

File: src/tickoni/logger.zig

- Add level and modules as optional parse from std.process.getEnvVarOwned() 
- Parse ZIG_LOG_LEVEL → level enum (off=0, err=1, debug=2)
- Parse ZIG_LOG_MODULES → comma-separated list of module strings to enable debug for (wildcard: * = all, ingest = only ingest)
- If no env vars set, fall back to current default (.err, no modules)
- If --verbose flag is passed, it sets ZIG_LOG_LEVEL=debug explicitly (override env)

zig
// New fields on Logger struct
level: Level = .err
modules: []const u8 = ""  // comma-separated module names
colorize: bool = false    // set on init by checking isatty

pub fn init() *Logger {
    // parse env vars
    // check isatty for colorize
}


2. Make log.debug() always callable (remove double-gate)

File: src/tickoni/logger.zig

- Remove if (logger.isVerbose()) guards from all tile code
- log.debug() internally checks: level >= debug AND (module matches OR no module filter)
- Keep enter()/exit() but make them always call debug() internally

3. Add structured output with key-value pairs

File: src/tickoni/logger.zig

- Change format to: {ts} {level} [{module}] {func}: {message} {key1=val1 key2=val2}
- Add pub fn field(self: *Logger, key: []const u8, val: []const u8) []const u8 — returns formatted KV pair
- Add pub fn kv(self: *Logger, key: []const u8, val: []const u8) !void — logs with structured KV

4. Add color support

File: src/tickoni/logger.zig

- Detect TTY via util.os_api.isatty(2) (need to add isatty to os_api.zig)
- Color mapping: debug=blue, err=red, panic=red+bold
- Only colorize when colorize == true (isatty check)

5. Add flush on err/panic

File: src/tickoni/logger.zig

- Call fflush(stderr) after err and panic (need to add fflush to os_api.zig)
- Debug does not flush

6. Remove redundant guards from tile code

Files: src/tickoni/tiles/payment_pipeline/*.zig

- ingest.zig:35: Remove if (logger.isVerbose()) guard, just call log.debug(...)
- normalize.zig:35: Same
- policy.zig:41: Same
- audit_stage.zig:35: Same
- metric.zig:22: Same
- diag.zig:17: Same (already has logger.isVerbose() check before the KV lookup — keep the check for the KV lookup itself but remove for log.debug())
- tile_process.zig:91,131,146: Already just call logger.get() — keep as-is

7. Update main.zig env var handling

File: src/app/tickoni/main.zig

- After --verbose detection, set ZIG_LOG_LEVEL=debug explicitly via std.process.setEnv()
- This ensures child processes (supervisor spawning tiles) inherit the level

8. Update helpers.zig test runner

File: tickoni-build/test/helpers.zig

- Change FD_LOG_LEVEL_STDERR=1 to ZIG_LOG_LEVEL=debug (also keep FD_LOG_LEVEL_STDERR for C logs)
- Or better: set both — FD_LOG_LEVEL_STDERR=1 AND ZIG_LOG_LEVEL=debug

9. Add isatty and fflush to os_api.zig

File: src/tickoni/util/os_api.zig

- Add pub fn isatty(fd: FileDescriptor) bool → calls c.isatty(fd)
- Add pub fn fflush() void → calls c.fflush()
- Add tk_isatty and tk_fflush to os.c shim

10. Add unit tests for new functionality

File: src/tickoni/logger.zig (tests section at bottom)

- Test env var parsing: ZIG_LOG_LEVEL=debug → level is debug
- Test env var parsing: ZIG_LOG_LEVEL=off → level is off
- Test module filtering: ZIG_LOG_MODULES=ingest → ingest logs appear, normalize doesn't
- Test module filtering: ZIG_LOG_MODULES=* → all logs appear
- Test colorize detection (mock isatty)
- Test structured KV output format

File Change Summary

| File                                               | Change                                                                   |
|----------------------------------------------------|--------------------------------------------------------------------------|
| src/tickoni/logger.zig                             | Major rewrite: env vars, module filter, structured output, colors, flush |
| src/tickoni/util/os_api.zig                        | Add isatty, fflush exports                                               |
| src/tickoni/c_abi/shim/os.c                        | Add tk_isatty, tk_fflush C wrappers                                      |
| src/tickoni/tiles/payment_pipeline/ingest.zig      | Remove if (logger.isVerbose()) guard                                     |
| src/tickoni/tiles/payment_pipeline/normalize.zig   | Remove if (logger.isVerbose()) guard                                     |
| src/tickoni/tiles/payment_pipeline/policy.zig      | Remove if (logger.isVerbose()) guard                                     |
| src/tickoni/tiles/payment_pipeline/audit_stage.zig | Remove if (logger.isVerbose()) guard                                     |
| src/tickoni/tiles/payment_pipeline/metric.zig      | Remove if (logger.isVerbose()) guard                                     |
| src/tickoni/tiles/payment_pipeline/diag.zig        | Remove if (logger.isVerbose()) guard around log.debug()                  |
| src/app/tickoni/main.zig                           | Set env var after --verbose detection                                    |
| tickoni-build/test/helpers.zig                     | Add ZIG_LOG_LEVEL=debug to test env                                      |
| src/tickoni/logger.zig (tests)                     | New tests for env parsing, module filter, colors                         |

Implementation Order

1. os_api.zig + os.c: Add isatty, fflush (foundation, no breaking changes)
2. logger.zig: Add env var parsing, module filtering, flush, colors (core rewrite)
3. Tile code: Remove redundant isVerbose() guards (cleanup)
4. main.zig: Set env var after --verbose (integration)
5. helpers.zig: Add ZIG_LOG_LEVEL=debug (test visibility)
6. Tests: New unit tests for logger

What NOT to do

- Don't change the Firedancer C logger at all
- Don't change the global logger pattern — keep logger.get() returning the singleton
- Don't add async logging or separate log threads
- Don't add log rotation or file output (keep it simple)
- Don't add performance counters or metrics to the logger
