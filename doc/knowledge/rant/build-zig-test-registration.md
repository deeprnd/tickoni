---
adr: "0006"
title: "build.zig test registration — data-driven registry over linear copy"
status: "proposed"
date: "2026-08-19"
authors:
  - "vicgenin"
tags:
  - "build-system"
  - "maintainability"
  - "zig"
supersedes: []
superseded_by: []
related:
  - "v2.10-s2: modular build.zig refactoring"
---

# ADR-0006: build.zig test registration — data-driven registry over linear copy

> The unit test lane in build.zig is ~850 lines for ~60 test binaries, growing linearly with every new test file (~14 lines per test). We need a way to add tests without the build script growing into a non-manageable monolith.

## Decision Summary

In the context of the Tickoni `build.zig` Zig build script, facing linear growth in the unit test lane (~850 lines for ~60 tests, ~14 lines per test), we decided to evaluate a **data-driven spec registry** over **directory auto-scan** or **module grouping**, to achieve **bounded build script growth regardless of test count**, accepting **more explicit per-test registration text**, because **explicit linkage is a correctness feature, not overhead**.

## Context and Problem Statement

The current unit test lane (`if (build_tests)` block in `build.zig`, lines 663-1516) has ~850 lines for ~60 test binaries. Each new test adds:

1. Module creation with imports (6-8 lines)
2. `linkTickoniCodec()` call (1 line, sometimes conditional)
3. `linkTickoniFiredancer()` call (1 line, sometimes conditional)
4. `test_step.dependOn()` (1 line)
5. `run_tests_cmd.addArtifactArg()` (1 line)

Plus a coverage lane (~260 lines) that repeats most of the same tests with only the artifact action changing.

The `ballet.c` duplicate symbol incident (commit `2cef9972a`) was caused by implicit linkage through shared modules — linkage decisions hidden in module structure, not explicit.

**Decision question:** How should test registration in `build.zig` evolve to handle 100+ test files without becoming a linear growth problem, while keeping linkage explicit and auditable?

This decision matters now because the test count is growing steadily, the coverage lane already duplicates ~40% of the unit lane, and future test additions (system tests, integration tests, QT-bound tests) will compound the problem.

## Scope

### In scope

- Unit test lane registration (offline tests)
- Coverage test lane registration
- Integration test lane registration (fewer tests, different pattern)
- Module declaration organization (shared vs. test-only)
- Helper function extraction (linkTickoniCodec, shimCFlagsFor, etc.)

### Out of scope

- Firedancer C build (Makefile / justfile)
- Zig 0.17 std.Build migration (separate ADR, v2.10-s2)
- Test content, test logic, or test infrastructure
- Runtime behavior, test execution, or coverage collection

## Decision Drivers

- **Correctness:** Linkage decisions (codec vs. Firedancer vs. both vs. neither) must be explicit and visible, preventing duplicate-symbol incidents like `ballet.c`
- **Maintainability:** Adding a new test should require less than 10 lines of build script, with zero copy-paste of existing patterns
- **Bounded growth:** Build script size for test registration must not grow linearly with test count. Adding 10 tests should add at most ~50 lines of spec data, not ~140 lines
- **Test lane separation:** Unit, integration, system, and coverage lanes have different behaviors (run vs. install, different dependency graphs) but share the same test specs
- **Developer experience:** New developers should be able to add a test without understanding the build system internals

Quality attributes affected:

- Correctness: High — duplicate symbol bugs have cost weeks of investigation
- Maintainability: High — linear growth is unsustainable
- Portability: Medium — linkage behavior is platform-dependent (Windows vs. Linux vs. macOS)
- Operability/testability: Medium — test registration is a build-time concern only

## Constraints and Assumptions

- `build.zig` must remain the single entry point — Zig's `std.Build` expects `pub fn build(b)` in `build.zig`
- Helper functions (linkTickoniCodec, shimCFlagsFor, etc.) can be moved to separate files and imported
- Module declarations (c_abi, util, logger, etc.) can be moved to separate files and imported
- Each test binary must still compile as a standalone `std.Build.Step.Compile`
- Coverage lane specs can be derived from unit lane specs with a different action enum

## Considered Options

