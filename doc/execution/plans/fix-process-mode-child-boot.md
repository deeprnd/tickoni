# Fix: Process-Mode Child Tile Boot Failure

**Status:** Assessed. Fix planned.

**Root cause:** The child's `tile_process.zig.run()` rebuilds the topology identically to the parent but **does not attach to the shared workspace**. After `topo_build.build()`, the child has correct offsets but a null workspace pointer. When `fd_topo_run_tile()` (Firedancer C) runs, `fd_topo_fill_tile()` resolves mcache/dcache/fseq from null/wrong addresses, the work function sees empty links and returns instantly, and `fd_tile_private_halt` tears everything down silently.

**Secondary risk:** `FD_APP_NAME` compile-time constant mismatch may cause `fd_topo_join_workspace` to look for `firedancer_tkpay0.wksp` instead of `tickoni_tkpay0.wksp`.

---

## Assessment

### What's Already Correct (Firedancer C-code IS being used)

**This is not a "we're not using Firedancer" problem.** Every critical component dispatches to Firedancer C-code:

| Component | Tickoni Zig | Firedancer C | Verified |
|-----------|------------|--------------|----------|
| Topology builder | `topo_build.zig` calls `topobNew/Link/Tile/Finish` | `fd_topob_new/link/tile/finish` | Confirmed |
| Tile launcher | `tile_process.zig` calls `runTileSimple` | `shim/tile_run.c` calls `fd_topo_run_tile` | Confirmed |
| Workspace join | Inside `fd_topo_run_tile` → `fd_topo_join_workspace` | Same | Confirmed |
| Link filling | Inside `fd_topo_run_tile` → `fd_topo_fill_tile` | Same | Confirmed |
| Privileged init | `tk_tile_privileged_init` callback | `fd_topo_run_tile` calls `priv_init` | Confirmed |
| Run loop | `tk_tile_run` callback | `fd_topo_run_tile` calls `run` callback | Confirmed |
| Callback adapter | `topo_run.zig` → `shim/topo_run.c` → `shim/tile_run.c` | `fd_topo_run_tile_t` struct | Confirmed |

The Zig code is a thin glue layer. The actual topology construction, workspace joining, link filling, and tile lifecycle are all Firedancer C.

### What's Correctly Reimplemented (Intentional Differences)

1. **Self-exec topology rebuild** — Both parent and child independently call `topo_build.build()` with identical inputs. This is the Firedancer self-exec convention. Correct.

2. **TopologySpec serialization** — `topology_spec.zig` serializes the Tickoni Topology (tiles + channels) to a compact versioned binary struct, written by supervisor, read by child. This replaces Firedancer's YAML config parsing with a simpler binary format. Correct.

3. **LaunchSpec serialization** — `launch_spec.zig` carries per-tile bootstrap data (tile ID, CPU placement, workspace name, cnc gaddr, link handles, shmem path, heartbeat config, kind_id_offset). Correct.

4. **Normal pages instead of huge pages** — Firedancer uses `fd_topo_create_workspace` (huge/gigantic pages via `fd_shmem_create_multi`). Tickoni uses `wkspNewNamed` (normal pages) because huge pages are not always available. The `topoWkspSetPtr` + `topoWkspNew` pattern is the Tickoni workaround for this constraint. Documented and intentional.

### What's Reimplemented (Firedancer run1.c path NOT used)

Firedancer's launch orchestration in `src/app/shared/commands/run/run.c` → `run1.c` uses:
- `clone()` with stack allocated in shared memory
- PID namespaces for sandboxing
- seccomp filters
- XDP file descriptor passing
- cgroup isolation
- `execve` with tile name, kind_id, pipe_fd, config_fd arguments

Tickoni cannot use this because it needs macOS/Windows support. Instead, Tickoni uses:
- `execv` with `__tile-run` command + spec file path argument
- No PID namespaces, no seccomp, no XDP, no cgroups
- Normal page stack allocation

**Impact:** For dev/test, this is fine. For production, these are real security gaps (no sandbox, no isolation). The child tile boot bug is **NOT** caused by this difference — it's caused by the missing workspace attachment described below.

### The Missing Piece (The Bug)

**The child's `tile_process.zig.run()` does NOT attach to the shared workspace after rebuilding the topology.**

Parent (`supervisor.zig` lines 306-328):
```zig
// 1. Create named shmem region (normal pages)
wkspNewNamed(workspace_name_z, ..., part_max);
// 2. Attach to it
wksp = wkspAttach(workspace_name_z);
// 3. Inject ptr into topology
topoWkspSetPtr(built_topo.topo, built_topo.wksp_idx, wksp);
// 4. Instantiate objects (mcache/dcache/fseq/metrics/cnc)
topoWkspNew(built_topo.topo, built_topo.wksp_idx);
```

