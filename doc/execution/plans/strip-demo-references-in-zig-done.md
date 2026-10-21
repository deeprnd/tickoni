# Strip Remaining Demo References in .zig Files

## Overview

After the `demo/` directory deletion and `investment_demo` → `investment_fixture` rename, 66 demo references remain scattered across `.zig` files. This plan categorizes each by action needed.

## Category A: Broken Path References (Must Fix)

References to deleted `src/tickoni/demo/` or `src/tickoni/test/demo/` directories. These are dead code paths.

| File | Line | Reference | Action |
|------|------|-----------|--------|
| `src/app/tickoni/topologies.zig` | 99-100 | Comment: "demo/integration tests (src/tickoni/test/demo/investment/**)" | Update path to `src/tickoni/test/fixtures/investment/**` |
| `src/tickoni/doctor/checks.zig` | 264 | `"src/tickoni/demo/fixtures/demo.manifest.json"` | Update to `src/tickoni/test/fixtures/investment/fixtures/demo.manifest.json` or remove if no longer applicable |

## Category B: Evidence Module `demo_ref` (Rename)

`src/tickoni/evidence/mod.zig` uses `demo_ref` as a field name and JSON key. This references an audit document path `doc/execution/audits/stories/V2.22.S7-demo-output.md`.

| Line | Code | Action |
|------|------|--------|
| 23 | `/// Reference to the demo output.` | Rename doc: "Reference to the audit output." |
| 24 | `pub const demo_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-demo-output.md";` | Rename `demo_ref` → `audit_ref`, update path if audit document was renamed |
| 69 | `demo_ref: []const u8 = "doc/execution/audits/stories/V2.22.S7-demo-output.md",` | Same rename |
| 98-99 | `"\\\"demo\\\":\\\"" + self.demo_ref` | Rename JSON key `demo` → `audit`, reference `self.audit_ref` |
| 178 | Test expecting `"doc/execution/audits/stories/V2.22.S7-demo-outp..."` | Update assertion |
| 209 | `std.mem.indexOf(u8, json_str, "demo")` | Update to `"audit"` |

**Decision needed:** Is the audit doc `V2.22.S7-demo-output.md` still relevant? If it was renamed to something like `V2.22.S7-investment-fixture-output.md`, update both the file path and the `demo_ref` field. If not, rename the field to `audit_ref` and the JSON key from `"demo"` to `"audit"` for clarity.

## Category C: Fixture Module IDs (Rename for Consistency)

`src/tickoni/test/fixtures/investment/mod.zig` uses `demo`-prefixed IDs in test data. These are internal identifiers for test scenarios and don't break anything, but they contradict the fixture rename.

| Line | Code | Action |
|------|------|--------|
| 28 | `live_capability_envelope_id = "capenv.trading_order.propose.demo"` | → `"capenv.trading_order.propose.fixture"` |
| 30 | `live_budget_id = "budget.demo_paper.live"` | → `"budget.fixture_paper.live"` |
| 38 | `demo_cash_buffer_threshold_cents: i64 = 500_000` | → `fixture_cash_buffer_threshold_cents` |
| 56 | `.cash_buffer_threshold_cents = demo_cash_buffer_threshold_cents` | → `fixture_cash_buffer_threshold_cents` |
| 1018-1026 | Two function calls passing `demo_cash_buffer_threshold_cents` | → `fixture_cash_buffer_threshold_cents` |
| 857 | Comment: "System-level demo suite" | → "System-level fixture suite" |

## Category D: Test File Names (Rename)

Test files with "demo" in their names. These are not broken but contradict the fixture rename.

| File | Action |
|------|--------|
| `src/tickoni/test/integration/test_process_demo_parity.zig` | Rename → `test_process_parity.zig` |
| `src/tickoni/test/system/test_investment_demo_live.zig` | Rename → `test_investment_live.zig` |
| `src/tickoni/test/system/test_portfolio_cash_demo.zig` | Rename → `test_portfolio_cash.zig` |
| `src/tickoni/test/integration/test_investment_demo_system_suite.zig` | Rename → `test_investment_system_suite.zig` |

After renaming, update all imports and build lane registrations in:
- `build-lib/lanes/integration.zig`
- `build-lib/lanes/system.zig`
- `build-lib/factory.zig`
- `build-lib/lanes/unit.zig`

## Category E: Internal String Constants (Low Priority)

These are test-only identifiers used internally. They don't break anything but are inconsistent with the fixture naming.

