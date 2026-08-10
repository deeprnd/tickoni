<!--
Tickoni backlog proposal template.

Use this template when an idea is not ready to become an epic or story yet.
A backlog proposal answers: why does this belong in Tickoni?

It should be product-fit first, implementation-light. Do not turn this into an
acceptance-criteria document. If the proposal is accepted, graduate it into an
epic or story using the relevant template.
-->

# Backlog Proposal: Refactor `build.zig` to <500 Lines via Declarative Modules + Walk-Based Registration

**Candidate issue type if accepted:** epic
**Candidate labels:** [`documentation`, `enhancement`]
**Related docs / examples:** `doc/strategy/templates/proposal-template.md`, `src/tickoni/test/mocks/`, `src/tickoni/codec/`

## Proposal Summary

Refactor `build.zig` from its current ~1,766 lines into a <500-line declarative build script. The new script will: (1) declare module name-to-path mappings once, (2) accept 2–3 path prefixes for test discovery (unit, integration, cov), and (3) provide utility functions that walk those paths, resolve each file's required named imports, apply include/exclude filters, and register `addTest`/`installArtifact` steps. No manual copy/paste of per-file `b.createModule` + `b.addTest` blocks — a single registration loop handles the pattern.

## Product Fit Thesis

This fits Tickoni because it removes a structural barrier to community contribution. `build.zig` is a critical build-system entry point — every new module, test, or tile requires edits here. At 1,766 lines with hundreds of near-identical test declarations, it is effectively a gate that prevents community developers from adding code without deep familiarity with the build system's idiosyncrasies. Reducing it to a declarative module registry plus utility-driven discovery directly advances safe money-adjacent development by making the codebase easier to extend with correctness guarantees.

It is not just generic developer productivity because the build system directly controls what code gets compiled, linked, and tested. Every manual `addTest` entry defines a test isolation boundary, import scope, and link configuration — errors in these choices cause `ld.lld: undefined symbol` failures or silent test omissions. The Tickoni-specific consequence is that a broken build entry can mask coverage gaps or break CI reproducibility for the supervisor and its tiles.

## Tickoni Fit Checklist

| Fit question | Answer |
| --- | --- |
| What financial or money-adjacent consequence does this help control? | Reduces build-entry errors that could silently skip test compilation for financial schema modules (thesis, basket, catalog, drift). |
| Which user/operator trust problem does it reduce? | Developers can safely add new modules/tests without accidentally breaking link configurations or duplicating module instances. |
| How does it support policy-gated proposals instead of uncontrolled execution? | Module declarations become the single source of truth; the walk function derives test entries from that registry, eliminating ad-hoc additions. |
| What audit, evidence, or replay value does it create? | Every registered test step logs its source path and import resolution chain — reproducible build output. |
| What finance-native scope matters: account, beneficiary, wallet, rail, currency, market, venue, instrument, amount, exposure, frequency, approval path? | N/A — this is build-system infrastructure, but it affects all consumer-money schema compilation (thesis, basket, portfolio, catalog, trade_ticket, drift, cards, impact). |
| How does it keep agents off the direct money path? | Agents still cannot bypass build/test verification — the refactoring only changes how test entries are registered, not what gets tested. |
| How does it avoid becoming generic agent automation or trading-alpha UX? | The scope is strictly `build.zig` structure; no trading, alpha, or generic tooling is involved. |

## User / Operator Problem

Developers (human or agent) who add a new Zig module with `test {}` blocks must manually:

1. Create a `b.createModule()` with the correct `root_source_file`.
2. List every `@import("name")` call from that file in the module's `.imports` field, pointing to the correct named `std.Build.Module` instance.
3. Create a `b.addTest(.{ .root_module = ... })` wrapping that anonymous module.
4. Conditionally call the correct `linkTickoniCodec`/`linkTickoniFiredancer`/`linkTickoniTopoRun` helper based on what C symbols the file pulls in.
5. Wire `test_step.dependOn(&b.addRunArtifact(...).step)`.
6. Repeat the entire pattern for the integration-test lane (new module instances, same imports).
7. Repeat once more for the cov lane (same as unit tests but with `installArtifact` instead of `runArtifact`).
8. Some work was done in doc/strategy/roadmap/backlog/poc/poc_discovery.zig.

This results in ~1,400 lines (80% of the file) that are copy/paste variations of the same five-step pattern, differing only in file path, import list, and link helper set. Adding a new test file requires 20+ lines of manual boilerplate spread across 3 lanes. A missing import causes a `no such package` compile error; a wrong link helper causes `ld.lld: undefined symbol`. Both are hard to debug for newcomers.