Child (`tile_process.zig` lines 176-204):
```zig
// 1. Rebuild topology (correct offsets)
built = topo_build.build(...);
// 2. Find this tile
tile_idx = topoFindTile(...);
// 3. Skip workspace attachment entirely!
// 4. Call into Firedancer
runTileSimple(built.topo, tilePtr);
```

When `runTileSimple()` → `fd_topo_run_tile()` runs:
1. `fd_topo_join_workspace()` — may fail silently if the workspace name resolves wrong (see FD_APP_NAME below)
2. `fd_topo_fill_tile()` — reads mcache/dcache/fseq addresses from topo, but they resolve to null/wrong because the workspace isn't attached
3. Registers callbacks, runs `privileged_init` (cnc join works — offsets are correct)
4. Runs `run()` — work function sees empty/invalid links, returns instantly (0 events)
5. `fd_tile_private_halt` — tears everything down silently

### Secondary Risk: FD_APP_NAME Mismatch

Firedancer's `fd_topo_join_workspace` constructs the workspace name as `"%s_%s.wksp"` using `FD_APP_NAME` (compile-time constant). In Firedancer, `FD_APP_NAME` = "firedancer". In Tickoni, the topology's `app_name` field is set to "tickoni" via `topobNew(topo, "tickoni")`.

If `fd_topo_join_workspace` uses `FD_APP_NAME` instead of the topology's stored `app_name`, the child will look for `firedancer_tkpay0.wksp` instead of `tickoni_tkpay0.wksp` — the workspace join fails, and everything downstream breaks.

**Need to verify:** What does `fd_topo_join_workspace` actually use? `FD_APP_NAME` or `topo->app_name`?

---

## Fix

### Change 1: `src/tickoni/runtime/tile_process.zig` — Attach workspace in child boot path

After `topo_build.build()` (line 176-180), before `runTileSimple()` (line 204), add workspace attachment:

```zig
// v2.14.S8.T12: the child must also attach to the real workspace.
// topo_build.build() only builds the in-memory description; the real
// workspace is created by the supervisor and exists at the concrete
// name "tickoni_<name>.wksp".
var wksp_name_z_buf: [rt.topo_build.concrete_workspace_name_cap]u8 = undefined;
const wksp_name_z = try rt.topo_build.concreteWorkspaceName(&wksp_name_z_buf, spec.workspace_name.slice());
const wksp = c_abi.wksp.wkspAttach(wksp_name_z) orelse {
    std.debug.print("tile_process: failed to attach to workspace {s} for tile {d}\n", .{ wksp_name_z, spec.tile_idx });
    return 1;
};
c_abi.topob.topoWkspSetPtr(built_topo.topo, built_topo.wksp_idx, wksp);
c_abi.topob.topoWkspNew(built_topo.topo, built_topo.wksp_idx);
```

This mirrors what the parent does at supervisor.zig lines 327-328.

### Pre-requisite: Verify FD_APP_NAME behavior

**Before implementing Change 1**, verify whether `fd_topo_join_workspace` uses `FD_APP_NAME` (compile-time) or the topology's stored `app_name` (runtime). This determines whether we also need to ensure the build compiles with `-DFD_APP_NAME="tickoni"`.

Check:
- `src/disco/topo/fd_topo.c` line for `fd_topo_join_workspace` — does it reference `FD_APP_NAME` or `topo->app_name`?
- `build.zig` — is `FD_APP_NAME` set to "tickoni"?

If `fd_topo_join_workspace` uses `FD_APP_NAME` and it's not set to "tickoni", add a **Change 0**: set `-DFD_APP_NAME="tickoni"` in the build.zig target that compiles `fd_topo_run.c` / `fd_topo.c` / `fd_topob.c`.

### Verification of the fix

The fix is safe because:
1. `wkspAttach` joins the same named region the parent created — the naming convention is identical (`concreteWorkspaceName` produces `tickoni_<name>.wksp`)
2. `topoWkspSetPtr` is explicitly designed for this — topob.zig comment says: "fd_topo_create_workspace hard-requires huge/gigantic pages... Tickoni reuses that and backs the memory with its own normal-page wksp... topoWkspNew's .new callbacks only need topoWkspPtr to be non-null"
3. `topoWkspNew` re-runs the same `.new` callbacks (mcache/dcache/fseq/cnc) at the same offsets — the child gets valid object pointers
4. After this, `fd_topo_fill_tile` in `fd_topo_run_tile` will resolve mcache/dcache/fseq correctly from the shared workspace

### Secondary verification: `tk_tile_run` already checks for null wksp

