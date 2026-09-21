# Plan: Integrate metric + metric_in Workspaces into Tickoni Topology

**Story**: v2.15.S10 (metric + metric_in workspace integration)
**Created**: 2026-09-21
**Status**: planned

---

## Problem Statement

Tickoni's `topo_build.build()` creates only one workspace called `"metric"` and passes it as every tile's `metrics_wksp` parameter to `fd_topob_tile()`. Firedancer uses two distinct workspaces:

| Firedancer workspace | Purpose |
|---|---|
| `"metric"` | Tile workspace for the metric tile's own data objects |
| `"metric_in"` | Shared workspace for ALL tiles' FD_MGAUGE gauge data |

In Firedancer's model, every tile gets:
1. A `"metrics"` **object** (not workspace) inside `"metric_in"` — this is where FD_MGAUGE pointers resolve via `fd_topo_fill_tile()`
2. Its own tile workspace for `"tile"` / `"cnc"` objects
3. Link workspaces shared between producer-consumer pairs

Tickoni currently creates only `"metric"` and passes it as `metrics_wksp`. The supervisor then calls `topoFindWksp("metrics")` which returns 0 — a hardcoded workspace name that never exists. This causes `MetricsWkspNotFound` and crashes before any tile can run.

---

## Target Architecture

```
fd_topo_t (Firedancer topology)
├── workspaces[0] = "metric"          ← tile wksp for the metric tile
├── workspaces[1] = "metric_in"       ← SHARED metrics workspace for ALL tiles' FD_MGAUGE
├── workspaces[2] = "tkpay0"          ← channel tile workspace
├── objects[...]
│   ├── obj[0] = "metrics" in wksp[1] ("metric_in")  ← tile 0's gauge target
│   ├── obj[1] = "tile" in wksp[2] ("tkpay0")
│   ├── obj[2] = "metrics" in wksp[1] ("metric_in")  ← tile 1's gauge target
│   └── obj[3] = "tile" in wksp[2] ("tkpay0")
└── tiles[...]
    ├── tile[0] = "tkings": tile_wksp=wksp[2], metrics_wksp=wksp[1]
    └── tile[1] = "tkaudt": tile_wksp=wksp[2], metrics_wksp=wksp[1]
```

The supervisor must:
1. Create a real shared-memory workspace backed by `"metric_in"`
2. Set it as the workspace pointer for `metrics_wksp` (wksp_idx of `"metric_in"`)
3. Call `topoWkspNew()` on it to instantiate gauge objects

---

## Implementation Steps

### Step 1: Create both workspaces in `topo_build.build()`

**File**: `src/tickoni/runtime/topo_build.zig`

In `build()`, register `"metric"` and `"metric_in"` workspaces in the correct order, matching Firedancer's `fd_topob_wksp()` call sequence. Return both workspace indices in `BuiltTopo`:

```zig
// In BuiltTopo struct:
pub const BuiltTopo = struct {
    // ... existing fields ...
    metrics_wksp_idx: usize = 0,  // "metric_in" — shared gauge workspace
    metric_tile_wksp_idx: usize = 0,  // "metric" — metric tile's own workspace
};

// In build():
const metric_tile_wksp_idx = c_abi.topob.topobWksp(topo, "metric");
const metrics_wksp_idx = c_abi.topob.topobWksp(topo, "metric_in");

// Pass "metric_in" (not "metric") as every tile's metrics_wksp:
const metrics_wksp_z = toZ(&metrics_wksp_buf, "metric_in");
const tile_id = c_abi.topob.topobTile(topo, toZ(&tile_name_buf, t.id.slice()), wksp_name_z, metrics_wksp_z, 0);

// Return both in BuiltTopo:
return .{
    .metrics_wksp_idx = metrics_wksp_idx,
    .metric_tile_wksp_idx = metric_tile_wksp_idx,
    // ...
};
```

**Verify**: Run `zig build unit-test-all` — the existing topology tests should still pass (same construction order, just an extra workspace).

### Step 2: Fix supervisor to create and attach `"metric_in"` workspace

**File**: `src/app/tickoni/supervisor.zig`

Replace the broken `"metrics"` lookup with the actual `metrics_wksp_idx` returned from `build()`:

```zig
// Remove:
// const metrics_wksp_id = c_abi.topob.topoFindWksp(built_topo.topo, "metrics");
// if (metrics_wksp_id == 0) return error.MetricsWkspNotFound;

// Use the index directly from built_topo:
const metrics_wksp_id = built_topo.metrics_wksp_idx;

// Create and attach the metric_in workspace:
var metrics_wksp_name_z_buf: [rt.topo_build.concrete_workspace_name_cap]u8 = undefined;
const metrics_wksp_name_z = try rt.topo_build.concreteWorkspaceName(
    &metrics_wksp_name_z_buf, "metric_in");

const metrics_footprint = c_abi.topob.topoWkspFootprint(
    built_topo.topo, metrics_wksp_id);
const metrics_page_cnt = metrics_footprint /
    c_abi.wksp.shmem_normal_page_sz + 8;

// ... wkspNewNamed + wkspAttach + topoWkspSetPtr ...

c_abi.topob.topoWkspSetPtr(built_topo.topo, metrics_wksp_id, metrics_wksp);
c_abi.topob.topoWkspNew(built_topo.topo, metrics_wksp_id);
```

