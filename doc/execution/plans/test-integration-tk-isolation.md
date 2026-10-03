# Tickoni Integration Lane Isolation and Recovery Plan

## Goal

Repair the failing `just test-integration-tk` lane by running one integration test binary at a time, fixing the first failure before adding the next. Do not treat a build or partial run as verification; mark a row verified only after its exact test binary passes on the current Windows ARM workspace.

## Test inventory

All tests start as **NOT VERIFIED** for this investigation. This is an initial tracking state, not a claim that every test is known to fail.

| # | Integration test file / binary | Initial status |
|---:|---|---|
| 1 | `src/tickoni/test/integration/test_investment_allowed_trade.zig` | VERIFIED |
| 2 | `src/tickoni/test/integration/test_investment_blocked_limits.zig` | VERIFIED |
| 3 | `src/tickoni/test/integration/test_investment_restricted_instrument.zig` | VERIFIED |
| 4 | `src/tickoni/test/integration/test_investment_input_policy_denials.zig` | VERIFIED |
| 5 | `src/tickoni/test/integration/test_investment_replay.zig` | VERIFIED |
| 6 | `src/tickoni/test/integration/test_investment_decision_cards.zig` | VERIFIED |
| 7 | Investment demo integration binary (`investment_demo_test_mod`) | VERIFIED |
| 8 | `src/tickoni/test/integration/test_link_bounds.zig` | VERIFIED |
| 9 | `src/tickoni/test/integration/test_metric_tile_integration.zig` | VERIFIED |
| 10 | `src/tickoni/test/integration/test_process_pipeline.zig` | VERIFIED |
| 11 | `src/tickoni/test/integration/test_process_cpu_placement.zig` | VERIFIED |
| 12 | `src/tickoni/test/integration/test_process_topology.zig` | VERIFIED |
| 13 | `src/tickoni/test/integration/test_process_demo_parity.zig` | NOT VERIFIED |
| 14 | Mock-server integration binary (`src/tickoni/test/mocks/mock_servers.zig`) | NOT VERIFIED |
| 15 | `src/tickoni/test/integration/test_model_tile_http.zig` | NOT VERIFIED |

## Execution sequence

1. Temporarily make the canonical integration step depend on exactly one binary: `test_process_topology.zig`. All other test run steps must be excluded from the lane, not silently treated as passing.
2. Reproduce that binary through `just test-integration-tk`. Capture each test's actual assertion separately from deferred cleanup failures; ensure failed tests still stop/reap children so teardown does not mask the original assertion.
3. Fix the root cause in the owning production/test seam. Force rebuild the changed inputs and rerun the isolated binary until it exits successfully. Then update only that row to VERIFIED with command and evidence.
4. Add one further integration binary to the lane, run the canonical recipe, fix its issue if present, and mark its row only after a pass. Repeat incrementally through the inventory.
5. Restore the full integration dependency graph after all binaries have passed individually. Run `just test-integration-tk` end-to-end and record its result separately; individual passes do not substitute for aggregate verification.
6. Remove temporary isolation scaffolding and verify the final diff contains no accidental suppression, unrelated workspace edits, or untracked generated logs.

## Current evidence / known failures

- The original `test_process_topology.zig` stale-state failure was repaired; its isolated binary passes all six tests in the Windows ARM integration lane.
- An earlier full-lane run reported `test_process_demo_parity.zig` (`expected 16, found 24`) and `test_process_cpu_placement.zig` (`expected .stopped, found .crashed`). The CPU-placement binary now passes in isolation; demo parity remains to be rechecked when added.
- Inventory tests 1–11 are VERIFIED individually in the Windows ARM integration lane.

## Evidence log

| Test | Command / artifact | Result |
|---|---|---|
| All listed tests | Initial state | NOT VERIFIED |
| `test_process_topology.zig` | `timeout 120s just test-integration-tk` (Windows ARM; isolated lane) | VERIFIED — canonical lane exited 0; all 6 tests passed. Commit `605db5a37`. |
| `test_investment_allowed_trade.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with topology) | VERIFIED — canonical lane exited 0; both isolated binaries passed. |
| `test_investment_blocked_limits.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with topology and allowed trade) | VERIFIED — canonical lane exited 0; all three isolated binaries passed. |
| `test_investment_restricted_instrument.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all four isolated binaries passed. |
| `test_investment_input_policy_denials.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all five isolated binaries passed. |
| `test_investment_replay.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all six isolated binaries passed. |
| `test_investment_decision_cards.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all seven isolated binaries passed. |
| Investment demo integration binary | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all eight isolated binaries passed. |
| `test_link_bounds.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all nine isolated binaries passed. |
| `test_metric_tile_integration.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all ten isolated binaries passed. |
| `test_process_pipeline.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all eleven isolated binaries passed. |
| `test_process_cpu_placement.zig` | `timeout 120s just test-integration-tk` (Windows ARM; sequential with preceding verified binaries) | VERIFIED — canonical lane exited 0; all twelve isolated binaries passed. |
