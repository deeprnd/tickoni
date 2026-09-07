# Bug Fix Plan: Windows Runtime Stub Layer (#46)

**Bug**: Windows implementation is a stub layer, not a functional runtime — tiles cannot run
**Source**: V2.22.S4 security audit Finding 2
**Severity**: CRITICAL — blocks Windows support
**Status**: Open — stubs still present as of 2026-09-07

---

## Current State

Confirmed as of 2026-09-07: both Windows platform stubs remain unchanged in structure:

- `src/util/tile/fd_tile_threads_platform_windows.c` — 129 lines, all stubs
- `src/disco/topo/fd_cpu_topo_platform_windows.c` — 19 lines, single-CPU stub

The stubs compile but tiles cannot execute on real Windows hardware: no stack allocation, no CPU topology discovery, no multi-tile dispatch, no thread affinity.

---

## Scope

This fix replaces the stub implementations with functional (if not full-featured) Windows equivalents. It does NOT aim to match Linux/macOS feature parity — just to enable tiles to actually run.

### What changes
- `fd_tile_threads_platform_windows.c`: functional thread stack allocation, tile execution (CreateThread + WaitForSingleObject), CPU topology detection (GetActiveProcessorCount/GetSystemInfo)
- `fd_cpu_topo_platform_windows.c`: real Windows CPU/NUMA discovery via `GetLogicalProcessorInformationEx` or `EnumProcessorRelations`
- `fd_log_private_cpu_id`: use `GetCurrentProcessorNumber` instead of hardcoded 0
- `fd_log_private_main_stack_sz`: use `GetCurrentThreadStackLimits()` or detect stack via thread context

### What does NOT change
- Tile IDs, capability names, audit schema, replay behavior
- Firedancer infrastructure paths or topology conventions
- Any Linux/macOS code
- Build system structure (per-platform files pattern preserved)

---

## Implementation Plan

### Phase 1: CPU Topology Discovery

**File**: `src/disco/topo/fd_cpu_topo_platform_windows.c`

Replace stub with Windows-native discovery:

1. Call `GetActiveProcessorCount(ALL_PROCESSOR_GROUPS)` to get total CPU count
2. Call `GetLogicalProcessorInformationEx(RelationProcessorGroup)` to build per-CPU info:
   - `cpu[].idx` ← processor index
   - `cpu[].online` ← 1 (all reported CPUs are online on Windows)
   - `cpu[].numa_node` ← from `GROUP_AFFINITY` group info or query `GetGroupInformation`
   - `cpu[].sibling` ← hyperthread sibling via `GROUP_LOGICAL_PROCESSOR_POSITION`
3. Populate `fd_topo_cpus_t` struct the same way Linux does
4. `fd_topo_cpus_printf_platform`: print detected CPUs in same format as Linux

**Windows API used**:
- `GetActiveProcessorCount()`
- `GetLogicalProcessorInformationEx(RelationProcessorGroup, ...)`
- `GetGroupInformation()` for NUMA grouping

**Fallback**: If `GetLogicalProcessorInformationEx` fails, fall back to `GetSystemInfo` (single group, no NUMA detail).

**Verification**: Unit test in `test_cpu_topo_platform_windows.c` verifies `cpu_cnt >= 1`, `numa_node_cnt >= 1`, and that at least one CPU is online.

### Phase 2: Tile Threading — Stack Allocation

**File**: `src/util/tile/fd_tile_threads_platform_windows.c`

Replace `fd_tile_private_stack_new`:

1. Use `VirtualAlloc` with `MEM_COMMIT | MEM_RESERVE` and `PAGE_READWRITE` to allocate stack memory
2. Allocate `FD_TILE_PRIVATE_STACK_SZ + 2 * PAGE_SIZE` (same guard region pattern as Linux)
3. Call `VirtualAlloc` twice more with `PAGE_GUARD | PAGE_READWRITE` for guard lo and guard hi
4. On failure, fall back to NULL (pthread default stack, same as Linux fallback)

Replace `fd_tile_private_stack_delete`:

1. Call `VirtualFree` for guard hi, guard lo, and main stack regions
2. Handle NULL gracefully (already done for Linux)

### Phase 3: Tile Threading — Execution

**File**: `src/util/tile/fd_tile_threads_platform_windows.c`

Replace stub execution with functional implementation:

1. `fd_tile_private_manager` → Windows equivalent using `CreateThread` with a Windows thread start routine
2. Thread function runs the same state machine: BOOT → IDLE → EXEC loop → HALT
3. Use `SRWLOCK` (Slim Reader/Writer Lock) instead of `pthread_mutex` for tile locking
4. `fd_tile_exec_new`: acquire lock, set tile state to EXEC, return tile pointer
5. `fd_tile_exec`: return current tile pointer for given index
6. `fd_tile_exec_done`: check if tile state is EXEC
7. `fd_tile_exec_delete`: wait for IDLE, return fail message, release lock