**Key change**: No more `topoFindWksp("metrics")`. The supervisor now uses the exact `metrics_wksp_idx` that `build()` computed during topology construction. This is the same pattern Firedancer uses internally.

### Step 3: Wire the metric tile (`tkmetr`) into the payment topology

**File**: `src/app/tickoni/topologies.zig`

The `paymentPipeline` and `paymentPipelineProcess` topologies currently define 2 tiles (`tkings` + `tkaudt`). To have a working metric tile:

1. Add `tkmetr` as a third tile in the payment topology
2. The metric tile has no channel wiring — it only reads FD_MGAUGE data from the shared `"metric_in"` workspace
3. Verify the tile registry has `tkmetr` registered

This is a **minimal addition** — the metric tile's sole job in V1 is to read and surface gauges. It doesn't participate in the event pipeline.

### Step 4: Write integration test

**File**: `src/tickoni/test/integration/test_process_metrics.zig`

The test should:
1. Start `startPaymentPipelineProcess` with `tkings` + `tkaudt` + `tkmetr`
2. Inject events through `tkings`
3. Verify the metric tile can read gauges written by the other tiles
4. Verify no `MetricsWkspNotFound` or NULL `metrics_ptr` errors

### Step 5: Update `BuiltTopo` consumer code

**File**: Any code that references `built_topo.metrics_wksp_idx` must be checked:

- `src/app/tickoni/supervisor.zig` — Step 2 covers this
- Any test code that builds topologies and expects the metrics workspace
- Any replay substitution logic that needs metrics workspace access

---

## Firedancer Reference Points

### Workspace creation order (`topology.c` lines 420-454)

```c
fd_topob_wksp(topo, "metric");     // index 0 — metric tile's own workspace
fd_topob_wksp(topo, "diag");
// ... other workspaces ...
fd_topob_wksp(topo, "metric_in");  // later index — SHARED gauge workspace
```

### Tile registration (`topology.c` lines 654-691)

Every tile uses `"metric_in"` as `metrics_wksp`:

```c
fd_topob_tile(topo, "quic",   "quic",    "metric_in", ...);
fd_topob_tile(topo, "metric", "metric",  "metric_in", ...);
fd_topob_tile(topo, "diag",   "diag",    "metric_in", ...);
// ... all other tiles follow the same pattern ...
```

### Object creation (`fd_topob.c` lines 185-191)

```c
// Inside fd_topob_tile():
fd_topo_obj_t * tile_obj = fd_topob_obj(topo, "tile", tile_wksp);
fd_topo_obj_t * obj = fd_topob_obj(topo, "metrics", metrics_wksp);
```

The `"metrics"` string is an **object name** inside `metrics_wksp`, not a workspace name.

### Gauge access (`fd_topo_fill_tile`)

`fd_topo_fill_tile()` uses `tile->metrics_obj_id` to find the `"metrics"` object, then resolves its `wksp_id` to get the pointer. The gauge pointers (`TILE->metrics_ptr`) point into the `"metric_in"` workspace.

---

## Risk & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| `topoWkspFootprint` returns wrong size for `metric_in` | Workspace allocation fails | Use same pattern as channel wksp: `footprint / page_sz + headroom` |
| Child tiles can't join `metric_in` workspace | Tiles crash at startup | `fd_topo_run_tile()` auto-joins via `fd_topo_join_workspace()` using the topology's app_name + workspace name convention — same as channel wksp |
| Metric tile has no channel wiring | No way to inject events | Metric tile reads gauges, not channels. It doesn't need event injection. |
| `BuiltTopo.metrics_wksp_idx` is 0 (unset) | Supervisor crashes with NULL pointer | The `build()` function always creates both workspaces — index is never 0 unless topology construction fails entirely |

---

## Verification Checklist

- [ ] `zig build build-all` passes with new workspace creation
- [ ] `zig build unit-test-all` passes — topology tests validate object layout
- [ ] `zig build integration-test` passes — `test_process_metrics` runs without `MetricsWkspNotFound`
- [ ] Supervisor logs show `"metric_in"` workspace created and attached
- [ ] Child tile processes join `metric_in` successfully (no attach failures in logs)
- [ ] `FD_MGAUGE_SET` calls in tiles write to non-NULL `metrics_ptr`
- [ ] Metric tile can read gauge data from other tiles' `metrics_ptr`
- [ ] Replay test (`test_process_demo_parity`) passes — gauges are substitutable
- [ ] `just test-*` gate passes if it covers integration tests

---

## Out of Scope

- Metric tile UI/API integration — handled by CaseOps and `tkapi`, not this plan
- Metric tile model integration — model access goes through `tkmodl`
- Metric tile execution integration — metrics are read-only observation
- Firedancer upstream changes — all changes are in `deeprnd/tickoni` only
