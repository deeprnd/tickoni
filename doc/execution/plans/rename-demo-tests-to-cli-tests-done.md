# Plan: Rename demo tests and commands to CLI tests

## Motivation

`demo` is a misleading name for what these actually are:
- Fixture-backed conformance tests exercising the CLI subcommand path
- CLI contract tests (version, doctor) plus investment scenario validation
- Not demos/showcases; they are deterministic verification tests

Similarly, `tickoni-supervisor demo investment` is a CLI subcommand, not a "demo" in the product-sense.

Rename to `cli` to accurately describe: CLI contract verification + deterministic scenario conformance against fixtures.

## Scope

### Rename (in scope)

- `test-demo-tk` → `test-cli-tk` (all platform variants)
- `export-demo-conformance-*` → `export-cli-conformance-*`
- `compare-demo-conformance` → `compare-cli-conformance`
- `just/test/demo.just` → `just/test/cli.just`
- `.github/workflows/_ci-demo.yml` → `.github/workflows/_ci-cli.yml`
- All `test-demo-tk` references in documentation, story templates, plans

### Remove entirely (in scope — these are test-only, not production)

- `src/tickoni/demo/` directory — all 5 conformance modules are test utilities imported ONLY by the demo CLI command. Absorb into unit tests (preflight, runner, conformance, comparator, substitution) and integration tests (investment helpers). Remove `src/tickoni/demo/` directory entirely.
- The `tickoni-supervisor demo investment` CLI subcommand — remove dispatch from `main.zig`. This is part of the same cleanup: the CLI command exists solely to exercise test utilities.
- Historical audit reports — these are records of what was verified at a point in time. Do not touch.

## Files to touch

### Justfile ecosystem

| File | Change |
|------|--------|
| `justfile` (line 26) | `import "just/test/demo.just"` → `import "just/test/cli.just"` |
| `just/test/demo.just` | Rename to `just/test/cli.just`; update all recipe names and comments |
| `just/test/all.just` | No change currently (demo not in test-all aggregator) |

### CI

| File | Change |
|------|--------|
| `.github/workflows/_ci-demo.yml` | Rename to `.github/workflows/_ci-cli.yml`; update workflow name, job name, step name, all test-recipe references |

### Dispatch

| File | Change |
|------|--------|
| `scripts/dispatch-map.json` | Key `"test-demo-tk"` → `"test-cli-tk"`; all value entries updated |

### Documentation (update)

| File | Change |
|------|--------|
| `doc/execution/testing-tickoni.md` | `test-demo-tk` → `test-cli-tk` everywhere |
| `doc/execution/plans/tests-all-template.md` | `test-demo-tk` → `test-cli-tk`; `demo-conformance` → `cli-conformance` |
| `doc/execution/plans/hygiene-migrate-demo-tests-from-bash-to-pytest.md` | `test-demo-tk` → `test-cli-tk`; `demo.just` → `cli.just` |
| `doc/execution/quality.md` | `test-demo-tk` → `test-cli-tk` |
| `doc/strategy/templates/story-template.md` | `test-demo-tk` → `test-cli-tk` (template pattern) |
| `doc/strategy/roadmap/epics/v1.11.md` | `test-demo-tk` → `test-cli-tk` |
| `doc/strategy/roadmap/stories/v2.10-s8.md` | `test-demo-tk` → `test-cli-tk`; `demo-conformance` → `cli-conformance` |
| `doc/strategy/roadmap/stories/v2.10-s12.md` | `test-demo-tk` → `test-cli-tk` |
| `doc/strategy/roadmap/stories/v2.10-s14.md` | `test-demo-tk` → `test-cli-tk` |
| `doc/strategy/roadmap/stories/v3.19-s*.md` | `test-demo-tk` → `test-cli-tk` (all 8 story files) |
| `doc/strategy/roadmap/stories/v3.23-s*.md` | `test-demo-tk` → `test-cli-tk` (all 4 story files) |

### Documentation (do NOT touch — historical records)

- `doc/execution/audits/stories/V2.10.S*-quality-gate.md`
- `doc/execution/audits/stories/V2.10.S*-security-audit.md`
- `doc/execution/audits/stories/V2.10.S*-maintainability-audit.md`
- `doc/execution/audits/stories/V2.22.S*-quality-gate.md`
- `doc/execution/audits/stories/V2.22.S*-telemetry-audit.md`
- `doc/execution/audits/stories/V2.22.S*-zig-audit.md`
- `doc/execution/audits/stories/V2.21.S*-quality-gate.md`
- `doc/execution/audits/stories/V2.10.S10-maintainability-audit.md`

## Architectural Findings (updated)

All 5 conformance modules in `src/tickoni/demo/` are imported ONLY by the demo CLI command in `main.zig`. They are test utilities, not production code:

| Module | Responsibility | Import scope | Unit tests |
|---|---|---|---|
| `preflight.zig` | Manifest validation (runtime tier, version, isolation, fixtures) | Demo CLI only | In-file |
| `runner.zig` | Builds `Artifact` from `BackendResult` + fixture files | Demo CLI only | In-file |
| `conformance.zig` | `Artifact` struct, `sha256Hex()`, JSON/plain serialization | Demo CLI only | In-file |
| `comparator.zig` | Cross-platform `Artifact` comparison (ignores runtime/isolation tier) | Demo CLI only | In-file |
| `substitution.zig` | Maps scenario names → `BackendResult` configs | Demo CLI only | In-file |

**No separate `conformance_test` binary is needed.** All modules already have in-file unit tests. They should be absorbed into existing test infrastructure:

| Module | Absorb into | Method |
|---|---|---|
| `preflight.zig` | Unit tests (stays in `src/tickoni/demo/`) | Remove from `main.zig` dispatch; unit tests remain |
| `runner.zig` | Unit tests | Same |
| `conformance.zig` | Unit tests | Same |
| `comparator.zig` | Unit tests | Same |
| `substitution.zig` | Demo/investment helpers | Move to `src/tickoni/test/demo/investment/` (demo-only scope) |
| `demo/investment/mod.zig` | Integration tests | Move `runSystemSuite()` logic into `src/tickoni/test/integration/` |

The only gap the demo CLI covered (cross-platform hash stability) is already exercised by integration tests that read fixture files. The comparator's logic can live as unit tests.

## Order of operations

1. **Remove** `demo` CLI subcommand from `main.zig` dispatch (eliminates production exposure)
2. **Move** `substitution.zig` → `src/tickoni/test/demo/investment/` (demo-only scope)
3. **Move** `mod.zig` `runSystemSuite()` logic → `src/tickoni/test/integration/` integration test
4. Rename `just/test/demo.just` → `just/test/cli.just` (all recipe names, comments, file-level header)
5. Update `justfile` import line
6. Rename `.github/workflows/_ci-demo.yml` → `.github/workflows/_ci-cli.yml` (all references inside)
7. Update `scripts/dispatch-map.json`
8. Batch-update documentation references (search/replace `test-demo-tk` → `test-cli-tk`)
9. Verify: `just --list` shows new names; grep confirms no stale `test-demo-tk` references remain in non-audit files; `zig build test` passes
