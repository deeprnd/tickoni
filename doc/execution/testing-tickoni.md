# Tickoni Testing

This document summarizes the justfile-oriented test layers for the current
Tickoni repository.

<p align="center">
  <!-- badge:build:start -->
  <img alt="Build" src="https://img.shields.io/badge/build-passing-brightgreen?style=flat-square" />
  <!-- badge:build:end -->

  <!-- badge:quality:start -->
  <img alt="Quality" src="https://img.shields.io/badge/quality-unknown-lightgrey?style=flat-square" />
  <!-- badge:quality:end -->

  <!-- badge:security:start -->
  <img alt="Security" src="https://img.shields.io/badge/security-passing-brightgreen?style=flat-square" />
  <!-- badge:security:end -->
</p>

<p align="center">
  <!-- badge:unit:start -->
  <img alt="Unit Tests" src="https://img.shields.io/badge/unit%20tests-passing-brightgreen?style=flat-square" />
  <!-- badge:unit:end -->

  <!-- badge:integration:start -->
  <img alt="Integration Tests" src="https://img.shields.io/badge/integration%20tests-passing-brightgreen?style=flat-square" />
  <!-- badge:integration:end -->

  <!-- badge:system:start -->
  <img alt="System Tests" src="https://img.shields.io/badge/system%20tests-passing-brightgreen?style=flat-square" />
  <!-- badge:system:end -->

  <!-- badge:e2e:start -->
  <img alt="E2E Tests" src="https://img.shields.io/badge/e2e%20tests-passing-brightgreen?style=flat-square" />
  <!-- badge:e2e:end -->
</p>

<p align="center">
  <!-- badge:cov-fd:start -->
  <img alt="Engine Coverage" src="https://img.shields.io/badge/engine%20coverage-unknown-lightgrey?style=flat-square" />
  <!-- badge:cov-fd:end -->

  <!-- badge:cov-tk:start -->
  <img alt="Tests Coverage" src="https://img.shields.io/badge/tests%20coverage-86.8%25-yellowgreen?style=flat-square" />
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
- Qt harness tests for the Qt terminal CMake build tree
- **CLI unit and integration tests** — fixture-backed, no llama.cpp or
  live tiles required. Verifies `tickoni --version` and `tickoni doctor`
  contracts via `test-unit-cli` and `test-integration-cli`.
- Tickoni integration tests for schema pipeline fixture contracts and
  tile-boundary scenario coverage (tkcase, tkdisp, tkagnt, replay, audit)
- explicit Tickoni system tests for live `tkmodl` compatibility against a local
  `llama.cpp` server and downloaded GGUF model
- Firedancer-derived C unit tests through the upstream unit-test Make target
- Firedancer-derived e2e/integration-test through CI (locally, `test-e2e-fd` is a no-op)
- Cross-platform conformance comparison via
  `contrib/tool/readme/compare_build_artifact_conformance.py` (ignores platform-specific fields)
- Aggregate gates that compose build, quality, security, and test checks

## Test Commands

CI uses the platform-qualified forms of these recipes. The bare forms below
are local host dispatchers only.

Tickoni-owned Zig:

- `just test-unit-tk` — Tickoni harness unit tests (unified `zig build test-unit-tk` compiles + runs)
- `just test-unit-cli` — CLI unit tests (`tickoni --version` and `tickoni doctor` contracts)
- `just test-integration-tk` — Tickoni integration tests (Zig `zig build integration-test`)
- `just test-integration-cli` — CLI integration tests (spawn the `tickoni` binary)
- `just test-system-tk` — System tests with live llama.cpp server

Qt terminal:

- `just test-qt` — Qt CMake build and smoke test
- `just test-qt-linux-x86` — Qt build + smoke on Linux x86

Firedancer-derived C:

- `just test-unit-fd` — Firedancer unit tests (Make-backed, huge-page aware)
- `just test-e2e-fd` — **no-op placeholder** (`@true`). The Firedancer integration-test target is exercised through CI directly; this recipe has not been wired locally.

Aggregates:

- `just test-unit-all` — unit lane across all codebases (unit + CLI + infra + FD); badge-wrapped through `contrib/tool/readme/run-badged-command.py`
- `just test-integration-all` — integration lane (integration-tk + CLI integration)
- `just test-e2e-all` — e2e lane (currently all no-op placeholders)
- `just test-system-all` — system lane (requires llama.cpp)
- `just test-all` — unit + integration + coverage + system + e2e
- `just test-cov-tk` — Tickoni harness coverage
- `just test-cov-fd` — Firedancer coverage (no-op locally; CI coverage is pre-existing and requires LLVM toolchain)
- `just test-cov-all` — both coverage lanes
- `just tests-all` — build + quality + security + tests (full handoff gate, aggregator-of-aggregators only)

Current placeholder test recipes:

