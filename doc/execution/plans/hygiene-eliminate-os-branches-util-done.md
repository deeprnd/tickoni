# Plan: Eliminate OS Branches from util/

## Problem

Three files in `src/tickoni/util/` have `builtin.os.tag` branches. The rule is: Zig caller code must never branch on OS — all platform-specific logic must live in C shim files (`os.c`, `topo_run_platform_*.c`), and Zig callers must route through `util.os_api` or `c_abi.os` uniformly.

### Findings

| # | File | Issue | Severity |
|---|------|-------|----------|
| 1 | `util/os_api.zig:7-8` | `ProcessId` and `FileDescriptor` type aliases use `if (builtin.os.tag == .windows)` — but are dead code (zero references) | Low |
| 2 | `util/cpu.zig:64` | `CpuSetAffinity` struct is a comptime `if (builtin.os.tag == .linux)` branch — real syscalls on Linux, no-op stubs elsewhere | Medium |
| 3 | `util/process_api.zig:3,60` | `tryReapNoHang()` has a runtime `builtin.os.tag == .windows` branch — Windows `WaitForSingleObject` vs POSIX `waitpid` | High |

### Standard

All platform-specific logic must live in C shim files. Zig callers use uniform function calls. When the C shim doesn't have a function yet, add it to the C shim first, then update the Zig caller to use it.

---

## Changes

### 0. Fix `util/os_api.zig` — delete dead type aliases

**File:** `src/tickoni/util/os_api.zig` (lines 7-8)

**Status:** TODO

**Action:**
- Delete `ProcessId` type alias (line 7)
- Delete `FileDescriptor` type alias (line 8)
- Delete unused `builtin` import (line 3)

These types are never referenced anywhere in the codebase.

### 1. Fix `util/cpu.zig` — move `CpuSetAffinity` to C shim

**Files:** `src/tickoni/c_abi/shim/os.c`, `src/tickoni/c_abi/shim/os.zig`, `src/tickoni/util/cpu.zig`

**Status:** TODO

**Action:**

Add two functions to `os.c` in all three platform blocks:

- `int tk_get_affinity(int pid, unsigned char *mask)` — Linux: real `sched_getaffinity()`, macOS/fallback: no-op (all bits set or zero)
- `int tk_set_affinity(int pid, const unsigned char *mask)` — Linux: real `sched_setaffinity()`, macOS/fallback: no-op

Add externs + Zig wrappers to `os.zig`:
```zig
pub extern fn tk_get_affinity(pid: c_int, mask: [*]u8) c_int;
pub extern fn tk_set_affinity(pid: c_int, mask: [*]const u8) c_int;
```

Remove the `CpuSetAffinity` struct from `cpu.zig`. Replace with direct `os_api` calls in `getAffinity()`/`setAffinity()`.

### 2. Fix `util/process_api.zig` — move `tryReapNoHang` branching to C shim

**Files:** `src/tickoni/c_abi/shim/os.c`, `src/tickoni/c_abi/shim/os.zig`, `src/tickoni/util/process_api.zig`

**Status:** TODO

**Action:**

Add a result struct to `os.zig`:
```zig
pub const tk_process_reap_result = extern struct {
    pid: c_int,
    status: c_int,
    exit_code: c_int,
    signal: c_int,
    stop_signal: c_int,
    kind: c_int,
};
```

Add `void tk_process_reap(int pid, int options, tk_process_reap_result *out)` to `os.c` in all three platform blocks:

- **Linux/macOS:** calls `waitpid()`, decodes status word via `WIFEXITED`/`WIFSIGNALED`/`WIFSTOPPED`, fills `kind` (0=none, 1=exited, 2=signaled, 3=stopped)
- **Windows:** calls `WaitForSingleObject()`, fills `kind` (0=none/timeout, 1=exited)
- **Fallback:** no-op (zeroes out struct)

Add extern + Zig wrapper to `os.zig`.

Replace `tryReapNoHang()`'s `builtin.os.tag` branch with a single call to `os_api.c.tk_process_reap()`. The caller maps `kind` to `PollResult`:
- `pid == -1` → `.failed`
- `pid == 0` → `.running`
- `kind == 1` → `.reaped = .{ .exited = exit_code }`
- `kind == 2` → `.reaped = .{ .signal = signal }`
- `kind == 3` → `.reaped = .{ .stopped = stop_signal }`

Remove the `builtin` import and the `termFromWaitStatus()` helper from `process_api.zig` (no longer needed).

### 3. Update `util/os_api.zig` — re-export new wrapper functions

**File:** `src/tickoni/util/os_api.zig`

**Status:** TODO

**Action:**

Add wrappers (following the existing pattern in `os.zig`):
```zig
pub fn getAffinity(pid: c_int, cpu_set: []u8) void {
    _ = c.tk_get_affinity(pid, cpu_set.ptr);
}

pub fn setAffinity(pid: c_int, cpu_set: []const u8) void {
    _ = c.tk_set_affinity(pid, cpu_set.ptr);
}

pub fn processReap(pid: c_int, options: c_int) tk_process_reap_result {
    var result: tk_process_reap_result = undefined;
    c.tk_process_reap(pid, options, &result);
    return result;
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/tickoni/c_abi/shim/os.c` | Add `tk_get_affinity()`, `tk_set_affinity()`, `tk_process_reap()` in Linux, Windows, and fallback blocks |
| `src/tickoni/c_abi/shim/os.zig` | Add `tk_process_reap_result` struct, 3 externs, 3 wrappers |
| `src/tickoni/util/os_api.zig` | Delete 2 dead type aliases + 1 unused import; add 3 wrapper functions |
| `src/tickoni/util/cpu.zig` | Delete `CpuSetAffinity` struct; replace with `os_api` calls |
| `src/tickoni/util/process_api.zig` | Delete `builtin.os.tag` branch; call through `os_api.processReap()`; remove `termFromWaitStatus()` |

---

## Verification

1. **Build:** `zig build check` — compiles without errors
2. **No `builtin.os.tag` in util caller files:**
   ```bash
   grep -rn 'builtin\.os\.tag' src/tickoni/util/*.zig
   ```
   Should be empty (except possibly `os.zig` which is the shim, not util caller).
3. **No dead code:** `ProcessId` and `FileDescriptor` have zero references after deletion.

---

## Risk

- **Low risk:** All changes are localized to 5 files plus the C shim. No business logic changes, no tile topology changes, no API contract changes.
- **`tk_process_reap`** — the unified reap function consolidates Windows and POSIX reaping into a single struct. The struct layout must match exactly across platforms for Zig FFI.
- **`CpuSetAffinity` removal** — the struct was the only place `sched.h` was imported into `cpu.zig`; moving it to `os.c` is the correct location for platform-specific syscalls.
- **No test changes required** — the existing tests exercise the same code paths, just through a different (correct) call stack.
