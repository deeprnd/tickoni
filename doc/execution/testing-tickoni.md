# Tickoni Testing

This document summarizes the justfile-oriented test layers for the current
Tickoni repository.

<p align="center">
  <!-- badge:build:start -->
  <img alt="Build" src="https://img.shields.io/badge/build-passing-brightgreen?style=flat-square" />
  <!-- badge:build:end -->

  <!-- badge:quality:start -->
  <img alt="Quality" src="https://img.shields.io/badge/quality-failing-red?style=flat-square" />
  <!-- badge:quality:end -->

  <!-- badge:security:start -->
  <img alt="Security" src="https://img.shields.io/badge/security-unknown-lightgrey?style=flat-square" />
  <!-- badge:security:end -->
</p>

<p align="center">
  <!-- badge:unit:start -->
  <img alt="Unit Tests" src="https://img.shields.io/badge/unit%20tests-failing-red?style=flat-square" />
  <!-- badge:unit:end -->

  <!-- badge:integration:start -->
  <img alt="Integration Tests" src="https://img.shields.io/badge/integration%20tests-failing-red?style=flat-square" />
  <!-- badge:integration:end -->

  <!-- badge:system:start -->
  <img alt="System Tests" src="https://img.shields.io/badge/system%20tests-unknown-lightgrey?style=flat-square" />
  <!-- badge:system:end -->

  <!-- badge:e2e:start -->
  <img alt="E2E Tests" src="https://img.shields.io/badge/e2e%20tests-unknown-lightgrey?style=flat-square" />
  <!-- badge:e2e:end -->
</p>

<p align="center">
  <!-- badge:cov-fd:start -->
  <img alt="Engine Coverage" src="https://img.shields.io/badge/engine%20coverage-unknown-lightgrey?style=flat-square" />
  <!-- badge:cov-fd:end -->

  <!-- badge:cov-tk:start -->
  <img alt="AI Harness Coverage" src="https://img.shields.io/badge/harness%20coverage-unknown-lightgrey?style=flat-square" />
  <!-- badge:cov-tk:end -->
</p>

The [Testing Firedancer](../testing.md) page is the Firedancer-style test
guide. This file is intentionally separate for now so the current `justfile`
command matrix can be documented without merging those two views.

## Test-Driven Development

Tickoni development should follow test-driven development. After planning a
change and before implementing it, write the narrowest test that captures the
new behavior, regression, or invariant. The implementation is complete only
when that test passes in the correct lane and the relevant broader validation
still passes.

Do not rely on custom throwaway verification scripts as the only proof for new
behavior. If a one-off script or ad hoc command is needed to prove a feature,
that is a signal that a unit, integration, e2e, system, quality, or security
test is missing. Add the test to the correct scope below and wire it through
the existing `justfile`, `build.zig`, or Make-backed command path as
appropriate.

## Test Layers

The repository currently has:

- Harness unit tests for Tickoni-owned supervisor, topology, queue, sandbox,
  Phase 0 payment pipeline, audit, case, disp, schema, model, adapter, and
  evidence module behavior
- **Deterministic demo conformance suite** — fixture-backed, no llama.cpp or
  live tiles required. Verifies `tickoni --version`, `tickoni doctor`, and
  `tickoni-supervisor demo investment` against a known manifest. Produces
  `conformance.json` bundles that can be compared across platforms.
- Tickoni integration tests for schema pipeline fixture contracts and
  tile-boundary scenario coverage (tkcase, tkdisp, tkagnt, replay, audit)
- explicit Tickoni system tests for live `tkmodl` compatibility against a local
  `llama.cpp` server and downloaded GGUF model
- Firedancer-derived C unit tests through the upstream unit-test Make target
- Firedancer-derived e2e/integration-test build and run target
- Cross-platform conformance comparison via
  `contrib/test/compare_demo_conformance.py` (ignores platform-specific fields)
- Aggregate gates that compose build, quality, security, and test checks

## Core Commands

Tickoni-owned Zig:

