---
title: "Remove dead process-function code"
branch: story/process-fn-removal
created: 2026-11-26
status: planning
---

# Remove dead process-function code

All tiles now use fd-stem. The `process_fn` / `.tile` launch mode / `__tile-run` path is 100% dead code. Removing it.

## Phase 1: Remove `tile_process.zig` module (the entire process-mode runtime)

1. **Delete** `src/tickoni/runtime/tile_process.zig` — only used by `__tile-run` which is dead
2. **Remove** `pub const tile_process = @import("tile_process.zig");` from `src/tickoni/runtime/mod.zig`
3. **Clean up** comments in `src/tickoni/c_abi/topo_run.zig` that reference tile_process.zig

## Phase 2: Clean up `tile_main.zig`

4. **Remove** the entire `run()` function (lines 24-31) — only called by `__tile-run`
5. **Remove** the entire `runPipelineStage()` function (lines 207-216) — always returns early (process_fn always null)

## Phase 3: Clean up `main.zig`

6. **Remove** the `__tile-run` handler block (lines 88-91) — never reached
7. **Update** the usage text to remove `__tile-run` references

## Phase 4: Simplify `tile_registry.zig`

8. **Remove** `ProcessFn` type (lines 20-26) — never assigned
9. **Remove** `process_fn: ?ProcessFn = null` from `TileEntry` (line 90) — always null
10. **Remove** `.process_fn = null` from all 16 registry entries
11. **Remove** `LaunchMode` enum (line 76) — only `.stem` ever used
12. **Remove** `launch_mode: LaunchMode = .tile` from `TileEntry` (line 86) — always `.stem`
13. **Remove** `.launch_mode = .stem` from all 16 registry entries
14. **Remove** `process_fn` and `launch_mode` references from `tile_registry_test.zig`

## Phase 5: Simplify `supervisor.zig`

15. **Simplify** `tileArgv()` — remove `launch_mode` parameter, always return `__stem-run`
16. **Update** call site on line 833 to drop the `entry.launch_mode` argument
17. **Remove/update** the three test functions (lines 1559-1590):
    - "tileArgv launches a stem tile through __stem-run and a Zig tile through __tile-run" → remove .tile test case
    - "tileArgv appends --verbose" → keep but drop launch_mode param
    - "tkings, tkpoly and tkgate children are spawned through __stem-run" → update to not reference launch_mode

## Phase 6: Update comments

18. **Remove** references to "process-mode" and "process tile" in comments across:
    - `tile_main.zig` module doc, line 13, line 203-206
    - `supervisor.zig` lines 3, 23, 327-336, 77-79
    - `tile_registry.zig` module doc, line 17-19, line 48, line 87-88
    - `tile_process.zig` module doc (already covered by deletion)
    - `topologies.zig` lines 94, 262, 355
    - `test_stem_liveness.zig` line 53

## Verification

19. **Build** the project and run tests to confirm nothing references the removed code