| File | Lines | Code | Action |
|------|-------|------|--------|
| `src/tickoni/tiles/agent/mod.zig` | 18, 20 | `capenv.trading_order.propose.demo`, `budget.demo_paper` | → `fixture_*` variants |
| `src/tickoni/tiles/model/backend.zig` | 462-512 | `budget.demo_paper`, `capenv.trading_order.propose.demo` | → `fixture_*` variants |
| `src/tickoni/tiles/model/run.zig` | 115-117 | `capenv.demo`, `budget.demo` | → `fixture_*` variants |
| `src/tickoni/tiles/model/validator.zig` | 99-270 | `capenv.demo`, `budget.demo` | → `fixture_*` variants |
| `src/tickoni/test/mocks/mock_model.zig` | 120-131 | `budget.demo_paper`, `capenv.trading_order.propose.demo` | → `fixture_*` variants |
| `src/tickoni/test/integration/test_model_tile_http.zig` | 53-100 | `budget.demo_paper`, `capenv.trading_order.propose.demo` | → `fixture_*` variants |
| `src/tickoni/tiles/audit/fixture_events.zig` | 58, 102 | `demo.investment.v1`, `replay_demo` | → `fixture.investment.v1`, `replay_fixture` |

## Category F: Comments (Low Priority)

Comments mentioning "demo" that describe the system or test intent. These don't affect correctness but are inconsistent with the fixture rename.

| File | Lines | Context | Action |
|------|-------|---------|--------|
| `src/tickoni/evidence/mod.zig` | 23 | `/// Reference to the demo output.` | Update |
| `src/tickoni/schema/capability/capability.zig` | 5 | "demo/replay code cannot drift" | Update to "fixture/replay code" |
| `src/tickoni/schema/consumer_money/cards.zig` | 4, 178, 211 | "current demo flow", "demo/runtime path" | Update to "fixture" |
| `src/tickoni/schema/portfolio/portfolio.zig` | 267, 271 | "Deterministic demo fixtures", "demo account" | Update to "fixture" |
| `src/tickoni/test/fixtures/investment/audit_trace.zig` | 61 | "demo audit traces" | Update to "fixture audit traces" |
| `src/tickoni/test/integration/test_investment_decision_cards.zig` | 5 | Test name "investment_decision_cards_integration: allowed demo..." | Update test name |
| `src/tickoni/test/integration/test_investment_demo_system_suite.zig` | 64 | "system demo live: full investment suite via..." | Update (renamed in D) |
| `src/tickoni/test/system/test_investment_demo_live.zig` | 4 | "system demo live: real tkmodl..." | Update (renamed in D) |
| `src/tickoni/test/system/test_portfolio_cash_demo.zig` | 1-39 | Comments and test name | Update (renamed in D) |

## Execution Plan

### Phase 1: Critical (A + B) — Do First

1. Fix Category A: broken path references in `topologies.zig` and `checks.zig`
2. Fix Category B: rename `demo_ref` → `audit_ref` in `evidence/mod.zig`
   - Also check if the referenced audit doc path needs updating

**Verify:** `zig build test-unit-tk` still passes

### Phase 2: Fixture Consistency (C)

3. Rename `demo_cash_buffer_threshold_cents` → `fixture_cash_buffer_threshold_cents` in `test/fixtures/investment/mod.zig`
4. Update `live_capability_envelope_id` and `live_budget_id` in same file
5. Update test name comments

**Verify:** `zig build test-unit-tk` still passes

### Phase 3: Internal Test IDs (E)

6. Rename `demo`-prefixed IDs in `tiles/agent/mod.zig`, `tiles/model/backend.zig`, `tiles/model/run.zig`, `tiles/model/validator.zig`, `test/mocks/mock_model.zig`, `test/integration/test_model_tile_http.zig`, `tiles/audit/fixture_events.zig`

**Verify:** `zig build test-unit-tk` and `test-integration-tk` pass

### Phase 4: File Names (D) — Requires Build Graph Update

7. Rename test files per table above
8. Update build lane registrations in `build-lib/lanes/*.zig` and `build-lib/factory.zig`

**Verify:** All test lanes pass

### Phase 5: Comments (F) — Cleanup

9. Update all remaining comments referencing "demo" to "fixture"

**Verify:** No `zig build` regressions

## Pre-Flight Checks

- Confirm audit doc `doc/execution/audits/stories/V2.22.S7-demo-output.md` still exists and its name before renaming `demo_ref`
- Verify all test file renames don't break any import chains or build lane registrations
- Run full test suite after each phase
