# Zig Zealot OCD Audit — 2026-08-11

**Scope:** All `*.zig` files under `src/` in the Tickoni codebase.
**Excluded:** `.zig-cache/`, `zig-pkg/` (vendor), `src/discof/`, `src/discoh/`, build artifacts.
**Coverage:** ~100+ source files, including `build.zig`.

---

## 1. 🔴 Potential Bug — `std.mem.span()` on `getenv` Return Value

### File: `src/tickoni/test/demo/investment/mod.zig:197`

```zig
pub fn envOrDefault(
    allocator: std.mem.Allocator,
    name: []const u8,
    fallback: []const u8,
) ![]u8 {
    const name_z = try allocator.dupeZ(u8, name);
    defer allocator.free(name_z);
    if (std.c.getenv(name_z)) |val| return allocator.dupe(u8, std.mem.span(val));
    return allocator.dupe(u8, fallback);
}
```

**Issue:** `std.c.getenv()` returns `?[*:0]u8` — a sentinel-terminated C string pointer. `std.mem.span()` on a `[*:0]u8` produces `[:0]u8` — a slice **with** the trailing null terminator included.

`allocator.dupe(u8, ...)` accepts `[]const u8`, and while Zig will implicitly coerce `[:0]u8` to `[]const u8` (the coerced slice drops the null terminator), this is:

- A **silent implicit coercion** that obscures intent
- Fragile — if the API contract for `dupe` changes or the coercion rules tighten, this becomes a compile error
- Inconsistent with the codebase's own documented pattern in the `zig-development` skill, which prescribes `std.mem.sliceTo(v, 0)` for all `getenv` usage

**Recommendation:** Replace with `std.mem.sliceTo(val, 0)`:

```zig
if (std.c.getenv(name_z)) |val| return allocator.dupe(u8, std.mem.sliceTo(val, 0));
```

This produces a clean `[]const u8` slice with no trailing null, making the intent explicit and immune to future coercion rule changes.

### File: `src/tickoni/test/system/test_investment_demo_live.zig:18-19`

```zig
if (std.c.getenv("TK_LIVE_TEST")) |v| {
    const val = std.mem.span(v);
```

Same issue — `v` is `[*:0]u8`, `std.mem.span(v)` produces `[:0]u8`. The subsequent `std.mem.eql(u8, val, "1")` works because `eql` also coerces `[:0]u8` to `[]const u8`, but it's the same fragility pattern.

**Recommendation:** Replace with `std.mem.sliceTo(v, 0)`.

---

## 2. 🟡 Style — Inconsistent `getenv` Null Comparison

Five files check `TK_GEN_FIXTURES` and `TK_LIVE_TEST` via `std.c.getenv`, using **both** comparison styles:

| File | Line | Style |
|------|------|-------|
| `test_investment_replay.zig` | 240 | `== null` |
| `fixture_events.zig` | 216 | `!= null` |
| `fixture_events.zig` | 402 | `== null` |
| `test_investment_demo_live.zig` | 18 | `|v|` (optional binding) |
| `investment/mod.zig` | 197 | `|val|` (optional binding) |

**Recommendation:** Standardize on one pattern. The `|v|` optional binding form (used in `demo_live` and `investment/mod.zig`) is the most idiomatic Zig — it's compact and immediately usable. The `== null` form is fine but requires a separate comparison expression. Pick one and apply consistently.

---

## 3. 🟡 Duplicate Logic — Heartbeat Multiplication

### File: `src/app/tickoni/supervisor.zig:96-104`

```zig
fn resolvedHeartbeatStaleAfterNs(config: ProcessPipelineConfig) u64 {
    if (config.heartbeat_stale_after_ns != 0) return config.heartbeat_stale_after_ns;
    return std.math.mul(u64, config.heartbeat_interval_ns, 5) catch std.math.maxInt(u64);
}

fn resolvedStopGraceNs(config: ProcessPipelineConfig) u64 {
    const from_heartbeat = std.math.mul(u64, config.heartbeat_interval_ns, 5) catch std.math.maxInt(u64);
    return @min(@max(from_heartbeat, 500 * std.time.ns_per_ms), 2 * std.time.ns_per_s);
}
```