**Windows threading primitives**:
- `CreateThread` instead of `pthread_create`
- `SRWLOCK` instead of `pthread_mutex`
- `SetThreadAffinityMask` or `SetThreadGroupAffinity` instead of `sched_setaffinity`
- `GetThreadId` / `GetCurrentThreadId` for thread ID
- `_beginthreadex` as alternative (but `CreateThread` is preferred for Firedancer-style code)

### Phase 4: CPU Configuration & Logging

**File**: `src/util/tile/fd_tile_threads_platform_windows.c`

1. `fd_tile_private_cpu_config`: set thread priority via `SetPriorityThread` to `THREAD_PRIORITY_TIME_CRITICAL` (equivalent to Linux `setpriority(-19)`)
2. `fd_tile_private_cpu_restore`: restore saved priority
3. `fd_log_private_cpu_id`: use `GetCurrentProcessorNumber()` (Windows 8+) or `GetCurrentProcessorNumberEx()` (Windows 8.1+)
4. `fd_log_private_main_stack_sz`: detect via `_resetstkoflw` probe or thread stack limits

### Phase 5: Boot Sequence

**File**: `src/util/tile/fd_tile_threads_platform_windows.c`

Replace `fd_tile_private_boot`:

1. Parse `--tile-cpus` / `FD_TILE_CPUS` env (same as Linux)
2. Create one thread per tile index 1..tile_cnt-1 via `CreateThread`
3. Each thread runs `fd_tile_private_manager` (Windows version)
4. Wait for all threads to reach IDLE state before returning
5. Tile 0 runs in the main thread (same as Linux)

Replace `fd_tile_private_halt`:

1. Signal all tiles to HALT
2. Wait for each thread via `WaitForSingleObject` with timeout
3. `TerminateThread` as last resort if a thread doesn't respond
4. Clean up resources

---

## Verification

### Unit Tests
1. Update `test_cpu_topo_platform_windows.c` — verify real CPU count, not 1
2. Update `test_tile_threads_platform_windows.c` — verify `fd_tile_exec_new` returns non-NULL for idx >= 2, stack is non-NULL

### Smoke Test
3. Build on Windows: `zig build -Dtarget=x86_64-windows -Dmode=debug`
4. Run with `--tile-cpus 0-3` and verify 4 tile threads start
5. Verify `fd_tile_cnt()` returns expected count
6. Verify `fd_tile_cpu_id(tile_idx)` returns valid CPU index

### CI
7. Add Windows build+test step if not present (check `tests-short.yml` / CI config)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Windows API changes across versions | Use runtime detection (`GetProcAddress`) for newer APIs, fall back to older equivalents |
| SRWLOCK vs pthread_mutex ABI | SRWLOCK is part of Windows kernel32 — stable API, no compat concerns |
| Thread stack limits on Windows | Default Windows thread stack is 1MB (same as stub), but `VirtualAlloc` approach gives full control |
| NUMA topology detection complexity | Start with single-group, single-NUMA fallback; `GetGroupInformation` for multi-group |
| `SetThreadGroupAffinity` availability | Windows XP+; only concern is Windows Server 2003 (EOL, not supported) |

---

## File Change Summary

| File | Change Type | Lines Changed (est) |
|------|-------------|-------------------|
| `src/disco/topo/fd_cpu_topo_platform_windows.c` | Replace stub with functional impl | 19 → ~120 |
| `src/util/tile/fd_tile_threads_platform_windows.c` | Replace stub with functional impl | 129 → ~500 |
| `src/util/tile/test_tile_threads_platform_windows.c` | Update unit tests | +50 |
| `src/disco/topo/test_cpu_topo_platform_windows.c` | Update unit tests | +30 |

---

## Implementation Order

1. CPU topology (`fd_cpu_topo_platform_windows.c`) — no dependencies
2. Stack allocation (`fd_tile_private_stack_new/delete`) — needed before threading
3. Tile execution framework (`fd_tile_private_manager`, SRWLOCK, state machine)
4. CPU config & logging helpers
5. Boot/halt sequence wiring
6. Test updates

---

## Industry Reference

This approach follows Firedancer's own platform-split pattern:
- Linux: `fd_tile_threads_platform_linux.c` — full POSIX threads, `sched_setaffinity`, `mmap` stacks
- macOS: `fd_tile_threads_platform_macos.c` — delegates to Linux source with `__MACH__` guards
- Windows: `fd_tile_threads_platform_windows.c` — Win32 API equivalent (this fix)

The functional Linux implementation is the reference. Windows uses equivalent Win32 APIs:

| Linux | Windows | Purpose |
|-------|---------|---------|
| `pthread_create` | `CreateThread` | Thread creation |
| `pthread_attr_setaffinity_np` | `SetThreadGroupAffinity` | CPU pinning |
| `sched_getcpu` | `GetCurrentProcessorNumber` | CPU ID |
| `mmap` (stack) | `VirtualAlloc` | Stack allocation |
| `munmap` | `VirtualFree` | Stack deallocation |
| `setpriority` | `SetThreadPriority` | Thread priority |
| `pthread_mutex` | `SRWLOCK` | Tile locking |
| `pthread_join` | `WaitForSingleObject` | Thread wait |
| `prctl(PR_SET_NAME)` | `SetThreadDescription` | Thread naming |