1. **Data-driven spec registry** — Generic `registerTestLanes()` function + explicit spec arrays. Each test = one struct entry (~5 lines).
2. **Directory scan + auto-link** — Scan source directories for `.zig` test files, auto-detect imports and linkage. Near-zero per-test cost.
3. **Hybrid: scan + opt-in override** — Auto-scan standard locations, but require explicit spec for non-standard tests (custom imports, special linkage).
4. **Module grouping** — Group related tests into "groups" with shared linkage; individual tests just contribute source files to a group.

## Option Analysis

### Option 1: Data-driven spec registry

A generic `registerTestLanes(b, specs, action)` function where `action` is an enum (`.unit | .cov | .integration`). Each test is a struct entry with explicit linkage flags:

```zig
const unit_specs = &.{
    .{
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .imports = &.{ .{ .name = "basket", .module = basket_mod } },
        .needs_codec = true,
    },
    .{
        .source_file = "src/tickoni/runtime/topology.zig",
        .imports = &.{},
    },
};
registerTestLanes(b, unit_specs, .unit);
registerTestLanes(b, unit_specs, .cov); // reuses same specs, different action
```

**Good, because:**

- Linkage is explicit and visible in the spec — prevents `ballet.c`-style incidents
- Coverage lane is O(1) — one function call reuses unit specs
- Adding a test = append a struct entry, ~5 lines, zero copy-paste
- The generic function handles all variance (codec/Firedancer/topo_run conditional linking, Windows manifest fixups, libc flag)
- Build script total: ~30 lines for registry + ~400 lines for specs = ~430 lines (vs. ~1100 current)

**Bad, because:**

- Still requires one entry per test — does not solve the *data volume* problem entirely, only reduces *per-entry cost*
- New developers must learn the `TestSpec` struct and linkage flags
- Spec files may become large (~400 lines) — harder to navigate than line-by-line test blocks

**Neutral or conditional:**

- The registry function itself is small and stable (~80 lines) — once written, it rarely changes
- Spec files grow linearly with test count, but at ~5 lines/test vs. ~14 lines/test

**Validation needed:**

- Compile check: build `zig build test` with registry + specs
- Verify coverage lane produces identical binaries
- Verify Windows linkage still works (manifest fixups, different lib paths)

### Option 2: Directory scan + auto-link

Scan `src/tickoni/**/*.zig` for test files, auto-detect `@import()` calls to determine linkage:

```zig
// Pseudocode
const test_files = scanDirForZigFiles("src/tickoni");
for (test_files) |path| {
    const imports = autoDetectImports(path); // reads @import() calls
    const needs_codec = hasModule(imports, "c_abi");
    const needs_firedancer = hasModule(imports, "util") or hasModule(imports, "runtime");
    registerTest(b, path, needs_codec, needs_firedancer, .unit);
}
```

**Good, because:**

- Near-zero per-test cost — adding a `.zig` file requires no build script changes
- Build script total: ~50 lines for scanner, regardless of test count
- No spec files to maintain or update

**Bad, because:**

- Auto-linking is opaque — you can't see why a test needs Firedancer vs codec
- Transitive imports are invisible — if module A imports `c_abi`, and the test imports A, the scanner won't see it without full dependency analysis
- Per-test exceptions are hard to express — a test that imports `c_abi` but doesn't need codec requires special-casing
- Feels like the "magic CMake" anti-pattern — configuration hidden in conventions, not explicit code
- The `ballet.c` incident happened precisely because linkage was implicit

**Neutral or conditional:**

- Scanner complexity is non-trivial — must handle relative imports, named imports, and dynamic paths

**Validation needed:**

- Spike: write a scanner prototype, run it against current test files, compare auto-detected specs to manual specs
- Verify transitive import detection accuracy

### Option 3: Hybrid — scan + opt-in override

Auto-scan standard locations (`src/tickoni/**/*.zig`), but require an explicit spec for non-standard tests:

```zig
const specs = autoScanSpecs("src/tickoni");
// Override non-standard tests:
specs = specs ++ &.{
    .{
        .source_file = "src/tickoni/schema/portfolio/portfolio.zig",
        .needs_codec = true,  // explicit override for custom linkage
    },
};
```