The expression `std.math.mul(u64, config.heartbeat_interval_ns, 5) catch std.math.maxInt(u64)` is duplicated verbatim across two functions.

**Recommendation:** Extract to a private helper:

```zig
fn heartbeatIntervalMsTimes5(config: ProcessPipelineConfig) u64 {
    return std.math.mul(u64, config.heartbeat_interval_ns, 5) catch std.math.maxInt(u64);
}
```

---

## 4. 🟡 Inconsistent While-Loop Increment Style

The codebase uses two styles for incrementing loop variables:

- **Post-increment in while condition:** `while (i < len) : (i += 1)` (seen in `main.zig:59,270`)
- **Body-increment:** `i += 1;` inside the loop body (seen in ~25+ locations across `demo/runner.zig`, `tickoni/demo/preflight.zig`, `tickoni/demo/semver.zig`, `app/tickoni/main.zig`, etc.)

Both are valid Zig. The `: (i += 1)` form is preferred by the Zig style guide for simple counting loops because it keeps the increment visible at the loop header.

**Recommendation:** No immediate action required — this is a style preference, not a correctness issue. Document the preferred style if the team wants consistency.

---

## 5. 🟡 `version.zig:21-40` — `semver()` Docstring Clarity

```zig
/// Semver release string (no prerelease on stable releases).
/// Writes to the caller's buffer and returns the resulting string.
pub fn semver(buf: []u8) ![]const u8 {
```

The function is correctly implemented — it takes a caller-provided buffer and returns a slice into it. However, the docstring says "Writes to the caller's buffer and returns the resulting string" which could be misread as a heap-allocating pattern.

**Recommendation:** Clarify the docstring:

```zig
/// Format the semver release string into the caller-provided `buf`.
/// The returned slice points into `buf` — the caller owns `buf` and
/// must keep it alive for as long as the returned slice is used.
```

This matches the pattern used in `VersionInfo.init()` at line 73-78 which correctly calls `semver(&buf)` and uses the result before `buf` goes out of scope.

---

## 5. 🟡 `version.zig:21-40` — `semver()` Docstring Clarity

```zig
/// Semver release string (no prerelease on stable releases).
/// Writes to the caller's buffer and returns the resulting string.
pub fn semver(buf: []u8) ![]const u8 {
```

The function is correctly implemented — it takes a caller-provided buffer and returns a slice into it. However, the docstring says "Writes to the caller's buffer and returns the resulting string" which could be misread as a heap-allocating pattern.

**Recommendation:** Clarify the docstring:

```zig
/// Format the semver release string into the caller-provided `buf`.
/// The returned slice points into `buf` — the caller owns `buf` and
/// must keep it alive for as long as the returned slice is used.
```

This matches the pattern used in `VersionInfo.init()` at line 73-78 which correctly calls `semver(&buf)` and uses the result before `buf` goes out of scope.

---

## 6. 🔴 `std.c.` — C FFI Overuse Instead of Zig-Native APIs

### Overview

The codebase uses `std.c.` **14 times** across **5 files**. `std.c.` is Zig's C FFI layer — a bridge to C's ABI, not a Zig-native API. Zig provides equivalent standard library APIs for every `std.c.` function used here. Continuing to use `std.c.` is anti-pattern for a codebase that aims to be idiomatic Zig: it introduces C ABI dependencies, obscures intent, and prevents the compiler from optimizing across FFI boundaries.