## Current Gap

The current `build.zig` has no auto-discovery for new test files. Every new `.zig` file with `test {}` blocks must be manually declared in three separate sections (unit, integration, cov). The file path, import list, and link helpers must be copied and adapted by hand. There is no single source of truth for "this file belongs to this module with these imports" — the module declarations and the test declarations are scattered and duplicated. The cov step is effectively a copy of the unit test step with `installArtifact` instead of `runArtifact`. There are 3+ identical link helper functions (`linkTickoniCodec`, `linkTickoniFiredancer`, `linkTickoniTopoRun`, `linkTickoniTileRun`) that are correctly abstracted at the helper level but not at the caller level — every test step still manually invokes the right helper.

## Proposed Product Behavior

When a developer adds a new `.zig` file under `src/tickoni/` with `test {}` blocks, `build.zig` should automatically discover it and register it for testing. The developer only needs to:

1. Define the module's named imports in a single declaration table.
2. Optionally specify which link helpers are needed (by marking the file or by convention).
3. Ensure the file path falls under one of the declared discovery paths.

Expected behavior:

* `build.zig` declares ~15–20 named modules at the top (name → path + imports). This is the single source of truth for module identity.
* Two walk functions iterate over `src/tickoni/` paths with configurable include/exclude glob patterns. One walk handles unit/cov tests; another handles integration tests (which use separate module instances).
* Each discovered `.zig` file with `test {}` blocks gets a `b.createModule()` that inherits the file's directory's nearest named module's imports, with per-file overrides.
* The walk registers `addTest()` steps with the correct link helpers applied based on the file's location (e.g., files under `c_abi/` or `codec/` get `linkTickoniCodec`; files under `tiles/*/mod.zig` that import c_abi get `linkTickoniFiredancer`).
* The cov lane is a single loop over the unit test artifacts with `installArtifact` instead of `runArtifact` — no duplication.

## Why Now

`build.zig` at 1,766 lines is the largest single file in the codebase. It is the build-system entry point that every new developer encounters. The current manual maintenance model creates a high barrier to contribution — adding a test file is a 10+ minute process of reading existing entries, copying the pattern, and carefully setting imports and link helpers. Community contributors need a maintainable build system to even attempt meaningful work on Tickoni's consumer-money schema or tile logic. The cov lane failure (missing `linkTickoniFiredancer` on `sup_cov_test`) just demonstrated that manual entries are error-prone even for experienced maintainers.

## Example Scenario

```text
Given: A community developer adds src/tickoni/schema/consumer_money/new_schema.zig
       with test {} blocks that import @import("basket"), @import("portfolio"), @import("thesis")
When:   the developer runs `zig build test`
Then:   build.zig discovers new_schema.zig via the walk, resolves its imports
        from the module registry (basket_mod, portfolio_mod, thesis_mod),
        creates the test binary, applies linkTickoniCodec (because it lives
        under schema/consumer_money/), and registers it under the test step.
```

## Product Boundaries

### In Scope

* Refactor `build.zig` to <500 lines.
* Declare ~15–20 named modules at the top (name → path + imports).
* Walk-based test discovery for unit and cov lanes.
* Walk-based test discovery for integration lane (separate module instances).
* Utility function that resolves a file's import set from the module registry.
* Utility function that applies correct link helpers based on file path conventions.
* Keep existing link helper functions unchanged (`linkTickoniCodec`, `linkTickoniFiredancer`, `linkTickoniTopoRun`, `linkTickoniTileRun`).
* Preserve `addPlainTestRun` for process-mode tests.

### Out Of Scope

* Auto-discovery of Zig modules from source files by parsing `@import()` calls (too fragile; module declarations remain explicit).
* Changes to CI pipeline structure (`.github/workflows/tests-short.yml`, `justfile`).
* Changes to Firedancer C shim files or build.
* Build-time caching or incremental build optimization.
* Support for non-Zig build targets (C/Firedancer build remains in GNUmakefile).

### Authority Boundary

| Action class | Proposed boundary |
| --- | --- |
| Observe | Allowed — the build script is read to verify compilation. |
| Analyze | Allowed — developers can inspect the module registry. |
| Draft | Allowed — new module declarations are added by the developer. |
| Recommend | Allowed — the walk function's link helper decisions are reviewable. |
| Propose | Allowed — changes to `build.zig` go through normal PR review. |
| Prepare | Sandbox only — the developer builds locally before pushing. |
| Execute | Denied — CI runs the build and tests; no direct execution. |
| Override/Administer | Out of scope — no build system override mechanism. |

