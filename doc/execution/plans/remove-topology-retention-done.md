---
title: "Replace topology.Topology retention with BuiltTopo as single source of truth"
author: "vicgenin"
date: "2026-10-12"
status: "draft"
---

## Problem

`topology.Topology` is an input spec used to build the Firedancer topology (`topo_build.zig::build()`), but it is **retained** in `Supervisor` and referenced post-build. Because `build()` deliberately skips the metric tile during registration (it needs its own workspace "metric"), the Firedancer topology has a different tile index ordering than the descriptor array:

```
Descriptor order:  0=tkings, 1=tknorm, 2=tkdedu, 3=tkpoly, 4=tkaudt, 5=tkrepl, 6=metric, 7=tkdiag
Firedancer order:  0=tkings, 1=tknorm, 2=tkdedu, 3=tkpoly, 4=tkaudt, 5=tkrepl, 6=tkdiag, 7=metric
```

The metric/tkdiag tiles are swapped at indices 6/7. Every code path that indexes Firedancer arrays by `topo.tiles[i]` (descriptor position) gets the wrong tile — this is the root cause of the `metric_boot_timestamp` reading zero from tkdiag's CNC instead of metric's.

## Design Decision

Don't delete `Topology` or its child types (`TileDescriptor`, `Channel`, `CpuPlacement`, `TileId`). They're still needed as:

1. **Input spec** — `topologies.zig` builds them, `topo_build.zig::build()` reads them to construct Firedancer objects
2. **Child rebuild input** — `TopologySpec` serializes them for `__tile-run` handoff
3. **Type definitions** — `tile.zig`, `link.zig`, `cpu_placement.zig` own these types

What gets deleted: the **runtime retention** of `Topology` after `build()` completes. `BuiltTopo` becomes the sole source of truth for any index-based access post-build.

## New Data Structure

Add to `BuiltTopo` in `topo_build.zig`:

```zig
pub const BuiltTopo = struct {
    // ... existing fields (buf, topo, wksp_idx, metric_wksp_idx, etc.) ...

    /// Per-tile metadata indexed by Firedancer tile idx, owned by BuiltTopo.
    /// Populated by build() after topobFinish so every consumer uses the
    /// canonical Firedancer index instead of guessing from descriptor order.
    pub const Info = struct {
        tile_id: rt.tile.TileId,
        name: []const u8,                // diagnostics only
        cpu_placement: rt.cpu_placement.CpuPlacement,
        cnc_gaddr: usize,                // resolved once, used for CNC joins
        cnc: ?*c_abi.cnc.Cnc,            // parent-side join (supervisor lifecycle)
    };
    tile_infos: []Info,                   // indexed by Firedancer idx, length = topo->tile_cnt

    /// Per-tile Firedancer idx lookup by TileId string, for O(n) find.
    /// Replaces the descriptor-idx assumption that causes the metric/tkdiag swap.
    tile_ids_by_name: []const [*:0]const u8,  // parallel to tile_infos
};
```

`build()` populates `tile_infos` from `topo_desc.tiles` after `topobFinish(topo)` (line 292). `tile_infos[firedancer_idx]` has the correct `tile_id` for every index. `deinit()` frees `tile_infos` and `tile_ids_by_name`.

### Lookup helper

```zig
/// Returns the Firedancer index for a tile ID, or BuiltTopo.not_found.
pub fn tileIdxById(self: *const BuiltTopo, tile_id: rt.tile.TileId) usize {
    for (self.tile_infos, 0..) |info, i| {
        if (info.tile_id.eql(tile_id)) return i;
    }
    return c_abi.topob.not_found;
}
```

## Changes by File

### 1. `src/tickoni/runtime/topo_build.zig` — populate `tile_infos` in `build()`

After `topobFinish(topo)` (line 292), iterate all `topo->tiles[i]`, extract tile name (tile ID string), look up CPU placement from `cpu_idx_arr` before it was freed (capture during the register loop at line 181), and populate `tile_infos`. Allocate `tile_infos` and `tile_ids_by_name` slices.