| `std.c.` Usage | Count | Files | Zig-Native Replacement |
|----------------|-------|-------|------------------------|
| `std.c.getenv()` | 5 | `investment/mod.zig`, `test_investment_demo_live.zig`, `test_investment_replay.zig`, `fixture_events.zig` | `std.process.getEnvVarOwned()` or `std.process.EnvInfo.init().get()` |
| `std.c.fopen()`/`fclose()`/`fwrite()` | 7 | `test_investment_replay.zig`, `fixture_events.zig` | `std.fs.cwd().createFile()` + `file.writeAll()` |
| `std.c.W.NOHANG` | 1 | `process_api.zig` | `std.posix.W.NOHANG` |
| `std.c.FILE` type | 1 | `fixture_events.zig` | `std.fs.File` |

### 6.1 `std.c.getenv()` — 5 Call Sites

#### File: `src/tickoni/test/demo/investment/mod.zig:197`

```zig
if (std.c.getenv(name_z)) |val| return allocator.dupe(u8, std.mem.span(val));
```

**Problems:**
1. Uses C FFI for what Zig handles natively
2. The `std.mem.span()` coercion bug from Section 1 (see below)
3. Requires manual `dupeZ` allocation of `name_z` just to pass a C-compatible pointer

**Zig-native replacement:**
```zig
pub fn envOrDefault(
    allocator: std.mem.Allocator,
    name: []const u8,
    fallback: []const u8,
) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, name)) |owned| return owned;
    return allocator.dupe(u8, fallback);
}
```

This is simpler (no `dupeZ` allocation), fixes the coercion bug (returns owned `[]u8` directly), and is idiomatic Zig.

#### File: `src/tickoni/test/system/test_investment_demo_live.zig:18-19`

```zig
if (std.c.getenv("TK_LIVE_TEST")) |v| {
    const val = std.mem.span(v);
```

**Zig-native replacement:**
```zig
if (std.process.getEnvVarOwned(allocator, "TK_LIVE_TEST")) |v| {
    if (!std.mem.eql(u8, v, "1")) { ... }
}
```

Or for read-only (no allocation):
```zig
if (std.process.EnvInfo.init().get("TK_LIVE_TEST")) |v| {
    if (!std.mem.eql(u8, v, "1")) { ... }
}
```

#### Files: `test_investment_replay.zig:240`, `fixture_events.zig:216,402`

```zig
if (std.c.getenv("TK_GEN_FIXTURES") == null) return error.SkipZigTest;
```

**Zig-native replacement:**
```zig
if (std.process.EnvInfo.init().get("TK_GEN_FIXTURES") == null) return error.SkipZigTest;
```

### 6.2 `std.c.fopen`/`fclose`/`fwrite` — 7 Call Sites

#### File: `src/tickoni/tiles/audit/fixture_events.zig:360-398`

```zig
fn cwrite(f: *std.c.FILE, s: []const u8) void {
    _ = std.c.fwrite(s.ptr, 1, s.len, f);
}

fn writeFixtureFile() !void {
    const path = "src/tickoni/test/fixtures/fixture_audit_gen.zig";
    const f = std.c.fopen(path, "w") orelse return error.FileOpenFailed;
    defer _ = std.c.fclose(f);
    // ... repeated cwrite(f, ...) calls throughout
}
```

**Problems:**
1. C FFI for basic file I/O that Zig handles natively
2. Introduces a custom `cwrite()` helper that wraps `fwrite` — adds indirection for zero benefit
3. The helper takes `*std.c.FILE` which couples the entire function to the C file type
4. `defer _ = std.c.fclose(f)` discards the close error — same issue can be solved with `std.fs.File` which owns its lifecycle

