# Doc Alignment Plan: Thread Mode Removal + Metric Tile + Security Boundary

**Status:** In Progress
**Date:** 2026-09-30
**Trigger:** Thread/dev/test mode has been removed from codebase (commit `8da46501a`), but docs still reference it. Metric tile (`tkmetr`/`metric`) is fully wired in code but described inconsistently. Overall doc-to-code drift needs tightening.

---

## Why Process-Only (No Thread/Dev/Test Mode)

The thread/dev/test mode was removed because:

1. **Security isolation requirement:** LLM, UI, and 3rd-party services must be fully isolated from Firedancer, which is a closed, trusted systems substrate. Process-level isolation provides separate address spaces, separate seccomp/Landlock sandboxes, and separate CPU placement.
2. **Thread mode shared address space** is insufficient trust boundary separation — a buggy LLM server thread could corrupt Firedancer queue state.
3. **Runtime consistency:** The supervisor now only launches processes. Thread mode was a compatibility lane that created confusion about which mode is the target for production hardening.

This is a product security decision, not just an engineering preference.

---

## Current Findings: Where Docs Drift From Code

### Finding 1: Thread/Dev/Test Mode References (HIGH PRIORITY)

**Files affected:**
- `doc/knowledge/tile-topology.md` lines 237-238: "A thread-backed topology may remain as a dev/test compatibility lane, but it is not the process-isolation target for runtime hardening work."
- `doc/knowledge/tile-orchestration.md` line 287: "process/thread launch semantics"
- `doc/knowledge/tile-orchestration.md` lines 551, 720: "thread-mode run callback (RunFn)", "thread/dev run callback, if any"
- `doc/knowledge/architecture.md` line 186: "dev/test mode" (Phase 0 spike description)
- `doc/knowledge/architecture.md` line 221: "thread-only topology may remain for fast dev/unit tests"

**Code reality:** `tile_registry.zig` has `ProcessFn` only — no `RunFn` or `thread_mode` callback exists. `supervisor.zig` no longer has thread-mode spawn paths. `topo_build.zig` only builds topologies for process-mode dispatch.

### Finding 2: Metric Tile Naming Inconsistency (MEDIUM)

**Code reality:**
- Tile ID is `metric` (renamed from `tkmetr` in commit `b28be01a7`)
- `TileId.parse("metric")` is used in `topologies.zig`, `tile_registry.zig`
- `topo_build.zig` detects tile by name `"metric"`
- The logical name in the registry is still `"metric_tile"` (string used for `topobTile`)

**Docs:**
- `tile-topology.md` line 399: `tkmetr` / `metric_tile` (uses old runtime ID)
- `architecture.md` line 488: `tkmetr` / `metric_tile` (same)
- `workspace-management.md` consistently uses `tkmetr`

**Issue:** Code uses `metric` as the tile ID, docs use `tkmetr`. Both are wrong — the code's TileId is literally `metric`, not `tkmetr`. The logical name `metric_tile` in the registry entry is a display name, not the runtime ID.

### Finding 3: Metric Tile Description (LOW-MEDIUM)

**Code reality:**
- Metric tile is fully wired: workspace creation (`metric`, `metric_in`), tile registration, CPU placement (FLOATING), HTTP server on configurable port, metrics observer with `in_cnt` links from all pipeline tiles
- Test file: `test_metric_tile_integration.zig` tests build, HTTP `/metrics`, 404 handling, shutdown
- Registry entry: `process_fn = null`, has counter schema (`metric_snapshots`, `metric_backpressure_waits`), `in_cnt = 0`, `out_cnt = 0` (observer tile)
- `topo_build.zig` has conditional metric workspace creation (Task 0: scan for metric tile, create workspaces only if present)

**Docs:** `workspace-management.md` describes the metric tile workspace details well (lines 297-314), but it assumes `tkmetr` naming and doesn't mention the port-based HTTP surface or the `metric_tile_obj_id` scratch footprint.

### Finding 4: Tile Registry Descriptions (LOW)

**Docs say** (tile-orchestration.md line 718-726):
```
- thread/dev run callback, if any
- Linux full-runtime run callback or adapter entry, if any
- process/retail run callback, if any
```

**Code reality:** Registry has only `ProcessFn`. No `RunFn`, no `thread/dev` callback, no separate `Linux full-runtime` vs `process/retail` dispatch entries. All process-mode dispatch goes through `ProcessFn`.

### Finding 5: Architecture.md Phase 0 Description (LOW)

**Docs say** (line 186): "dev/test mode" spike
**Code reality:** The Phase 0 pipeline runs in process mode. The "dev/test" phrasing was from the thread-mode era.

---

## Alignment Plan

### Task 1: Remove Thread/Dev/Test Mode References (HIGH PRIORITY)

**DONE** — Committed as `885803562` (docs: remove thread/dev/test mode references).

**Files edited:**
1. `doc/knowledge/tile-topology.md` — Lines 237-238: "thread-backed topology" → "Process mode is the only dispatch path; there is no thread-mode compatibility lane." Line 282: "process/thread callback" → "process-mode callback".
2. `doc/knowledge/tile-orchestration.md` — Line 287: "process/thread launch semantics" → "process launch semantics". Line 551: "thread-mode run callback (RunFn), process-mode run callback (ProcessFn)" → "process-mode run callback (ProcessFn)". Lines 720-722: "thread/dev run callback", "Linux full-runtime run callback", "process/retail run callback" → "process-mode run callback (ProcessFn), if any".
3. `doc/knowledge/architecture.md` — Line 186: "dev/test mode" → "process mode". Line 221: "thread-only topology may remain for fast dev/unit tests but does not satisfy process-isolation acceptance" → "there is no thread-mode compatibility lane."