- `just test-integration-fd` — no-op (`@true`). Firedancer does not have a
  separate repo-facing intermediate integration layer.
- `just test-e2e-tk` — no-op (`@true`). Tickoni e2e is currently folded into
  `test-integration-cli` and `test-e2e-fd` (which is also a no-op). E2E-tk is
  waiting for 3rd-party system integrations to be available locally.
- `just test-system-fd` — no-op (`@true`). Firedancer system testing uses
  `test-e2e-fd` (also a no-op locally; CI exercises Firedancer integration-test directly).
- `just test-e2e-fd` — no-op (`@true`). E2E-fd is stubbed for good cause:
  these are Firedancer internals and we don't need to e2e-test them here. CI
  exercises Firedancer's `integration-test` target directly through the build
  stage rather than this local recipe.

Placeholder commands return `@true` in the `justfile`, following the repo
tooling rule that no-op component variants live in the `justfile` and not in
shell scripts. Do not remove or rename them without explicit instruction.

## What `tests-all` Runs

`just tests-all` runs these commands in order (aggregator-of-aggregators only):

1. `just quality-check-all` — format + lint + proto + yaml + spell
2. `just build-all` — Firedancer + Tickoni + Qt
3. `just test-all` — unit + integration + coverage + system + e2e
4. `just security-check-all` — engine + CodeQL + gitleaks + seccomp + proof + sanitizer

`just test-all` runs these commands in order:

1. `just test-unit-all`
2. `just test-integration-all`
3. `just test-cov-all`
4. `just test-system-all`
5. `just test-e2e-all`

`just test-unit-all` is badge-wrapped through
`contrib/tool/readme/run-badged-command.py` so the README status badges reflect the
same aggregate commands developers use locally.

## CLI Unit and Integration Tests

The CLI test layer replaces the former "demo conformance suite". It tests the
`tickoni` binary directly (via `test-unit-cli`) and its integration behavior
(via `test-integration-cli`) without requiring llama.cpp, live tiles, or any
external tooling.

### What it verifies

1. **`tickoni --version` contract** — asserts the output starts with `Tickoni `
   and contains all required fields: Build ID, Git, OS, Runtime Tier, Isolation
   Tier, Policy Schema, Replay Schema, Compiler.

2. **`tickoni doctor` contracts** — verifies both `--plain` and `--json` output.
   Plain output must contain `tickoni doctor — host report` and `Platform tier:`.
   JSON output must contain `platform_tier`, `result`, and `checks` array.

### Cross-platform CI

The `fixture-cli` CI job in `_ci-cli.yml` runs `test-integration-cli` on all
supported platforms (Linux x86/ARM, macOS x86/ARM, Windows x86/ARM) to verify
the binary runs correctly and the version/doctor contracts hold.

## Infrastructure (Python) Unit Tests

`just test-unit-infra-all` runs Python `pytest` suites across three contrib
subtrees, each testing build, setup, or tooling infrastructure rather than
application code:

- `just test-unit-infra-build` — `contrib/build/tests/`
  (`test_build_orchestrator.py`, `test_build_resolve_make.py`,
  `test_zig_build_configuration.py`)
- `just test-unit-infra-setup` — `contrib/setup/tests/`
  (`test_setup_asset_resolution.py`, `test_setup_ccache.py`, `test_setup_checks.py`,
  `test_setup_install_method.py`, `test_setup_minisign.py`, `test_setup_msvc.py`,
  `test_setup_openssl_build.py`, `test_setup_shell.py`, `test_setup_zig.py`)
- `just test-unit-infra-tooling` — `contrib/tool/tests/`
  (`test_dynamic_test_opts.py`, `test_justfile_script_refs.py`,
  `test_llama_server.py`, `test_qt_installer.py`, `test_badge_updater.py`)

These tests validate Python infrastructure that the build, CI, and developer
tooling depend on. They are included in `test-unit-all` via
`test-unit-infra-all` so they run alongside Zig unit tests and CLI tests.
The pytest cache and basetemp live under `just/build/pytest` and
`just/build/pytest-cache` to keep them out of source control.

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
- **CLI version/doctor contract, or tickoni binary change**: `just test-unit-cli` and `just test-integration-cli`
- Cross-boundary Tickoni/Firedancer unit-impacting change: `just test-unit-all`
- Qt terminal C++ or QML change: `just test-qt`
- Runtime topology, workspace setup, local process startup, Firedancer dev path,
  or e2e/system behavior change: `just test-e2e-fd`
- Live `tkmodl` HTTP compatibility, llama.cpp startup, GGUF model wiring, or
  local OpenAI-compatible server behavior change: `just test-system-tk`
  (requires `infra-ensure-llamacpp` first)
- **Windows-specific changes**: `just test-unit-tk-windows-x86` or
  `just test-unit-tk-windows-arm`
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
- `just test-e2e-fd`

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