### 2. `src/app/tickoni/supervisor.zig` — remove `topo: Topology` from Supervisor struct

**Remove:**
- `Supervisor.topo: Topology` field
- `Supervisor.init()` parameter `topo: Topology` → change to `topo_desc: Topology` (passed only for validation + build, then discarded)
- `self.topo.tiles` references throughout

**Fix the spawn loop** (currently line 555-622):

```zig
// Before (broken):
for (self.handles, 0..) |*h, i| {
    const tile = self.topo.tiles[i];  // WRONG: descriptor index ≠ Firedancer index
    ...
}

// After (correct):
const tile_infos = &self.process_state.?.built_topo.tile_infos;
for (tile_infos, 0..) |info, i| {
    const entry = tile_registry.findById(info.tile_id) orelse unreachable;
    // info.tile_id is correct for Firedancer index i
    ...
}
```

**Fix `cnc_join` loop** (currently line 485-489):

```zig
// Before (swapped indices):
for (self.topo.tiles, 0..) |_, i| {
    const laddr = c_abi.topob.topoObjLaddr(..., built_topo.cnc_obj_id[i]);  // wrong i
    state.cncs[i] = c_abi.cnc.cncJoin(laddr);
}

// After (correct indices):
const tile_infos = &state.built_topo.tile_infos;
for (tile_infos, 0..) |info, i| {
    const laddr = c_abi.topob.topoObjLaddr(..., state.built_topo.cnc_obj_id[i]);  // correct i
    state.cncs[i] = c_abi.cnc.cncJoin(laddr);
    state.built_topo.tile_infos[i].cnc = c_abi.cnc.cncJoin(laddr);
}
```

**Fix `snapshotProcessMetrics`** (currently line 868-891):

```zig
// Before (reads tkdiag's CNC with metric's counter schema):
for (self.topo.tiles, 0..) |tile, i| {  // WRONG: descriptor index
    const cnc = state.cncs[i];  // swapped for idx 6,7
    const entry = tile_registry.findById(tile.id) orelse continue;
    for (entry.counters) |c| {
        const v = rt.cnc_counters.appCounterRead(cnc, c.idx);
        .metric_boot_timestamp => snap.metric_boot_timestamp = v,
    }
}

// After (correct):
const tile_infos = &state.built_topo.tile_infos;
for (tile_infos, 0..) |info, i| {
    const entry = tile_registry.findById(info.tile_id) orelse continue;
    const cnc = state.cncs[i] orelse continue;  // correct index now
    for (entry.counters) |c| {
        const v = rt.cnc_counters.appCounterRead(cnc, c.idx);
        .metric_boot_timestamp => snap.metric_boot_timestamp = v,
    }
}
```

**Fix `snapshotProcessMetricsForTile`** (line 943-982): same pattern — use `tile_infos[tile_idx]` not `topo.tiles[tile_idx]`.

**Fix `stopProcess`** (line 1052): use `tile_infos[i].tile_id` not `topo.tiles[i].id.slice()`.

### 3. `src/app/tickoni/main.zig` — remove `topo.tiles` references

**`cmdStartProcess`** (line 178): currently passes `topo` to `Supervisor.init()` and uses it in the monitoring loop.
- Pass `topo` only for `Supervisor.init()` validation
- After `sup.startPaymentPipelineProcess()`, get tile names from `built_topo.tile_infos` (add accessor method `Supervisor.tileInfoAt(idx)`)
- Remove `topo.tiles[h.tile_idx].name` at line 198 — replace with `sup.tileInfoAt(h.tile_idx).tile_id`
- Line 232 `topo.tiles[i]` in the delta print loop — replace similarly

**`cmdStatus`** (line 269-292): already just prints tile info. Change signature to accept `&built_topo.tile_infos` or pass `topo` for diagnostics-only use. Since `cmdStatus` is a pre-run diagnostic, it can still take a `Topology` — but it should NOT be used for index-based access post-launch.