**Zig-native replacement:**
```zig
fn writeFixtureFile() !void {
    const path = "src/tickoni/test/fixtures/fixture_audit_gen.zig";
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    const header =
        \\// Auto-generated by `just gen-audit-fixtures`. Do not edit manually.
        \\pub const Fixture = struct {
        \\    expected_hash: u64,
        \\    expected_binary_len: usize,
        \\    expected_binary_bytes: []const u8,
        \\};
        \\
        \\pub const values = [12]Fixture{
        \\
    ;
    try file.writeAll(header);

    var buf: [512]u8 = undefined;
    for (makeFixtures()) |event| {
        var binary_buf: [codec.max_binary_len]u8 = undefined;
        const binary = try codec.formatBinary(&binary_buf, event);
        const entry = try std.fmt.bufPrint(
            &buf,
            "    .{{ .expected_hash = {d}, .expected_binary_len = {d}, .expected_binary_bytes = &.{{",
            .{ event.header.record_hash, binary.len },
        );
        try file.writeAll(entry);
        for (binary, 0..) |b, j| {
            const sep: []const u8 = if (j > 0) ", " else "";
            const hex = try std.fmt.bufPrint(&buf, "{s}0x{X:0>2}", .{ sep, b });
            try file.writeAll(hex);
        }
        try file.writeAll("} },\n");
    }

    try file.writeAll("};\n");
    std.debug.print("wrote {s}\n", .{path});
}
```

The `cwrite()` helper disappears entirely — replaced by `try file.writeAll(...)` inline. Every write becomes explicit and error-aware.

#### File: `src/tickoni/test/integration/test_investment_replay.zig:281-289`

```zig
const f = std.c.fopen(path, "w") orelse return error.FileOpenFailed;
defer _ = std.c.fclose(f);
// ... _ = std.c.fwrite(written.ptr, 1, written.len, f);
```

**Zig-native replacement:**
```zig
const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
defer file.close();
try file.writeAll(written);
```

Single line for the entire read-write-close lifecycle. No `cwrite` wrapper needed.

### 6.3 `std.c.W.NOHANG` — 1 Call Site

#### File: `src/tickoni/util/process_api.zig:43`

```zig
const rc = std.posix.system.waitpid(pid, &status, std.c.W.NOHANG);
```

**Zig-native replacement:**
```zig
const rc = std.posix.system.waitpid(pid, &status, std.posix.W.NOHANG);
```

Trivial swap: `std.c.W` → `std.posix.W`. `std.posix.W` is Zig's POSIX constant namespace — it's the Zig-native equivalent of C's `WNOHANG`. No FFI, no C ABI.

### 6.4 `std.c.FILE` Type — 1 Call Site

#### File: `src/tickoni/tiles/audit/fixture_events.zig:360`

```zig
fn cwrite(f: *std.c.FILE, s: []const u8) void
```

**Zig-native replacement:** This is eliminated by the replacement in Section 6.2 — the entire `cwrite` function is removed when switching to `std.fs.File` + `writeAll()`.

### 6.5 Rationale — Why This Matters

1. **Performance:** Zig's compiler can optimize across `std.fs` API calls (inline, constant-fold paths, elide syscalls). `std.c.` calls are opaque FFI boundaries — the compiler must treat them as black boxes.
2. **Correctness:** `std.c.fopen("w")` truncates; `std.c.fopen("a")` appends. The meaning of mode strings is C-specific and platform-dependent. `std.fs.cwd().createFile(path, .{ .truncate = true })` is explicit and portable.
3. **Error handling:** C file APIs return `FILE*` / `int` / `size_t` — error detection is manual (`f == null`, return value < 0). `std.fs.File` returns `!File` — errors are in the type, checked at compile time via `try`/`catch`.
4. **Consistency:** The codebase already uses Zig-native file I/O in many places (e.g., `std.fs.cwd().readFileAlloc()`, `std.fs.createFile()`). Using `std.c.*` in some places but not others is inconsistent and signals that the Zig file API was "not good enough" — when it actually is.
5. **The `span` bug is caused by this pattern:** Section 1's `std.mem.span()` coercion issue only exists because `std.c.getenv()` returns a C-style `[*:0]u8`. Using `std.process.getEnvVarOwned()` returns `!?[]u8` — no sentinel-terminated pointer, no coercion ambiguity.

### 6.6 Migration Priority