**Qt terminal** is a CMake build tree (`src/tickoni/terminal/`) with no
Firedancer, Zig, or Tickoni runtime dependency. Qt tests are build-and-smoke:
they compile with Clang, run the binary to verify it launches and renders
correctly, and apply clang-format and lint checks in quality gates. The Qt
terminal does not call model/adapter/execution backends, so it does not need
fixture substitution or mock servers.

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

Practical rule of thumb:

- unit: mock or fix the direct collaborator function, module, tile helper, or
  runtime input
- integration: substitute the external tool through the shared harness while
  keeping Tickoni internals real
- e2e/system: run the real local toolchain and avoid internal mocks
- CLI unit/integration: run the `tickoni` binary against fixture data
  (deterministic, cross-platform comparable)

## Harness Unit Tests

`just test-unit-tk` runs:

```bash
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{fd_tickoni_lib}} test-unit-tk
```

This is a single command: Zig's `addRunArtifact` compiles all test binaries
and runs them sequentially in one `zig build` invocation. The old two-step
pattern (`zig build test` then `run-tests`) was replaced with the unified
compile+run model that Zig natively supports — matching what Rust (`cargo
test`), Go (`go test`), Python (`pytest`), and most modern ecosystems do.

The `test` step (compile-only) is still available for CI use cases that need
to build test binaries without running them. `test-unit-tk` is the
compile+run entry point that developers use locally.

On Windows and macOS, `just test-unit-tk` delegates to platform-specific
recipes (`test-unit-tk-windows-x86`, `test-unit-tk-macos-arm`, etc.) which
use the same Zig `build.zig` graph. Firedancer library dependencies are
expected to be built separately (`just build-fd-{platform}`) or available
via pre-built CI artifacts.

The boundary for this lane is the directory: every Tickoni-owned test root that
is not under `src/tickoni/test/integration/` or `src/tickoni/test/system/` runs
here. In practice that means the runtime, C ABI, and tile modules' own inline
`test` blocks, all schema modules under `src/tickoni/schema/`, the supervisor
binary, and everything under `src/tickoni/test/fixtures/` and
`src/tickoni/test/mocks/` — fixture-contract tests and mock self-tests run
here, even where they substitute an external system, because that substitution
happens outside `src/tickoni/test/integration/`.

The current Zig test graph is defined in [build.zig](../../build.zig); consult
it for the exact current set of test roots rather than treating any list here
as authoritative.

## Engine Unit Tests

`just test-unit-fd` delegates to platform-qualified recipes. The FD unit-test
lane uses a two-tier recipe pattern:

| Recipe tier | Purpose |
|-------------|---------|
| `build-test-unit-fd-{platform}` | Builds test executables only (via `make unit-test`). Does **not** rebuild Firedancer libraries. |
| `test-unit-fd-{platform}` | Builds test executables, then runs them (via `contrib/test/run_unit_tests.sh`). |

Platform-qualified commands:

- `just test-unit-fd-linux-x86-gcc`
- `just test-unit-fd-linux-x86-clang`
- `just test-unit-fd-linux-arm-gcc`
- `just test-unit-fd-macos-x86`
- `just test-unit-fd-macos-arm`
- `just test-unit-fd-windows-x86`
- `just test-unit-fd-windows-arm`

On Linux, the build recipe computes resource-safe test options via
`dynamic_test_opts.py` (memory-driven `TEST_OPTS` and `LDFLAGS_EXE`), raises
memlock limits, and allocates gigantic pages when possible. It then runs
`make unit-test` with the appropriate compiler (`gcc-12`, `clang-18`, or
`gcc-14`) and the `tickoni_fd` machine profile. The run recipe invokes
`contrib/test/run_unit_tests.sh` with `--page-sz normal` fallback when needed.

On macOS and Windows, the build recipe runs `make unit-test` with the default
compiler and the run recipe uses `--page-sz normal --page-cnt 131072`.

All Firedancer builds use the `tickoni_fd` machine profile, which scopes the
build to only the 5 libraries Tickoni reuses (`fd_tango`, `fd_util`,
`fd_ballet`, `fd_disco`, `fd_waltz`). This excludes Solana validator tiles,
RPC schemas, and unrelated Firedancer source.

For local development without pre-built libraries,
use `just test-unit-fd-{platform}` to build + run in one step, or
`just build-fd-{platform}` first then `just test-unit-fd-{platform}`.

The bare dispatcher `just test-unit-fd` routes to the host platform's GCC recipe.

This is the preferred repo-facing Firedancer unit-test command. Do not invoke
raw compiler commands for Firedancer tests.

## Qt Test

`just test-qt` builds the Qt terminal CMake project and runs the resulting binary
to verify it launches without crash or QML error. On Linux x86 the command is