- `just test-unit-tk` — Tickoni harness unit tests (Zig `zig build test`)
- `just test-demo-tk` — **Deterministic demo conformance suite** (fixture-backed, no llama.cpp)
- `just test-integration-tk` — Tickoni integration tests (Zig `zig build integration-test`)
- `just test-system-tk` — System tests with live llama.cpp server

Firedancer-derived C:

- `just test-unit-fd` — Firedancer unit tests (Make-backed, huge-page aware)
- `just test-e2e-fd` — Firedancer integration-test / local topology

Aggregates:

- `just test-unit-all` — unit lane across all codebases
- `just test-integration-all` — integration lane
- `just test-e2e-all` — e2e lane
- `just test-system-all` — system lane (requires llama.cpp)
- `just test-all` — unit + integration + system + e2e
- `just test-cov-tk` — Tickoni harness coverage
- `just test-cov-fd` — Firedancer coverage (pre-optional, toolchain may be missing)
- `just test-cov-all` — both coverage lanes
- `just tests-all` — build + quality + security + tests (full handoff gate)

Current placeholder test recipes:

- `just test-integration-fd` — no-op (`@true`). Firedancer does not have a
  separate repo-facing intermediate integration layer.
- `just test-e2e-tk` — no-op (`@true`). Tickoni e2e is currently folded into
  `test-demo-tk` and `test-e2e-fd`.