**Good, because:**

- Most tests auto-discover (zero code change)
- Non-standard tests get explicit control
- Build script stays small (~100 lines for scanner)
- Can evolve from pure manual (Option 1) to hybrid to auto-scan over time

**Bad, because:**

- Two registration modes (auto + override) add cognitive load
- The "standard location" convention becomes a new rule that must be documented
- Overrides for non-standard tests are still manual, so Option 1 is always needed for those cases

**Neutral or conditional:**

- Most current tests are in standard locations, so the initial benefit is modest
- The hybrid approach delays the hard decision about auto-linking until later

**Validation needed:**

- Spike: write a scanner prototype and verify auto-detected specs match current manual specs for >90% of tests

### Option 4: Module grouping

Group related tests into "groups" with shared linkage:

```zig
const schema_group = TestGroup{
    .name = "schema",
    .needs_codec = true,
    .tests = &.{
        "src/tickoni/schema/portfolio/portfolio.zig",
        "src/tickoni/schema/basket/basket.zig",
    },
};
registerTestLanes(b, &.{schema_group}, .unit);
```

**Good, because:**

- Group-level linkage reduces per-test repetition
- Logical grouping mirrors the module hierarchy
- Fewer linkage decisions to make per test

**Bad, because:**

- Adds organizational overhead — test authors must understand groups
- Tests that cross group boundaries need awkward handling
- Harder to see a single test's full linkage without drilling into its group
- Group management adds a new dimension of complexity

**Neutral or conditional:**

- Effective only if groups are well-defined and stable
- Most current tests are standalone, so initial benefit is limited

**Validation needed:**

- Group definition review — do natural groupings exist?

## Comparison

| Criterion | Weight | Opt 1: Registry | Opt 2: Auto-scan | Opt 3: Hybrid | Opt 4: Groups |
| --- | ---: | --- | --- | --- | --- |
| Correctness (explicit linkage) | High | ★★★★★ | ★☆☆☆☆ | ★★★☆☆ | ★★★★☆ |
| Per-test cost | High | ★★★★☆ | ★★★★★ | ★★★★★ | ★★★★☆ |
| Total build script size | Medium | ★★★☆☆ | ★★★★★ | ★★★★☆ | ★★★★☆ |
| Developer experience | High | ★★★★☆ | ★★★☆☆ | ★★★☆☆ | ★★☆☆☆ |
| Implementation effort | Low | ★★★☆☆ | ★★☆☆☆ | ★★☆☆☆ | ★★★★☆ |
| Alignment with "explicit > magic" | High | ★★★★★ | ★☆☆☆☆ | ★★★☆☆ | ★★★★☆ |
| Scalability to 100+ tests | High | ★★★★☆ | ★★★★★ | ★★★★☆ | ★★★☆☆ |
| Coverage lane reuse | Medium | ★★★★★ | ★★☆☆☆ | ★★★★☆ | ★★★★☆ |

**Legend:** ★★★★★ = excellent, ★★★★☆ = good, ★★★☆☆ = acceptable, ★★☆☆☆ = poor, ★☆☆☆☆ = very poor

## Decision

**We will adopt Option 1 (data-driven spec registry) as the default, with Option 3 (hybrid scan + opt-in) as a future migration path.**

This is the standing choice for all new test registrations and the migration target for the existing unit lane. Option 3 becomes the default once a scanner prototype validates >90% auto-detection accuracy against manual specs.

The decisive factor is **explicit linkage prevents the `ballet.c` duplicate symbol class of bugs**. Auto-linking hides linkage decisions in opaque scanning logic — when linkage goes wrong, debugging requires understanding the scanner, not reading the spec. For a financial correctness-focused codebase, explicit linkage is worth the additional per-test registration text.

Rejected alternatives:

- **Option 2 (auto-scan + auto-link):** rejected because opaque linkage violates the explicit-linkage requirement that prevented the `ballet.c` incident.
- **Option 4 (module grouping):** rejected as a primary approach because it adds organizational overhead without solving the fundamental per-test registration problem — tests still need group assignment and linkage decisions happen at the group level, not per-test, which obscures per-test behavior.
- **Hybrid (Option 3) as the first step:** rejected because it introduces two registration modes before validating that auto-scan is actually effective. Option 1 is simpler and can evolve to Option 3 later without breaking existing specs.