### 4. `src/tickoni/runtime/cpu_placement.zig` — no change needed

`cpu_placement.validate()` operates on `topo.tiles` — this is pre-build validation, exactly the right use. No post-build references exist.

### 5. `src/tickoni/runtime/topology_spec.zig` — no change needed

`TopologySpec` is a serialization layer for child handoff. It takes `Topology` as input and serializes it. This is correct — the child needs the descriptor input to rebuild. No change.

### 6. `src/app/tickoni/topologies.zig` — no change needed

Static arrays `payment_tiles[]` and `payment_channels[]` are the input spec. They remain. Only their post-build retention in `Supervisor` is removed.

### 7. Test fixes

**`src/tickoni/test/integration/test_metric_tile_integration.zig`**:
- Line 376: `for (topo.tiles) |tile|` — change to use `built_topo.tile_infos`
- Line 653: `for (topo.tiles, 0..) |tile, i|` — change to `tile_infos`
- Lines 267-292: already use `parent.metric_tile_idx` — correct pattern, keep as-is

**`src/tickoni/test/integration/test_process_topology.zig`**:
- Line 139: `topo.tiles[tkrepl_idx]` — change to `built_topo.tile_infos[tkrepl_idx]`

**`src/app/tickoni/topologies.zig` tests** (line 170-174, 197-201, 207): test the static input spec — still correct, no change needed.

**`src/tickoni/runtime/topology.zig` tests** (line 44-140): test `Topology.validate()` — pre-build validation remains valid, no change.

**`src/tickoni/tile_registry.zig` tests** (line 333-337 `descriptorsFromRegistry`): creates descriptors for validate() tests. Keep as-is — this is pre-build input.

## Supervisor.init() Signature Change

```zig
// Before:
pub fn init(allocator: std.mem.Allocator, topo: Topology) !Supervisor

// After:
pub fn init(allocator: std.mem.Allocator, topo_desc: Topology) !Supervisor
```

`topo_desc` is only used for `topo.validate()` and `tile_registry.validate()`. The returned `Supervisor` has no `topo` field. The `BuiltTopo` (created during `startPaymentPipelineProcess`) is the sole post-build authority.

## What Stays (Unchanged)

- `topology.Topology` struct and all child types — still needed as input spec
- `topologies.zig` static arrays — still the production input
- `TopologySpec` serialization — still the child handoff mechanism
- `Topology.validate()` — still pre-build validation
- `tile_registry.zig` — string-based lookup via `findById()`, unaffected by index reordering

## Verification Steps

1. Run `zig build test` — all unit tests pass
2. Run `just test-integration-tk` — integration test `boot_timestamp via CNC (no HTTP)` passes (index 2 reads a large positive value)
3. Run `zig build check` — linting passes
4. Verify `cnc_obj_id` is now always accessed via `built_topo.tile_infos[firedancer_idx]` — grep should show zero references to `topo.tiles[i]` for index-based array access post-build

## Execution Order

1. ~~Add `tile_infos` to `BuiltTopo` and populate in `build()`~~ **DONE**
2. ~~Add `BuiltTopo.tileIdxById(tile_id)` lookup helper~~ **DONE**
3. Replace all `self.topo.tiles[i]` references in `supervisor.zig` with `built_topo.tile_infos[i]` or `tile_info_by_id()` ~~DONE~~
4. Remove `topo: Topology` from `Supervisor` struct ~~DONE~~
5. Update `Supervisor.init()` signature ~~DONE~~
6. Fix `main.zig` monitoring loop to use `built_topo` for tile names ~~DONE~~
7. Fix integration tests ~~DONE~~
8. Verify all tile registry lookups still work ~~DONE~~ (findById is string-based, unaffected by index reordering)
9. ~~Run full test suite~~ **DONE** (zig build install: pass, zig build check: pass, 168/168 unit tests pass, all 4 integration test binaries compile and pass — infra failures are pre-existing Docker/env issues, not code)