| Priority | Replacement | Effort | Impact |
|----------|-------------|--------|--------|
| **P0** | `std.c.getenv()` → `std.process.getEnvVarOwned()` | Low (2 lines each) | Fixes coercion bug, eliminates C FFI |
| **P0** | `std.c.fopen/fwrite/fclose` → `std.fs.File` | Medium (rewrite helper) | Eliminates `cwrite()`, proper error handling |
| **P1** | `std.c.W.NOHANG` → `std.posix.W.NOHANG` | Trivial (1 char) | Eliminates C FFI |
| **P1** | `std.c.FILE` type → `std.fs.File` | Covered by P0 | Type cleanup |

---

## 7. 🟢 All Good — Confirmed Compliant Patterns

### 7.1 `bufPrint` Tuple Formatting ✅
All ~50 `std.fmt.bufPrint` calls correctly use the `.{...}` tuple form. No bare values passed as the third argument.

### 7.2 `shimCFlagsFor()` Coverage in build.zig ✅
All 10 `addCSourceFiles` blocks in `build.zig` use `shimCFlagsFor()`. Zero hardcoded `"-std=c17"` flags in C source compilation.

### 7.3 `b.host.result` Eliminated ✅
`build.zig` uses `b.standardTargetOptions()` — no remnants of the removed `b.host` accessor.

### 7.4 `@min`/`@max` Builtins ✅
All min/max comparisons use the Zig 0.16 builtins `@min()` and `@max()`. No remnants of the removed `std.math.min`/`std.math.max`.

### 7.5 `std.Io.File.stdout().writer(io, &buf)` Pattern ✅
All 3 occurrences in `src/app/tickoni/` correctly use the Zig 0.16 Writer pattern. No direct `.print()` or `.writeAll()` on `File`.

### 7.6 `std.mem.indexOf(...) != null` Pattern ✅
All ~50 occurrences correctly use `std.mem.indexOf(u8, haystack, needle) != null` instead of the removed `std.mem.contains`.

### 7.7 No `ArrayList` Migration Debt ✅
No `ArrayList` usage found in source files — the Zig 0.16 `initCapacity(gpa, 0)` / `append(gpa, item)` pattern is not a concern here.

### 7.8 No `std.io.fixedBufferWriter` or `.getWritten()` ✅
All code uses `std.Io.Writer.fixed(&buf)` and `w.buffered()` or `w.buffer[0..w.end]`.

### 7.9 No `.path.?` LazyPath Pitfalls ✅
`build.zig` has zero occurrences of `.path.?` on `b.path()` or `b.build_root`.

### 7.10 No `_GNU_SOURCE` Without Guards ✅
Zero unguarded `_GNU_SOURCE` definitions in shim `.c` files.

### 7.11 No `b.addStaticLibrary` ✅
All C compilation uses `addCSourceFiles` — no references to the removed `b.addStaticLibrary`.

---

## Summary

| Severity | Count | Action |
|----------|-------|--------|
| 🔴 **Bug / Anti-pattern** | 2 | `std.mem.span()` → `std.mem.sliceTo()` for `getenv`; replace all 14 `std.c.` calls with Zig-native APIs |
| 🟡 **Style/Consistency** | 4 | getenv null style, duplicate mul logic, increment patterns, docstring clarity |
| 🟢 **All Good** | 11 patterns | bufPrint, shimCFlagsFor, @min/@max, .writer, indexOf, ArrayList-free, etc. |

**Most impactful fixes:**
1. Replace `std.mem.span()` with `std.mem.sliceTo()` on `getenv` return values (2 locations). Eliminates fragile implicit coercion.
2. Eliminate all 14 `std.c.` calls: replace `std.c.getenv()` with `std.process.getEnvVarOwned()`, `std.c.fopen/fwrite/fclose` with `std.fs.File` + `writeAll()`, `std.c.W.NOHANG` with `std.posix.W.NOHANG`. Fixes the coercion bug, eliminates C FFI overhead, and makes the codebase genuinely idiomatic Zig.