## Consequences

### Positive consequences

- Build script test registration bounded at ~430 lines (vs. ~1100 current), even as test count grows to 100+
- Coverage lane code reduced to one function call reusing unit specs
- Linkage decisions are explicit, visible, and auditable in spec arrays
- Adding a new test requires ~5 lines (spec entry), no copy-paste

### Negative consequences

- Spec files become ~400 lines for the unit lane — harder to navigate than line-by-line test blocks
- New test authors must learn the `TestSpec` struct and linkage flags
- Spec files must be updated manually — no automatic detection

### Neutral consequences

- Test registration moves from `build.zig` to separate spec files
- The generic registry function is small and stable (~80 lines)

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- |
| Spec files drift out of sync with source files | Low | Medium | CI build failure surfaces the mismatch immediately | build system |
| New linkage types (e.g., new C libraries) require registry changes | Low | Low | Registry function evolves alongside library additions | build system |
| Scanner validation shows <90% accuracy | Med | Medium | Fall back to manual registry (Option 1) indefinitely | build system |
| Registry function becomes complex with platform-specific logic | Low | Medium | Extract platform-specific logic into helper functions (already done) | build system |

## Implementation Plan

1. Extract helper functions (`linkTickoniCodec`, `linkTickoniFiredancer`, `shimCFlagsFor`, etc.) into `build/lib/`
2. Extract shared module declarations (`c_abi`, `util`, `logger`, etc.) into `build/mod/`
3. Write generic `registerTestLanes()` function in `build/test/registry.zig`
4. Write unit spec array in `build/test/unit_specs.zig`
5. Migrate unit lane to use registry + specs
6. Rewrite coverage lane to call `registerTestLanes(b, unit_specs, .cov)`
7. Migrate integration/system lanes similarly
8. Verify all lanes pass: `zig build test`, `zig build cov`, `zig build system-test`, `zig build integration-test`
9. Verify Windows build still works

Migration/backward compatibility:

- `zig build` (no flags) still builds the supervisor executable
- `zig build test` still runs the same tests
- `zig build cov` still installs coverage binaries
- No changes to test execution behavior or output

Operational impact:

- CI build commands unchanged
- No changes to test infrastructure or mock backends

## Confirmation

Tests:

- `zig build test` — all ~60 unit tests compile and run
- `zig build cov` — all coverage binaries install to `zig-out/cov/`
- `zig build system-test` — system tests compile and run
- `zig build integration-test` — integration tests compile and run
- `zig build` — supervisor executable builds (no test flags)

Review gates:

- Build system review by whoever owns CI build configuration
- Cross-platform verification (Linux, Windows, macOS)

Build/CI checks:

- `zig build test` must pass with registry-based registration
- `zig build cov` must produce identical binaries to pre-migration

## Deviation Criteria

A future implementation may deviate from this decision only when:

- Scanner prototype demonstrates >90% auto-detection accuracy, in which case Option 3 migration begins
- A new test type requires linkage that the registry cannot express, in which case a separate ADR for that test class
- Zig 0.17 `std.Build` introduces features that make Option 1 unnecessary, in which case a separate ADR for Zig 0.17 migration

Each deviation must record:

- why the default does not apply;
- which alternative is being used;
- who approved the deviation;
- how correctness and compatibility are verified;
- whether the deviation is temporary or permanent.

## Related Decisions and References

- ADR-??? (if any): build system architecture decisions
- v2.10-s2: modular build.zig refactoring (roadmap story)
- Commit `2cef9972a`: ballet.c duplicate symbol fix
- [Zig Build System Documentation](https://ziglang.org/documentation/master/std/)

## Authoring Checklist

- [x] Decision question is explicit
- [x] All 4 seriously considered options are named and analyzed
- [x] Chosen option stated as actionable rule
- [x] Rejected options rejected for specific reasons
- [x] Consequences include real costs (not just benefits)
- [x] Deviations are explicit
- [x] Validation/confirmation is concrete
- [x] Links to related decisions included
- [x] Instructional placeholder text removed
