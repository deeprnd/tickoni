# Plan: Eliminate OS Branches from Production Code

## Problem

The audit found **three production files** with `builtin.os.tag` branches or direct C shim calls that bypass the `os_api` abstraction layer. The rule is clear: Zig caller code must never branch on OS — all platform-specific logic must live in C shim files (`os.c`, `topo_run_platform_*.c`), and Zig callers must route through `util.os_api` or `c_abi.os` uniformly.

### Findings

| # | File | Issue | Severity |
|---|------|-------|----------|
| 1 | `util.zig` (lines 45, 69-79) | `portIsInUse()` has inline `builtin.os.tag == .windows` branches — implements its own socket-bind logic for POSIX instead of using the C shim | High |
| 2 | `model/backend.zig` (line 269) | Calls `c_abi.os.sleepNanos()` directly — bypasses `util.os_api.sleepNanos()` wrapper, which adds error-path handling | Medium |
| 3 | `process_api.zig` (lines 26, 53) | `termProcess()` and `tryReapNoHang()` have inline `builtin.os.tag` branches — POSIX `waitpid` logic is in the caller, not the shim | High |

### Correct patterns (reference)

- **Zig shim layer** (`os.zig`, `os_api.zig`): allowed to have `builtin.os.tag` branches for type aliases and id conversion — this *is* the shim.
- **C shim layer** (`os.c`, `topo_run_platform_*.c`): all `#if FD_HAS_*` branches must be in one file per logical subsystem, not scattered across callers.
- **Zig caller code**: zero `builtin.os.tag` branches. All OS-dependent calls go through `util.os_api` or `c_abi.os`.

---

## Standard

**All platform-specific logic must live in C shim files. Zig callers use uniform function calls.**

When the C shim doesn't have a function yet, **add it to the C shim first**, then update the Zig caller to use it. Never implement platform-specific logic in a Zig caller file.

---

## Changes

### 0. Add `tk_port_is_in_use()` POSIX implementation to `os.c`

**File:** `src/tickoni/c_abi/shim/os.c` (POSIX block, ~line 54)

**Status: DONE** — Replaced stub with full POSIX implementation using `socket()`, `bind()`, `close()`. Added `sys/socket.h`, `netinet/in.h`, and `sys/wait.h` includes to the POSIX block.

```c
int tk_port_is_in_use( uint16_t port ) {
  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = htonl( INADDR_ANY );

  int fd = socket( AF_INET, SOCK_STREAM, 0 );
  if( fd < 0 ) return 0;  /* socket() failed — can't determine, assume free */
  int busy = ( bind( fd, (struct sockaddr *)&addr, sizeof(addr) ) != 0 );
  close( fd );
  return busy;
}
```

---

### 1. Fix `util.zig` — `portIsInUse()`

**File:** `src/tickoni/util/util.zig` (lines 44-80)

**Status: DONE** — Replaced entire function body with `return c_abi.os.portIsInUse(port) != 0;`. Removed unused `sockaddr_in` struct (lines 20-25), `htons()` function (lines 30-32), and now-unused `builtin` import.

**Verified:** No `sockaddr_in` or `htons` references remain in `util.zig`.

---

### 2. Fix `model/backend.zig` — bypass `os_api` wrapper

**File:** `src/tickoni/tiles/model/backend.zig` (line 269)

**Status: DONE** — Changed `c_abi.os.sleepNanos(50 * std.time.ns_per_ms)` to `util.os_api.sleepNanos(50 * std.time.ns_per_ms)`. Added `const util = @import("util")` import. Call now goes through the `os_api` wrapper with proper error-path handling.

---

### 3. Add `tk_process_waitpid()` POSIX implementation to `os.c`

**File:** `src/tickoni/c_abi/shim/os.c` (POSIX block), `src/tickoni/c_abi/shim/os.zig`

**Status: DONE** — Added `tk_process_waitpid()` to the POSIX block (after `tk_process_poll`, before `tk_kill_process`). Added `sys/wait.h` include. Added Zig extern declaration `pub extern fn tk_process_waitpid(pid: c_int, status: [*]c_int, options: c_int) c_int;` to `os.zig`.

---