## Fit Against Product Principles

| Principle | How this proposal fits | Concern / open question |
| --- | --- | --- |
| Financial consequence over generic tool access | Reduces build-entry errors for financial schema modules (thesis, basket, portfolio, drift). | Walk-based discovery must be deterministic — non-deterministic file ordering could cause flaky builds. |
| Proposal-first agent behavior | Agents can still only propose build changes; execution requires CI verification. | How to handle files that need non-standard import resolution? |
| Policy gates and approval paths | Changes to `build.zig` still require PR review and CI pass. | None. |
| Audit-grade evidence | Every test step's source path and import chain is logged in build output. | None. |
| Deterministic replay or replay-safe substitution | `zig build` output is deterministic given the same source; walk order is sorted alphabetically. | Must sort discovered file paths. |
| Bounded model/tool/adapter spend | Build time may decrease (fewer redundant module instances). | None. |
| Fail-closed behavior | If walk discovers a file with unresolved imports, the build fails with a clear error — no silent skip. | Need a fallback for files that don't match any declared module. |
| No live side effects unless explicitly approved | Build changes have no live side effects — they only affect compilation and testing. | None. |

## Evidence Needed To Promote

* [ ] A working POC exists that refactors `build.zig` to <500 lines while passing all unit, integration, and cov tests.
* [ ] The module registry is clearly documented with name → path + imports mappings.
* [ ] The walk functions are configurable (include/exclude paths) and deterministic (sorted output).
* [ ] The proposal has an observable build-replay value (same source → same build output).
* [ ] Non-goals are explicit (no auto-import parsing, no CI changes, no C build changes).
* [ ] The refactoring can be split into independently verifiable epic/story work.

## Risks And Anti-Fit Signals

This should not move forward if:

* the walk-based approach fails to resolve complex import chains (e.g., test doubles that need 8+ named imports across multiple module hierarchies).
* the resulting build is slower than the current hand-written entries due to additional module creation overhead.
* the abstraction hides link helper decisions so deeply that debugging `ld.lld: undefined symbol` becomes impossible for newcomers.
* it duplicates a story that already covers build system improvements.
* the refactor breaks existing `just test-unit-tk` or `just test-cov-tk` CI integration.

## Open Decisions

| Decision | Options | Owner / next step |
| --- | --- | --- |
| Module registry format | (a) `pub const modules = .{ .{ "name", .{ .path = ..., .imports = ... } } };` — or — (b) inline `addModule` calls at the top. | Author — evaluate readability and ease of extension. |
| Import resolution strategy | (a) Each file's imports are declared in the registry; the walk looks up the containing directory's nearest module. — or — (b) Per-file override map keyed by relative path. | Author — evaluate maintainability. |
| Link helper inference | (a) Path-based convention (e.g., `c_abi/*` → `linkTickoniCodec`). — or — (b) Explicit metadata on module declarations (`link_helpers = .{ .codec }`). | Author — evaluate correctness guarantees. |
| Cov lane duplication | (a) Reuse unit test artifacts with `installArtifact` step wrapper. — or — (b) Separate walk for cov with `dest_dir = .{ .override = .{ .custom = "cov" } }`. | Author — evaluate build efficiency. |
| Integration test module instances | (a) Walk creates fresh `createModule()` instances per lane. — or — (b) Shared module instances with lane-specific link helpers. | Author — must preserve isolation (cov must not inherit C sources from unit tests). |

## Graduation Path

If accepted, this should become:

* [x] Epic: spans multiple stories — module registry design, walk-based unit/cov registration, walk-based integration registration, CI verification, documentation.
* [ ] Story: Create module registry declarations for all 20+ modules (independently verifiable).
* [ ] Story: Implement walk-based test discovery utility for unit/cov lanes.
* [ ] Story: Implement walk-based test discovery utility for integration lane.
* [ ] Story: Wire up link helper application by path convention.
* [ ] Story: CI verification — `just test-unit-tk`, `zig build test`, `just test-cov-tk`, `zig build cov` all pass.
* [ ] Documentation: Update `build.zig` header docs and developer README.
* [ ] Keep in backlog with notes — if POC reveals fundamental approach issues.
* [ ] Reject with rationale — if walk-based discovery cannot resolve all import chains.

Suggested next artifact:

* [ ] Create story using `story-template.md` for POC implementation.
* [ ] Create story using `story-template.md` for CI verification after POC.