- `just test-system-fd` — no-op (`@true`). Firedancer system testing uses
  `test-e2e-fd` (Firedancer's integration-test target).
- `just test-cov-fd` — no-op (pre-existing llvm-cov toolchain not installed).

Placeholder commands return `@true` in the `justfile`, following the repo
tooling rule that no-op component variants live in the `justfile` and not in
shell scripts. Do not remove or rename them without explicit instruction.

## What `tests-all` Runs

`just tests-all` runs these commands in order:

1. `just build-all`
2. `just quality-format-check-all`
3. `just quality-lint-check-tk`
4. `just quality-proto-check-all`
5. `@true # security-check-all: pre-existing IBT linker failure on host clang`
6. `just security-engine-check-changes`
7. `just test-all`

`just test-all` runs these commands in order:

1. `just test-unit-all`
2. `just test-integration-all`
3. `just test-cov-all`
4. `just test-system-all`
5. `just test-e2e-all`

`just test-unit-all` is badge-wrapped through
`contrib/readme/run-badged-command.py` so the README status badges reflect the
same aggregate commands developers use locally.

## Demo Conformance Suite (test-demo-tk)

The demo conformance suite is a **deterministic, fixture-backed test layer**
that does not require llama.cpp, live tiles, or any external tooling. It is the
primary CI validation path for cross-platform conformance (Linux, macOS, Windows
x86/ARM) and is part of every `tests-all` run.

### What it verifies

1. **`tickoni --version` contract** — asserts the output starts with `Tickoni `
   and contains all required fields: Build ID, Git, OS, Runtime Tier, Isolation
   Tier, Policy Schema, Replay Schema, Demo Manifest, Compiler.

2. **`tickoni doctor` contracts** — verifies both `--plain` and `--json` output.
   Plain output must contain `tickoni doctor — host report` and `Platform tier:`.
   JSON output must contain `platform_tier`, `result`, and `checks` array.

3. **`tickoni-supervisor demo` bare usage fails closed** — running `demo` without
   a manifest path or `--manifest` flag must exit non-zero.

4. **`tickoni-supervisor demo investment` with fixture manifest** — runs the
   deterministic investment demo against `src/tickoni/demo/fixtures/demo.manifest.json`,
   producing conformance output with:
   - `suite` array: one entry per scenario (each entry has `scenario`,
     `pass`/`fail` status, `event_hash`, optional `audit_jsonl_path`,
     `replay_capsule_path`, optional `blocked_diagnostic`)
   - `comparison` object: cross-scenario analysis (baseline_runtime_tier,
     all_match, scenarios summary)

### Conformance bundle format

The output is written to
`build/demo-conformance/<platform>/conformance.json` and
`build/demo-conformance/<platform>/comparison.json` (via
`contrib/test/export_demo_conformance_bundle.py`).

Fields that vary by platform and are ignored during cross-platform comparison:
- `runtime_tier`, `isolation_tier` (top-level per-artifact)
- `baseline_runtime_tier`, `all_match` (top-level comparison)

Fields compared across platforms:
- Scenario names and descriptions
- Event hashes and replay capsule references
- Audit JSONL paths and content

### Cross-platform comparison

`contrib/test/compare_demo_conformance.py` accepts 2+ conformance JSON files and
does pairwise comparison. Platform-specific fields are normalized out so bundles
from different OS/arch pairs can be compared cleanly. This is how CI validates
that Windows x86, Windows ARM, macOS x86/ARM, and Linux produce matching
deterministic outputs.

## Test Selection Rules

Run the narrowest relevant set first, then broaden when risk is high. The
current test task source of truth is the repository root `justfile`; run these
commands from the repository root unless noted otherwise.

- Tickoni Zig supervisor, topology, tile lifecycle, queue wrapper, sandbox
  wrapper, Phase 0 payment pipeline, schema, model, adapter, or evidence
  change: `just test-unit-tk`
- Tickoni coverage-sensitive change: `just test-cov-tk`
- Firedancer-derived C infrastructure, tango, disco, waltz, util, or ballet
  change: `just test-unit-fd`
- Firedancer coverage-sensitive change: `just test-cov-fd`
- **Demo manifest, demo module, CLI version/doctor contract, conformance output
  format, or cross-platform conformance comparison change**: `just test-demo-tk`
  (also run `contrib/test/compare_demo_conformance.py` manually to verify
  cross-platform coherence)
- Cross-boundary Tickoni/Firedancer unit-impacting change: `just test-unit-all`
- Runtime topology, workspace setup, local process startup, Firedancer dev path,
  or e2e/system behavior change: `just test-e2e-fd`
- Live `tkmodl` HTTP compatibility, llama.cpp startup, GGUF model wiring, or
  local OpenAI-compatible server behavior change: `just test-system-tk`
  (requires `infra-ensure-llamacpp` first)
- **Windows-specific changes**: `just test-unit-tk-windows-x86` or
  `just test-unit-tk-windows-arm` (builds FD libs for the target platform first,
  then runs Zig unit tests)
- Cross-cutting local runtime validation: `just test-all`
- Broad coverage validation: `just test-cov-all`
- Full repository validation with build, quality, security, and tests:
  `just tests-all`
- **Full handoff validation** (build + quality + security + all tests):
  `just tests-all`

Current placeholder test recipes are intentionally kept in the `justfile` so the
command shape remains stable while Tickoni-specific integration and e2e layers
are still being built:

- `just test-integration-fd`
- `just test-e2e-tk`
- `just test-system-fd`
- `just test-cov-fd`

Do not remove, rename, or repurpose these placeholders as part of ordinary
focused changes unless the user explicitly asks for that migration. When a
change may affect behavior that is currently covered only by the Firedancer
runtime path, or before broad handoff on risky work, run:

- `just test-e2e-fd`

If you do not run a relevant check, say so explicitly in the handoff.

## Layer Boundaries And Mocking

The test layer is determined by where replacement happens.

Unit tests replace direct collaborators at the function, tile helper, or module
boundary. A unit test may use a deterministic allocator, fixed payment pipeline
configuration, synthetic input event, fake clock value, direct queue instance,
or in-process supervisor state so the behavior under test stays one small unit
of code. Unit tests should not prove Firedancer process startup, seccomp policy
installation, real shared-memory workspace behavior, full Make integration-test
targets, or live external tool compatibility.

Integration tests keep Tickoni internals real and replace whole outside tools
at the harness boundary. Runtime topology, tile wiring, bounded queue behavior,
event normalization, deduplication, policy evaluation, audit hashing, replay
comparison, serialization, and C ABI wrappers should run through production-like
paths. The harness may substitute external systems with deterministic local
fixtures: a temporary filesystem store instead of a durable deployment store, a
localhost HTTP/RPC stub instead of a future payment processor or model gateway,
or a test shared-memory/workspace harness instead of an operator-managed host
setup. This is the same kind of replacement as using a compatible test engine
for an external database: the outside tool is substituted, but the application
path that talks to it remains real.

E2E and system tests use the actual local runtime tools in a local topology:
the Firedancer-derived Make targets, the `tickoni-supervisor` Zig binary,
wrapper scripts, huge-page setup where needed, and local process or future
container orchestration. These tests verify startup, command contracts, runtime
wiring, persistence or audit output, telemetry surface, and local tool
compatibility. They do not claim production scalability, high availability, or
managed-service parity: a local process topology is not a production supervised
deployment, and local huge-page allocation is not an operator-tuned host fleet.

**Demo conformance** is a special case: it runs the real `tickoni-supervisor`
binary and real Tickoni demo modules, but the demo modules read from fixture
files rather than live tools. It is therefore a system-level test that is
deterministic and fast enough to run on every CI commit across all platforms.
It sits between integration and system in the spectrum: real code, stubbed
external effects.

Firedancer does not map cleanly onto the three-layer application-test split
used by many service repos. Its C tests are mostly:

- unit tests for libraries and individual tiles, often with adjacent tile/link
  behavior mocked or injected directly into the tile under test
- app-level `integration-test` binaries that bring up the Firedancer dev
  runtime path and full local topology pieces

There is not a normal "2 or 3 real tiles only" integration layer for
Firedancer-side work. A tile test such as `test_verify_tile` builds a mock
topology and injects mock inputs into the `verify` tile. A tile test such as
`test_repair_tile` overrides adjacent stem publication/sign behavior so the
repair tile lifecycle can be tested without real tile infrastructure. The
`test_firedancer_dev` integration test is the opposite end of the spectrum: it
initializes Firedancer config/topology and forks the configure, workspace, dev,
and ready command paths.

That is why this repo routes `just test-e2e-fd` to Firedancer's
`make integration-test && make run-integration-test`, while
`just test-integration-fd` is only a placeholder. In Tickoni's repo-facing
taxonomy, Firedancer's Make `integration-test` target behaves like an
e2e/system check because it exercises the local runtime topology rather than an
intermediate subset of real tiles.

Practical rule of thumb:

- unit: mock or fix the direct collaborator function, module, tile helper, or
  runtime input
- integration: substitute the external tool through the shared harness while
  keeping Tickoni internals real
- e2e/system: run the real local toolchain and avoid internal mocks
- demo conformance: run real binaries with fixture data (deterministic,
  cross-platform comparable)

## Harness Unit Tests

`just test-unit-tk` runs:

```bash
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} test --summary all
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} run-tests
```

On Windows, `just test-unit-tk` delegates to
`just test-unit-tk-windows-x86` or `just test-unit-tk-windows-arm`, which first
build the Firedancer libraries for the target platform before running the Zig
tests.

The boundary for this lane is the directory: every Tickoni-owned test root that
is not under `src/tickoni/test/integration/` or `src/tickoni/test/system/` runs
here. In practice that means the runtime, C ABI, and tile modules' own inline
`test` blocks, all schema modules under `src/tickoni/schema/`, the supervisor
binary, and everything under `src/tickoni/test/fixtures/`,
`src/tickoni/test/mocks/`, `src/tickoni/test/demo/`, and
`src/tickoni/evidence/` — fixture-contract tests, mock self-tests, demo-module
tests, and evidence module tests are unit-lane by directory even where they
substitute an external system, because that substitution happens outside
`src/tickoni/test/integration/`.

The current Zig test graph is defined in [build.zig](../../build.zig); consult
it for the exact current set of test roots rather than treating any list here
as authoritative.

## Engine Unit Tests

`just test-unit-fd` runs a wrapper around the Firedancer-derived unit-test
Make targets.

All Firedancer builds use the `tickoni_fd` machine profile, which scopes the
build to only the 5 libraries Tickoni reuses (`fd_tango`, `fd_util`,
`fd_ballet`, `fd_disco`, `fd_waltz`). This excludes Solana validator tiles,
RPC schemas, and unrelated Firedancer source.

It performs these steps:

1. attempts to free previous gigantic page allocations
2. computes an automatic gigantic-page allocation target from available RAM
3. allocates gigantic pages on NUMA node `0` when possible
4. raises the current shell's memlock limit with `sudo prlimit`
5. builds unit tests with `make -j"$(nproc)" unit-test`
6. runs `make run-unit-test`
7. falls back to `make run-unit-test TEST_OPTS="--page-sz normal"` when
   gigantic pages are unavailable

On macOS and Windows, `just test-unit-fd` delegates to the platform build
recipe (e.g. `build-fd-macos-arm`) and then runs `just test-unit-tk` instead,
because Firedancer C unit tests require Linux. This is the same routing pattern
as `build-fd` — the justfile auto-detects the host platform.

This wrapper is the preferred repo-facing Firedancer unit-test command. Do not
invoke raw compiler commands for Firedancer tests.

## Engine E2E

`just test-e2e-fd` runs:

```bash
make -j"$(nproc)" MACHINE=tickoni_fd BUILDDIR={{fd_tickoni_build}} integration-test && \
make MACHINE=tickoni_fd BUILDDIR={{fd_tickoni_build}} run-integration-test
```

This intentionally uses Firedancer's Make `integration-test` class. In
Firedancer terminology, `test_firedancer_dev` is an integration test. In this
repo's `justfile` taxonomy, that same target is treated as e2e/system because
it starts the Firedancer dev command path and local topology pieces instead of
testing a small intermediate group of tiles.

`just test-e2e-tk` is currently a no-op placeholder.

## Integration Layer

`just test-integration-fd` is a placeholder (`@true`). Firedancer does not have
a separate repo-facing intermediate integration layer between tile/unit tests
and full-topology `integration-test` binaries.

`just test-integration-tk` runs:

```bash
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/zigw.sh build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} integration-test
```

On Windows, `just test-integration-tk` delegates to
`just test-integration-tk-windows-x86` or `just test-integration-tk-windows-arm`,
which first builds the Firedancer libraries for the target platform.

The boundary for this lane is the directory: every test root under
`src/tickoni/test/integration/` runs here, and nothing outside that directory
does. Tickoni internals run through production-like paths (tile wiring,
replay, audit, decision cards, transport wiring); model and adapter backends
are substituted with fixture or local mock-server backends so no network calls
leave the process. Fixture-contract tests and mock-server self-tests live
elsewhere in the test tree and so run under `just test-unit-tk` instead, even
where they substitute external systems the same way integration tests do —
the directory, not the mocking style, decides the lane.

`just test-integration-all` composes this lane with the current Tickoni
integration wiring so the aggregate command shape stays stable as coverage
grows.

## Explicit System Lane

`just test-system-tk` runs:

```bash
bash contrib/test/run_system_model_tests.sh
```

This lane starts a real local `llama.cpp` server, waits for its health endpoint,
and runs:

```bash
zig build system-test
```

Before running system tests, ensure the llama.cpp server is set up:

```bash
just infra-ensure-llamacpp   # build llama.cpp (CPU or CUDA if GPU detected)
just infra-ensure-model      # download GGUF model (requires `hf` CLI)
just infra-run-llamacpp      # start llama-server
```

On Windows, `just test-system-tk` delegates to
`just test-system-tk-windows-x86` or `just test-system-tk-windows-arm`, which
use `infra-ensure-llamacpp-win` and `infra-run-llamacpp-win` (CPU-only, no CUDA
on CI runners).

The boundary for this lane is also the directory: every test root under
`src/tickoni/test/system/` runs here, and nothing outside that directory does.
Not every root in this directory needs the live server itself — a deterministic,
fixture-backed proof can live here too if it belongs conceptually with the
other system-level demo proofs — but all of them run together under this one
lane because of where they live, not because of what each one mocks.

It is intentionally not part of `just test-integration-all` or `just test-all`.
The live model server, downloaded GGUF asset, and localhost HTTP surface make
this a system/smoke compatibility check rather than the default integration
lane.

## Demo Conformance Verification

The demo conformance suite produces artifacts under
`build/demo-conformance/<platform>/`. On CI, these are uploaded as artifacts.
The local canonical copy lives at
`build/demo-conformance/local-sample/conformance.json`.

To re-run and capture local artifacts:

```bash
just test-demo-tk                          # build + run full demo conformance
python3 contrib/test/export_demo_conformance_bundle.py . build/demo-conformance/local-sample
python3 contrib/test/compare_demo_conformance.py build/demo-conformance/linux/conformance.json build/demo-conformance/local-sample/conformance.json
```

## Quality And Security Gates

Preferred validation commands in order:

- `just quality-format-check-tk` validates `zig fmt --check` for the
  Tickoni-owned Zig source trees.
- `just quality-format-check-fd` validates trailing whitespace for changed
  non-Tickoni-owned paths, including Firedancer-derived C, docs, and scripts.
- `just quality-format-check-all` runs both formatting lanes.
- If formatting fails, prefer `just quality-format-fix-tk`,
  `just quality-format-fix-fd`, or `just quality-format-fix-all`, then only
  apply targeted manual formatting if automatic fixing still leaves failures.
- `just quality-lint-check-tk` runs Tickoni-owned lint checks.
- `just quality-lint-check-fd` runs Firedancer-derived lint checks and
  `shellcheck` when that tool is installed.
- `just quality-lint-check-all` runs both lint lanes.
- `just quality-check-all` runs the main repository quality bundle:
  format-check all lanes, then lint-check all lanes.
- `just security-gitleaks-check-all` scans the current Tickoni and
  Firedancer-owned source scopes for secret leaks.
- `just security-codeql-check-all` runs the configured CodeQL recipe variants.
  Some current variants are no-op placeholders while local setup is blocked or
  not yet wired.
- `just security-seccomp-check-all` runs the configured seccomp recipe variants.
  Current placeholder components are documented in [Security](./security.md).
- `just security-proof-check-all` runs proof-related checks for the lanes that
  currently expose them.
- `just security-sanitize-check-all` runs sanitizer-oriented checks, including
  Tickoni `ReleaseSafe` Zig tests and the Firedancer sanitizer path.
- `just security-check-all` runs the full repository security bundle:
  CodeQL, gitleaks, seccomp, proof, and sanitizer checks.
- `just test-unit-tk` runs Tickoni Zig harness unit tests.
- `just test-unit-fd` runs Firedancer-derived C unit tests through the
  repository wrapper that manages huge-page setup and normal-page fallback.
- `just test-unit-all` runs both unit lanes.
- `just test-integration-all` currently runs placeholder integration lanes so
  the aggregate command shape remains stable.
- `just test-e2e-fd` runs the Firedancer-derived local runtime integration-test
  build and execution path, surfaced as this repo's e2e/system lane.
- `just test-e2e-all` runs the Firedancer e2e/system lane plus the current
  Tickoni e2e placeholder.
- `just test-cov-tk` runs Tickoni harness coverage.
- `just test-cov-fd` runs Firedancer-derived C coverage with reduced
  parallelism for local and CI memory limits.
- `just test-cov-all` runs both coverage lanes.
- `just test-all` runs the broad test bundle: unit, integration, system, e2e.
- `just tests-all` runs the full local handoff gate: build, quality, security,
  and tests.

For broad changes, use:

- `just test-all`

For full handoff validation when build, quality, security, and runtime risk are
all in scope, use:

- `just tests-all`

If you skip a relevant gate because it is too expensive, needs unavailable
local tools, or requires host privileges such as huge-page or memlock setup,
call that out explicitly in the handoff.

## Related Docs

- [Development](./development.md)
- [Security](./security.md)
- [Observability](./observability.md)