**Rules applied:**
- "dev/test mode" → "process mode" (it runs as OS processes) ✓
- "thread-backed topology" → deleted (no longer exists) ✓
- "thread/dev run callback" → deleted (no longer exists) ✓
- "thread-only topology may remain for fast dev/unit tests" → "there is no thread-mode compatibility lane." ✓

**Why this is non-negotiable:** The thread mode is gone. Any doc reference to it implies it exists, which misleads developers into thinking there's a thread-mode dispatch path they can use or extend. This is also a security concern — if docs say thread mode exists, someone might try to re-add it.

### Task 2: Fix Metric Tile Naming (MEDIUM)

**DONE** — Committed as `17b6bec76` (docs: rename tkmetr to metric in docs).

**Files edited:**
1. `doc/knowledge/tile-topology.md` — Line 168: `tkmetr` → `metric` (Firedancer comparison). Line 170: `tkmetr` → `metric`. Line 212: `tkmetr` → `metric`. Line 399: `tkmetr` → `metric` (tile registry table). Line 432: `tkmetr` → `metric` (topology flow diagram). Line 475: `tkmetr` → `metric` (validator→Tile mapping).
2. `doc/knowledge/architecture.md` — Line 56: `tkmetr` → `metric`. Line 197: `tkmetr` → `metric`. Line 488: `tkmetr` → `metric`. Line 501: `*_tkmetr` → `*_metric`.
3. `doc/knowledge/workspace-management.md` — All occurrences of `tkmetr` → `metric` (lines 100-101, 105, 108-113, 293, 299, 308).

**Also fixed in code:** Verified `tile_registry.zig`, `topologies.zig` already use `TileId.parse("metric")` — correct.

**Rules applied:**
- Runtime ID = `metric` (as used in `TileId.parse("metric")` and `topobTile`) ✓
- Logical name = `metric_tile` (display name in registry) — kept as-is ✓
- All doc references now use `metric` as the runtime ID ✓

### Task 3: Tighten Metric Tile Description (LOW-MEDIUM)

**DONE** — Committed as `TODO` (after verification below).

**Files edited:**
1. `doc/knowledge/tile-topology.md` — Tile registry table row (line 80): added "configurable port", "zero in/out pipeline links", "pure observer reading from `metric_in`" to the metric tile description.
2. `doc/knowledge/workspace-management.md` — Lines 413-415: added "configurable port", "serving `/metrics` to external consumers", "scratch workspace (a few hundred KiB: 4 connections, 256 KiB out buffer) hosts HTTP server state", and "`metric_tile_obj_id` field in `BuiltTopo` carries the object ID". Also updated lines 109, 166, 404: "~32 MiB" → "a few hundred KiB (4 connections, 256 KiB out buffer)".

**Rules applied:**
- Configurable port explicitly documented ✓
- Observer role (zero links) reinforced ✓
- Scratch footprint (few hundred KiB: 4 connections, 256 KiB buffer) documented ✓
- `metric_tile_obj_id` in `BuiltTopo` documented ✓

### Task 4: Fix Tile Registry Description (LOW) — DONE ✅

Already applied in Task 1 commit `885803562`. `tile-orchestration.md` line 725 now reads:
"process-mode run callback (`ProcessFn`), if any" — the registry owns process-mode dispatch only.
No "thread/dev", "Linux full-runtime", or "process/retail" callback entries remain.

### Task 5: Architecture.md Phase 0 Cleanup (LOW) — DONE ✅

Already applied in Task 1 commit `885803562`. Verified current state:
- Line 186: "process mode" (not "dev/test mode")
- Line 221: "there is no thread-mode compatibility lane."

---

## Additional Tightening Opportunities (Nice-to-Have)

### T6: Verify platform-tiers.md vs code — DONE ✅
- `detectTier()` in `src/tickoni/util/tier.zig` returns `linux_full`, `macos_retail`, `windows_retail`, `unsupported`
- `platform-tiers.md` lists 5 tiers: same 4 plus `container_assisted` (doc-only; host tier is returned by `detectTier()`)
- Tier names, OS/arch mappings, and degraded-guarantee rules all match code behavior.
- No drift.

### T7: Verify engine-harness-snapshot.json — DONE ✅
- Snapshot commit: `288332d052023468635678886a5112df79c15362` (plan text referenced older `5f4614334...`)
- `engine_check_changes.py` exits 0: all 13 watched harness files are in sync.
- Files are current. Snapshot commit hash in plan text was stale; corrected above.

### T8: Auth tiles — keyswitch section — DONE ✅
- `auth-tiles.md` (220 lines) well-structured.
- Phase 0 tiles documented as `uses_id_keyswitch=0, uses_av_keyswitch=0` — matches `topo_build.zig` / `topob.zig` calls.
- No drift.

### T9: UI Style Guide — DONE ✅
- `doc/knowledge/ui-style-guide.md` (1865 lines) is a Qt Quick / Midnight Oni design spec.
- No tile/runtime/metric code touches QML or UI styling. Out of scope for alignment.
- No drift.

---

## Execution Order

1. **Task 1** (thread mode removal) — blocks everything else, highest security impact
2. **Task 2** (metric tile naming) — unambiguous, mechanical
3. **Task 3** (metric tile description) — needs Task 2 done first
4. **Task 4** (registry description) — mechanical
5. **Task 5** (architecture cleanup) — mechanical
6. **Tasks T6-T9** — nice-to-have, verify after core alignment
