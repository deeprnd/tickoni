# Time Management

## Clock Sources

Tickoni uses two fundamentally different clock types. They are **not interchangeable** — choosing the wrong one produces silent correctness bugs (NTP jumps corrupting durations, or boot-relative timestamps appearing as wall-clock time).

### WALLCLOCK — `fd_log_wallclock()`

**Purpose:** Time of day. Human-readable timestamps for logging and diagnostics.

**Underlying clock:** `CLOCK_REALTIME` (Linux/macOS), Windows equivalent.

**Properties:**
- Returns nanoseconds since UNIX epoch
- Subject to NTP adjustments, manual clock edits, leap seconds
- Can jump forward or backward
- Can go backwards

**Implementation:** Firedancer C utility in `src/util/log/fd_log.c`. Default backend is `fd_log_wallclock_host()` which calls `clock_gettime(CLOCK_REALTIME)`. The clock function is swappable via `fd_log_wallclock_set()` — used by tests and custom backends.

**Zig access:** Declared as `extern fn fd_log_wallclock() i64` in `src/tickoni/c_abi/os.zig`, wrapped by `fdLogWallclock()`.

**Used for:**
- Log timestamp formatting (`fd_log_wallclock_cstr()` produces `"YYYY/MM/DD HH:MM:SS.nnnnnnnnn"` strings)
- Wall-clock deadlines in tooling scripts (e.g. `fd_bencho.c` RPC timeouts)
- Diagnostic timestamps that need to correspond to real-world time

### MONOTONIC — `util.process.monotonicNanos()`

**Purpose:** Elapsed time measurement. Duration profiling, timeouts, benchmarking.

**Underlying clocks:** `CLOCK_MONOTONIC` (Linux/macOS), `QueryPerformanceCounter` (Windows).

**Properties:**
- Returns nanoseconds since an arbitrary point (typically boot)
- **Never jumps, never goes backwards**
- Survives NTP adjustments, manual clock edits
- **Not** related to wall-clock time

**Implementation chain (Zig → C shim → platform):**
```
util/process.zig:7          → pub const monotonicNanos = os_api.monotonicNanos;
util/os_api.zig:9           → return c.monotonicNanos();           // c = c_abi.os
c_abi/os.zig:95             → return tk_monotonic_nanos();         // extern fn
c_abi/shim/os.c             → platform-specific implementation
```

**Platform implementations:**
- Linux/macOS: `clock_gettime(CLOCK_MONOTONIC)` (shared block, line 130)
- Windows: `QueryPerformanceCounter` / `QueryPerformanceFrequency` (line 387)
- Fallback (no platform match): returns 0 (test-only stub)

**Used for:**
- Process lifecycle timing (`test_process_cpu_placement.zig`)
- Test observation wait loops (`util/test_process_api.zig`)
- Duration measurements in Tickoni utilities

## Decision Rules

Use this decision tree when writing new code that needs a clock:

| Scenario | Clock | Rule |
|---|---|---|
| Log timestamp (human-readable) | `fd_log_wallclock()` | Mandatory — this is what `FD_LOG_*` macros use |
| Duration / elapsed time | `monotonicNanos()` | Mandatory — wallclock can jump |
| Timeout deadline | `monotonicNanos()` | Mandatory — wallclock can jump backwards, making deadlines invalid |
| Benchmark / profiling | `monotonicNanos()` | Mandatory — wallclock noise corrupts measurements |
| Wall-clock deadline (e.g. "wait until 15:00 UTC") | `fd_log_wallclock()` | Rare — only when real-world time matters, not elapsed duration |
| Internal state machine transitions | `monotonicNanos()` | Default — unless the state needs wall-clock time of day |

### Anti-patterns (avoid these)

```
// BAD: measuring duration with wallclock
long t0 = fd_log_wallclock();
do_work();
long dt = fd_log_wallclock() - t0;  // WRONG: NTP jump corrupts dt

// BAD: timeout with wallclock
ctx->deadline = fd_log_wallclock() + 5e9;  // WRONG: clock can jump past deadline

// BAD: profiling with wallclock
long start = fd_log_wallclock();
benchmark();
long elapsed = fd_log_wallclock() - start;  // WRONG: wallclock noise
```

```
// BAD: logging with monotonic
// Monotonic returns "seconds since boot" — useless for log timestamps
char buf[64];
fd_log_wallclock_cstr(monotonicNanos(), buf);  // WRONG: shows boot-relative time
```

## Standardisation Rules

1. **Tickoni Zig code MUST use `util.process.monotonicNanos()` for all elapsed time, duration, and timeout logic.** Do not call `fd_log_wallclock()` from Zig code unless you explicitly need wall-clock time of day (extremely rare).

2. **C tile code uses `fd_log_wallclock()` by convention.** This is acceptable because Firedancer tile code is C and the logging infrastructure already depends on it. However, elapsed time measurements in tile loops should use monotonic where available.

3. **Do not mix clocks in a single duration calculation.** `t1 - t0` must use the same clock source for both values. Mixing `fd_log_wallclock()` and `monotonicNanos()` in the same subtraction produces garbage.

4. **The monotonicNanos abstraction chain is the single source of truth for Tickoni Zig.** Do not call `clock_gettime`, `QueryPerformanceCounter`, or any platform-specific clock directly from Zig code. Route through `util.process.monotonicNanos()`.

5. **Wallclock is swappable, monotonic is not.** `fd_log_wallclock()` can be redirected via `fd_log_wallclock_set()` for tests. The monotonic clock is platform-specific but not swappable at runtime — if you need testable timing, use mock durations in the test harness, not a swappable clock function.

## Platform Support

| Clock | Linux | macOS | Windows |
|---|---|---|---|
| `fd_log_wallclock()` | ✓ `CLOCK_REALTIME` | ✓ `CLOCK_REALTIME` | ✓ Windows APIs |
| `tk_monotonic_nanos()` | ✓ `CLOCK_MONOTONIC` | ✓ `CLOCK_MONOTONIC` | ✓ `QueryPerformanceCounter` |

Both clocks work on all three platforms. The monotonic clock has more deliberate cross-platform design: shared Linux/macOS block, separate Windows block, and test-only fallback stubs.