### 4. Fix `process_api.zig` — eliminate `builtin.os.tag` branches

**File:** `src/tickoni/util/process_api.zig`

**Status: DONE** — Both functions updated:

- `termProcess()`: Eliminated `builtin.os.tag` branch. Unified path: `os_api.c.processId(pid)` → `os_api.c.killProcess(numeric_pid)`. The shim's `processId()` handles Windows HANDLE→PID conversion; `killProcess()` is cross-platform.
- `tryReapNoHang()`: POSIX path now calls `os_api.c.tk_process_waitpid()` shim instead of inline `std.posix.system.waitpid()`. The `builtin.os.tag` branch is retained per **Option A** (documented exception) — Windows and POSIX reaping semantics are fundamentally incompatible (`processPoll` vs `waitpid`). A module-level doc comment explains the exception.

Added module-level documentation:
```zig
/// Process reaping API — cross-platform via C shim.
///
/// NOTE: This module retains `builtin.os.tag` branches because the
/// Windows and POSIX reaping semantics are fundamentally incompatible.
/// Windows uses `WaitForSingleObject` + `GetExitCodeProcess` (returns
/// exit code directly), while POSIX uses `waitpid` (returns a status
/// word encoding signals, exit codes, and core dumps). The C shim
/// provides `tk_process_poll()` for Windows and `tk_process_waitpid()`
/// for POSIX — callers use the appropriate primitive per-platform.
```

---

### 5. Remove unused code in `util.zig` (cleanup)

**File:** `src/tickoni/util/util.zig`

**Status: DONE** — `sockaddr_in` struct and `htons()` function were removed (already done in Issue 1). Now-unused `builtin` import also removed. All unused code cleaned up.

---

## Integration and system tests (unchanged)

- Integration static tests — already use `b.addRunArtifact()` natively. Not in scope.
- Integration process-mode tests — use `shims.addPlainTestRun()`. Not in scope.
- System tests — use `shims.addPlainTestRun()`. Not in scope.

---

## Verification

1. **Build:** `zig build` on Linux — compiles without errors
2. **Unit tests:** `zig build test` — all unit tests pass
3. **No more OS branches in callers:**
   ```bash
   grep -rn 'builtin.os.tag' src/tickoni/ --include='*.zig' \
     | grep -v 'os_api.zig' \
     | grep -v 'os.zig' \
     | grep -v 'process_api.zig'
   ```
   Result should be empty (process_api.zig is the documented exception).
4. **Verify shim functions exist:**
   ```bash
   grep 'tk_port_is_in_use\|tk_process_waitpid' src/tickoni/c_abi/shim/os.c
   ```
   Both should appear in the POSIX block.
5. **Verify model/backend.zig uses os_api:**
   ```bash
   grep 'sleepNanos' src/tickoni/tiles/model/backend.zig
   ```
   Should show `util.os_api.sleepNanos`.

---

## Risk

- **Low risk:** All changes are localized to three files plus the C shim. No business logic changes, no tile topology changes, no API contract changes.
- **`os_api.zig` needs a new extern declaration** for `tk_process_waitpid` — this is straightforward and follows the existing pattern.
- **`process_api.zig` exception** — if the user wants Option B (fully eliminate even shim-caller branches), that requires the unified `tk_process_reap()` shim which is more work but still low risk.
- **No test changes required** — the existing tests exercise the same code paths, just through a different (correct) call stack.

---

## Files Changed

| File | Change |
|------|--------|
| `src/tickoni/c_abi/shim/os.c` | Add POSIX `tk_port_is_in_use()` implementation; add POSIX `tk_process_waitpid()` |
| `src/tickoni/c_abi/shim/os.zig` | Add extern declaration for `tk_process_waitpid` |
| `src/tickoni/util/util.zig` | Replace `portIsInUse()` with shim call; remove unused `sockaddr_in`/`htons` if no longer referenced |
| `src/tickoni/tiles/model/backend.zig` | Change `c_abi.os.sleepNanos` to `util.os_api.sleepNanos` |
| `src/tickoni/util/process_api.zig` | Simplify `termProcess()` via `processId()` + `killProcess()`; refactor `tryReapNoHang()` to use `tk_process_waitpid()` shim |
