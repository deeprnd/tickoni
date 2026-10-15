# Eliminate empty `catch {}` across Zig codebase

## Problem

80 empty `catch {}` blocks scattered across the Zig codebase. This is a systematic anti-pattern that hides errors, degrades debuggability, and violates the "don't make errors vanish" principle.

### Distribution

| File | Count | Category |
|---|---|---|
| `src/tickoni/logger.zig` | 5 (4 runtime + 1 doc) | Logger API design |
| `src/app/tickoni/supervisor.zig` | 11 | Logger calls |
| `src/app/tickoni/main.zig` | 17 | Logger calls |
| `src/app/tickoni/tile_main.zig` | 5 | Logger calls |
| `src/tickoni/runtime/tile_process.zig` | 4 | Exit-path logging |
| `src/tickoni/tiles/payment_pipeline/ingest.zig` | 3 | Logger calls |
| `src/tickoni/tiles/payment_pipeline/normalize.zig` | 3 | Logger calls |
| `src/tickoni/tiles/payment_pipeline/dedupe.zig` | 3 | Logger calls |
| `src/tickoni/tiles/payment_pipeline/policy.zig` | 3 | Logger calls |
| `src/tickoni/tiles/payment_pipeline/audit_stage.zig` | 4 (1 safe) | Logger calls + 1 safe errdefer |
| `src/tickoni/tiles/payment_pipeline/replay.zig` | 5 (1 safe) | Logger calls + 1 safe yield |
| `src/tickoni/tiles/payment_pipeline/diag.zig` | 4 (1 safe) | Logger calls + 1 safe yield |
| `src/tickoni/tiles/payment_pipeline/queue.zig` | 2 (both safe) | Thread.yield() only |
| `src/tickoni/util/process_api.zig` | 1 | kill() failure |
| `src/tickoni/util/util.zig` | 1 | Cleanup |
| `src/tickoni/test/mocks/mock_broker_market_server.zig` | 5 | Mock server |
| `src/tickoni/test/mocks/mock_openai_server.zig` | 3 | Mock server |
| `src/tickoni/test/integration/test_investment_replay.zig` | 1 | Test cleanup |
| `src/tickoni/tiles/audit/fixture_events.zig` | 1 | Test fixture |
| **Total** | **80** | |

### Risk Assessment

| Category | Count | Risk | Action |
|---|---|---|---|
| Logger API suppression (tiles + main + supervisor + tile_main + tile_process) | ~72 | Low-Med | Fix at source (logger API) |
| `Thread.yield()` in pipeline loops | 4 | Low (safe) | No change |
| `kill()` in process_api.zig | 1 | Medium | Add logging |
| Cleanup in test/fixtures/util | 3 | Low | No change |
| Mock server responses | 8 | Low | No change |

## Root Cause

The logger API returns `!void` (`enter`, `exit`, `debug`, `info`, `err`, `kv`) but callers never handle the error. The error is `std.fmt.bufPrint` failing on a message too long for the stack buffer. The pattern emerged because the API surface doesn't match the failure likelihood — formatting failures are rare, and callers have no meaningful action to take.

## Plan

### Step 1: Fix the logger API to never return errors (priority 1)

**File: `src/tickoni/logger.zig`**

Convert `enter`, `exit`, `debug`, `info`, and `err` from `!void` to `void`. Internally catch formatting failures and fall back to the raw message.

```zig
pub fn enter(self: *Logger, module: []const u8, func: []const u8) void {
    self.debug(module, func, "enter") catch {};
}

pub fn exit(self: *Logger, module: []const u8, func: []const u8) void {
    self.writeSafe(.debug, module, func, "exit");
}
```

Add a `writeSafe` variant:

```zig
fn writeSafe(self: *Logger, level: Level, module: []const u8, func: []const u8, message: []const u8) void {
    if (@backingInt(level) < @backingInt(self.level)) return;
    if (level == .debug and !self.shouldLogModule(module, level)) return;

    var buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{s}{d} {s} [{s}] {s}: {s}{s}\n", .{
        color_code, ts, level_str, module, func, message, reset,
    }) catch {
        // Fallback: write raw message without formatting
        const raw = std.fmt.bufPrint(&buf, "{s} {d} [{s}] {s}: {s}{s}\n", .{
            color_code, ts, level_str, module, func, message, reset,
        }) catch return; // truly give up
        _ = util.os_api.write(2, raw);
        if (@backingInt(level) >= @backingInt(Level.warning)) util.os_api.fflush();
        return;
    };
    _ = util.os_api.write(2, line);
    if (@backingInt(level) >= @backingInt(Level.warning)) util.os_api.fflush();
}
```

Update `kvFmt` to use `writeSafe`. Keep `write` as `!void` for callers that do care.

### Step 2: Fix `kill()` in process_api.zig (priority 2)

**File: `src/tickoni/util/process_api.zig`**

```zig
_ = os_api.c.killProcess(numeric_pid) catch {};
```

Add debug visibility:

```zig
const log = logger.get();
os_api.c.killProcess(numeric_pid) catch |err| {
    log.debug("process_api", "termProcess", "kill returned {any}", .{err}) catch {};
};
```

### Step 3: Replace all `catch {}` in logger call sites (priority 3)

After Step 1, these calls no longer return `!void`:

- `src/app/tickoni/supervisor.zig`: 11 occurrences
- `src/app/tickoni/main.zig`: 17 occurrences
- `src/app/tickoni/tile_main.zig`: 5 occurrences
- `src/tickoni/runtime/tile_process.zig`: 4 occurrences
- `src/tickoni/tiles/payment_pipeline/*.zig`: ~28 occurrences (ingest, normalize, dedupe, policy, audit_stage, replay, diag)

Search for `log\.\(enter\|exit\|debug\|info\|err\)\(.*\) catch {}` and remove the `catch {}` suffix.

### Step 4: Leave safe `catch {}` blocks alone

No changes to:
- `std.Thread.yield() catch {}` (4 instances) — always safe, retry loop semantics
- `flush() catch {}` in test cleanup (3 instances) — best-effort cleanup
- `respondText/Json catch {}` in mock servers (8 instances) — client disconnect is normal
- `errdefer w.interface.flush() catch {}` in fixture_events (1 instance) — test cleanup

Focus areas for this story:
- **Analysability**: empty `catch {}` blocks obscure error paths, making root
  cause analysis harder. Verify the audit identifies all remaining ones and
  justifies each.
- **Modularity**: the logger API should be the single source of truth for
  error-free logging; verify no callers bypass it with ad-hoc `catch {}` patterns.
- **Testability**: verify tests for the payment pipeline still pass after
  logger API changes; add a regression test that asserts no empty `catch {}`
  in pipeline tile source files.
- **Modifiability**: after converting logger methods to `void`, verify no
  other callers rely on the `!void` return type (e.g. `try log.err(...)`).

### Verification

- `zig build test` passes
- `zig build test --summary` — no compiler warnings about unreachable code or unused values
- Grep for remaining empty `catch {}`: should be ~18 (all safe cases)
- `grep -rn 'catch {}' --include='*.zig' src/ | wc -l` — target: ≤20