```bash
cmake -S src/tickoni/terminal -B build/qt --fresh -DCMAKE_BUILD_TYPE=Release && \
cmake --build build/qt --parallel $(nproc) && \
./build/qt/tickoni-terminal --platform offscreen
```

On non-Linux platforms, `just test-qt` delegates to the platform-specific recipe
(e.g. `test-qt-macos-x86`). The Qt test does not require llama.cpp, live tiles,
or the Firedancer/Zig build — it only needs `cmake`, a C++17 compiler, and Qt 6
with the Quick component installed.

The boundary for this lane is the directory: every file under
`src/tickoni/terminal/` (`CMakeLists.txt`, `app/main.cpp`,
`qml/Tickoni/Main.qml`) runs here. Qt tests are build-and-smoke — there are no
unit tests for Qt terminal code yet. The primary verification is compilation
success and a clean launch with `--platform offscreen`.

Qt quality checks (clang-format and lint) run in the quality gate
`_ci-quality.yml` and are documented in [Qt Quality](./ci.md#qt-quality).
Qt security (sanitizer check) runs in the deep security stage
`_ci-security-deep.yml` with `check: sanitize-qt` and is documented in
[Qt Security](./ci.md#qt-security).

## Engine E2E

`just test-e2e-fd` is currently a no-op placeholder (`@true`). CI exercises
Firedancer's `integration-test` target directly through the build stage rather
than this local recipe.

## Integration Layer

`just test-integration-fd` is a placeholder (`@true`). Firedancer does not have
a separate repo-facing intermediate integration layer between tile/unit tests
and full-topology `integration-test` binaries.

`just test-integration-tk` runs the Zig integration lane. On macOS and Windows,
platform-specific recipes exist (`test-integration-tk-macos-x86`, etc.);
Firedancer library dependencies are expected to be built separately
(`just build-fd-{platform}`) or available via pre-built CI artifacts.

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

`just test-system-tk` runs `python contrib/test/orchestrator.py system-test`,
which executes the full end-to-end flow: start llama.cpp server, run
`zig build system-test`, and clean up (server shutdown).

Test infrastructure is managed by
`contrib/test/orchestrator.py`:

```bash
python3 contrib/test/orchestrator.py llm-server-start   # start server, wait for health
python3 contrib/test/orchestrator.py llm-server-stop    # kill server by PID
python3 contrib/test/orchestrator.py system-test        # full lifecycle: start → zig-test → stop
```

To override default paths:

```bash
export TK_LLAMA_CPP_DIR=~/custom/llama.cpp
export TK_HF_MODEL_DIR=~/custom/models
export TK_HF_MODEL_FILE=my-model.gguf
```

On Windows, `just test-system-tk` delegates to
`just test-system-tk-windows-x86` or `just test-system-tk-windows-arm`, which
build FD libs for the target platform and then call
`contrib/test/orchestrator.py system-test` (full e2e flow, CPU-only).

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
- `just quality-yaml-check-all` runs `yamllint` with a relaxed profile
  across the entire repository (all `.yaml`/`.yml` files). The config is in
  `.yamllint`. It excludes `opt/`, `node_modules/`, `.zig-global-cache/`,
  `build/`, `target/`, and `zig-out/`. Initially scoped to `.github/`, it was
  later expanded to the full repo.
- `just quality-spell-check-all` runs `cspell lint --no-progress` across
  the repository. The domain dictionary and ignored paths are configured in
  `.cspell.json`. It checks markdown, yaml, bash, python, and json files while
  excluding compiled/source trees under `src/`, `config/`, `.github/`, and
  build artefact directories.
- `just quality-check-all` runs the main repository quality bundle:
  format-check all lanes, lint-check all lanes, proto-check, yaml-check,
  and spell-check.
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
  engine, CodeQL, gitleaks, seccomp, proof, and sanitizer checks.
- `just test-unit-tk` runs Tickoni Zig harness unit tests.
- `just test-unit-fd` runs Firedancer-derived C unit tests through the
  repository wrapper that manages huge-page setup and normal-page fallback.
- `just test-unit-all` runs all unit lanes (TK, CLI, infra, FD).
- `just test-integration-all` runs the integration lanes (integration-tk + CLI integration).
- `just test-e2e-fd` is a no-op placeholder locally (see Engine E2E section).
- `just test-e2e-all` runs e2e placeholders.
- `just test-cov-tk` runs Tickoni harness coverage.
- `just test-cov-fd` runs Firedancer-derived C coverage (no-op locally; requires
  LLVM toolchain not installed on host).
- `just test-cov-all` runs both coverage lanes.
- `just test-all` runs the broad test bundle: unit, integration, coverage, system, e2e.
- `just tests-all` runs the full local handoff gate (aggregator-of-aggregators):
  quality, build, tests, and security.

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
