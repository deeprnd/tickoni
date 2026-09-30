# Bug Fix Summary: V2.22.S4 Telemetry Issues

## Issue #141 — "No black boxes" (FIXED)

**Audit finding:** Tiles invisible during execution; only atomic counters printed at pipeline end.

**Fix:** Added per-tile metric sampling loop in `src/app/tickoni/main.zig` (`cmdStartProcess`). Polls `snapshotProcessMetricsForTile()` every 1 second during pipeline execution, prints per-tile deltas (`dP`, `dN`, `dI`, `dD`, `dA`, `dR`, `dU`) to stdout. 600-sample max (10 min bound). Stops when `audited >= event_count`.

**Commit:** `31f7edec0` (thread-mode), `ea9f72da8` (process-mode). Thread-mode variant removed in `8da46501a` after supervisor refactoring; process-mode sampling remains in `main.zig:205-255`.

**Audit update:** `6a777ee14` marks "No black boxes" PASS.

## Issue #142 — "Per-tile visibility: atomic counters only, no log-level" (FIXED)

**Audit finding:** Tile logs were bare strings without structured per-event context.

**Fix:** Added `log.kvFmt()` calls with key-value context (offset, account_id, amount, event_hash, idempotency_key, decision rationale) to all 8 tile run loops. Debug-level — visible with `--verbose`.

**Tiles changed:** `ingest.zig`, `normalize.zig`, `dedupe.zig`, `policy.zig`, `audit_stage.zig`, `replay.zig`, `metric.zig`, `diag.zig`.

**Commit:** `2ac491f69` — "feat: enrich all 8 tiles with structured per-event kvFmt log entries".

**Audit update:** `08605c612` marks "Per-tile visibility" PASS.

## Audit Summary

| Finding | Original Status | Fixed | Audit PASS |
|---------|----------------|-------|------------|
| No black boxes (FAIL) | tiles invisible during execution | per-tile 1s polling loop | `6a777ee14` |
|| Per-tile log-level (FAIL) | bare strings, no kv context | `log.kvFmt()` in all 8 tiles | `08605c612` |

---

## Issue #142 — Full Evaluation Log

**Initial assessment (incorrect):** Said bug was present. Searched for `log\.kv\(` pattern, found zero matches, concluded no structured logging existed.

**Why wrong:** The code uses `log.kvFmt()`, not `log.kv()`. Basic search pattern error — the structured entries were right in front of me.

**Correct assessment:** Bug was already fixed. Commit `2ac491f69` added `log.kvFmt()` to all 8 tiles. The audit doc at line 223 correctly says PASS. The plan file (`v2.22-s4-tile-log-level-visibility-done.md`) is a retrospective record of what was done, not a pending plan.

**Conversation trace:**
1. Asked if #142 resolved → searched for `log.kv(` → found nothing → incorrectly said "not fixed"
2. Asked to implement steps → read all 8 tile files → found `log.kvFmt()` calls already present → realized the search error
3. Asked to verify commit is in branch → confirmed `2ac491f69` is in `story/metric-tile`
4. Final assessment: bug is fixed, audit doc is correct, no action needed

**Lesson:** Always verify search patterns match actual code conventions before concluding code is missing something. Check both the search term and the actual implementation name.

---

## Issue #111 — "77% test coverage; key ABI files missing tests" (NOT RESOLVED)

**Audit reference:** V2.22.S4-security-audit.md, Finding 12 (LOW) and audit-debt-tracking.md line 108.
**Severity:** MEDIUM
**Status:** Active — test debt. Still unresolved.

### What was marked "DONE" (Finding 12 in V2.22.S4-security-audit.md)

Finding 12 was "LOW: Test coverage is heavy on Zig, light on C". Three new C unit tests were added for Windows platform shims:
- `test_log_windows.c` — Windows CRT error path logging
- `test_cpu_topo_platform_windows.c` — Windows CPU topology stub
- `test_tile_threads_platform_windows.c` — Windows tile thread stubs

These cover the 4 Windows C shim files. The audit says: *"The Zig test gap (111 `.zig` files without tests) is a pre-existing condition, not a Windows-specific regression."*

### What was NOT done

1. **77% test coverage — unchanged.** `src/tickoni/` still has 146 Zig source files, only 18 test files. 111 untested Zig files remain.