`tile_process.zig` line 106-110:
```zig
const wksp = c_abi.topob.topoWkspPtr(topo_typed, g_ctx.wksp_idx) orelse {
    const log = logger.get();
    log.err("tile_process", "tk_tile_run", "workspace not joined") catch {};
    std.process.exit(1);
};
```

This is the `wksp` that `work()` receives. If the wksp isn't attached, this exits with a clear error. With the fix in place, this will succeed.

---

## Files Affected

| File | Change |
|------|--------|
| `src/tickoni/runtime/tile_process.zig` | Add `wkspAttach` + `topoWkspSetPtr` + `topoWkspNew` after `topo_build.build()`, before `runTileSimple()` |
| `build.zig` (possible) | Add `-DFD_APP_NAME="tickoni"` if `fd_topo_join_workspace` uses `FD_APP_NAME` |

## Files Verified (no changes needed)

| File | Reason |
|------|--------|
| `src/app/tickoni/supervisor.zig` | Parent workspace creation is correct; child fix mirrors parent |
| `src/tickoni/runtime/topo_build.zig` | `build()` correctly builds in-memory description only |
| `src/tickoni/c_abi/topob.zig` | `topoWkspSetPtr`/`topoWkspNew` already exist and are the correct pattern |
| `src/tickoni/c_abi/topo_run.zig` | `runTileSimple()` correctly dispatches to upstream `fd_topo_run_tile` |
| `src/tickoni/c_abi/shim/tile_run.c` | `TK_TILE_RUN` struct with callbacks is correct |
| `src/tickoni/runtime/topology_spec.zig` | Serialization round-trip is correct |
| `src/tickoni/runtime/launch_spec.zig` | Handoff fields are correct |
| `src/disco/topo/fd_topo_run.c` | Verified — Firedancer C implementation |
| `src/disco/topo/fd_topo.c` | Verified — workspace join logic |
| `src/disco/topo/fd_topob.c` | Verified — topology builder |
| `src/app/shared/commands/run/run.c` | Verified — Firedancer launch orchestration (not used by Tickoni) |
| `src/app/shared/commands/run/run1.c` | Verified — Firedancer child boot (not used by Tickoni) |

## Risk

- **None for Change 1.** This is a straightforward symmetry fix: the parent does X, the child must also do X. The parent already proves the pattern works (thread-mode tests pass). No new logic, no new dependencies, no behavioral changes.
- **Low for Change 0 (FD_APP_NAME).** Only needed if `fd_topo_join_workspace` references `FD_APP_NAME`. Build change, no runtime logic change.

## Testing

1. Build succeeds
2. `zig build test` unit tests pass (topo_build, launch_spec, topology_spec tests already exist)
3. Integration tests that use process-mode should transition from SKIP/FAIL to PASS
4. Verify that tile processes now produce events (metrics snapshot shows non-zero produced/normalized/audited counts)

---

## Execution Plan

0. **Verify FD_APP_NAME** — Read `fd_topo_join_workspace` in `fd_topo.c` and `build.zig` to determine if `FD_APP_NAME` affects Tickoni workspace name resolution. If needed, set `-DFD_APP_NAME="tickoni"`.
1. Add `var wksp_name_z_buf` declaration to `tile_process.zig.run()` after `topo_build.build()`
2. Add `wkspAttach` call with error handling (debug print)
3. Add `topoWkspSetPtr` + `topoWkspNew` calls
4. Build to verify compilation
5. Run unit tests
6. Run integration tests to verify process-mode tiles produce events

---

## Context: Firedancer vs Tickoni Architecture

**The question "why not just use Firedancer C-code" is already answered: we do, for every critical path.** The topology builder, tile launcher, workspace join, link filling, and tile lifecycle are all Firedancer C. Tickoni's Zig is the glue layer.

The differences are intentional product constraints:

| Concern | Firedancer | Tickoni | Reason |
|---------|-----------|---------|--------|
| Config format | YAML config file | Binary TopologySpec + LaunchSpec | No YAML dependency |
| Workspace pages | Huge/gigantic pages | Normal pages | Huge pages not always available |
| Launch orchestration | `run1.c` (clone + PID ns + seccomp) | `execv` + spec files | Needs macOS/Windows |
| Sandbox | PID namespaces + seccomp + cgroups | None (dev/test) | macOS/Windows don't support Linux namespaces |
| Tile count | Hundreds (Solana validator) | 8-14 (financial pipeline) | Different scale |

The launch orchestration reinvention does mean Tickoni lacks PID namespaces, seccomp, and cgroup isolation that Firedancer has. For production financial use, this should be addressed. But it is **not** the cause of the child boot bug.