2. **Key ABI files missing tests — still missing.** `src/tickoni/c_abi/` contains 14 Zig files (`c_abi.zig`, `queue.zig`, `sandbox.zig`, `dcache.zig`, `fseq.zig`, `fctl.zig`, `cnc.zig`, `tempo.zig`, `wksp.zig`, `boot.zig`, `topo_run.zig`, `topob.zig`, `ballet.zig`, `shim/os.zig`) — zero test files.

3. **No `quality-coverage-check` recipe — still absent.** Searched `just/quality.just`, `just/test/coverage.just`, and the entire justfile tree: zero references to `quality-coverage-check`. The quality.just file has `format-check`, `lint-check`, `proto-check`, `yaml-check`, and `spell-check` but no coverage gate.

4. **Coverage badge shows "unknown".** README.md line 29: `<img alt="Tests Coverage" src="https://img.shields.io/badge/tests%20coverage-unknown-lightgrey" />` — no live coverage badge is being updated.

5. **Audit-debt-tracking.md (line 235) confirms:** *"3 of 4 still active; doctor module now un-gated"* — coverage (#111) is one of the 3 remaining active findings.

### Why the "resolved" claim was wrong

Finding 12 ("LOW: Test coverage is heavy on Zig, light on C") was marked DONE because 3 C unit tests were added for Windows shims. But #111 (MEDIUM: "77% test coverage; key ABI files missing tests") is a separate finding covering the overall Zig test gap and missing ABI coverage. The audit-debt-tracking.md tracks them separately. Adding C shim tests for a Windows-specific regression does not address the pre-existing Zig/ABI coverage gap.

### Assessment: Bug is NOT resolved

The coverage infrastructure exists (`just test-cov-tk`, CI `_ci-coverage.yml`, kcov pipeline) but is not enforcing anything — thresholds are 20% (lines/statements/branches/functions), badge shows "unknown", and ABI file tests have not moved since the audit. The audit-debt-tracking.md still lists #111 as **Active — test debt**.

---

## Issue #109 — "Windows implementation stubs — not functional" (PARTIALLY STALE)

**Audit reference:** V2.22.S4-security-audit.md, Finding 2 (CRITICAL) and audit-debt-tracking.md line 106.
**Severity:** HIGH
**Status:** Stub finding valid; relevance justification stale.

### What the audit found

V2.22.S4 security audit (Finding 2) correctly identified that the Windows implementation is stubbed, not functional:
- `fd_tile_threads.c` Windows path: stack allocation returns NULL, CPU config is no-op, tile exec always NULL, returns 1 CPU / 1 NUMA.
- `fd_cpu_topo.c` Windows path: returns 1 CPU, 1 NUMA node, no topology discovery.
- Tiles do not run on actual Windows hardware — compile-only stubs.

### What is outdated

The audit-debt-tracking.md line 106 justification states: *"No `FD_HAS_WINDOWS` found in any Tickoni source file. Windows support is not implemented."*

This is **false**. `FD_HAS_WINDOWS` is present in 50+ locations across:
- `build-lib/lib/shims.zig` — build flag `-DFD_HAS_WINDOWS=1`
- `config/base.mk` — platform detection, `FD_HAS_WINDOWS:=1`
- `src/tickoni/c_abi/shim/*.c` — os.c, sandbox.c, tile_run.c, topob.c, windows_crt.c
- `src/util/log/fd_log_windows.c`, `src/util/fd_windows_compat.h`
- `src/disco/topo/fd_cpu_topo_platform_windows.c`, `fd_tile_threads_platform_windows.c`
- `src/waltz/grpc/fd_grpc_client_windows_stub.c`, `src/waltz/resolv/fd_netdb_windows_stub.c`, `src/waltz/udpsock/fd_udpsock_windows_stub.c`
- `src/tango/cnc/fd_cnc.c`, `src/app/tickoni/main.zig`

### What is still valid

The core finding remains: **Windows tiles are stubbed**. CPU pinning, stack management, multi-tile dispatch — all no-ops. Not shippable.

### Assessment: Relevance justification should be removed

The stub finding is real but the debt tracker's relevance note ("No `FD_HAS_WINDOWS` found") is outdated and should be corrected. The macro exists and is wired into the build system and shim layer. Only the "stubs, not functional" portion remains accurate.
