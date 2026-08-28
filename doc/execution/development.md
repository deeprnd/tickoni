# Development

This document covers local setup, repo-facing commands, and the main Tickoni
development workflow.

All developer tooling entrypoints live in the `justfile`. Do not add Tickoni
developer tooling targets to `config/everything.mk` or upstream Firedancer
Makefiles.

## Prerequisites

Core requirements:

- Linux on x86-64 for Firedancer-derived runtime work
- Windows 10 2004+ (x86_64) or Windows 11 (ARM64) for retail tier builds
- `just` (install manually — it is the sole documented manual prerequisite)
- Python 3
- clang or MSVC for Windows builds (MinGW-w64 for MSYS2)

Install platform-specific tooling with one command:

```bash
just setup-env
```

This installs Zig, the system compiler (GCC on Linux, clang on macOS, LLVM on Windows), make, gitleaks, shellcheck, pre-commit, buf, and Firedancer system dependencies. After `just setup-env` the rest of the `justfile` works without any further configuration.

Useful local tools for full gates:

- `codeql`
- Clang for sanitizer builds
- CBMC/proof tooling used by Firedancer proof checks

Firedancer only supports x86-64 Linux. Other targets are not valid for the
Firedancer runtime because the code relies on x86-64 memory-ordering
assumptions.

### Windows Build Notes

The Tickoni-owned Zig runtime builds on Windows with the following conventions:

- Target: `--target x86_64-pc-windows-msvc` (MSVC) or
  `--target x86_64-pc-windows-gnu` (MinGW-w64)
- CRT compat header: `src/tickoni/util/fd_windows_compat.h` provides
  `stricmp`, `strnicmp`, `strdup`, `snprintf`, `vsnprintf` shim functions
  for MSVC environments
- Build scope: Windows retail mode excludes Firedancer shared-memory tiles,
  seccomp tiles, and the full tile runtime — only portable Firedancer
  substrate is linked
- CI: Windows lanes run on `windows-2025` and `windows-11-arm` runners;
  demo conformance verifies deterministic fixture outputs match Linux

CI expectations:

- `zig build check` runs on Windows with MSVC and MinGW-w64 toolchains
- Demo conformance output is compared cross-platform against Linux reference
- No large-page or huge-page infrastructure on Windows — retail tier does not
  attempt shared-memory topology

## Install

Install common Python tooling used by repo maintenance, codegen, and tests:

```bash
just python-dev-install
```

Install the wider optional Python surface:

```bash
just python-dev-install-all
```

The wider install includes optional extras for protobuf generators, math
generators, simulation helpers, Solana helpers, and agave-cluster CLI
dependencies.

Install the repository-managed Git hooks:

```bash
git config core.hooksPath .githooks
chmod +x .githooks/commit-msg
```

This configures `core.hooksPath` to `.githooks` so the tracked `commit-msg`
hook silently strips `Co-Authored-By` trailers containing
`noreply@anthropic.com` (e.g. Claude Sonnet 5, Claude Opus, etc.) before a
commit is created. Human co-authors and non-anthropic AI trailers are left
unchanged.

## Build

Tickoni-owned Zig supervisor:

```bash
just build-tk
```

Firedancer C binary:

```bash
just build-fd
```

Firedancer dev validator:

```bash
just build-fd-dev
```

Combined default build:

```bash
just build-all
```

`build-all` badge-wraps `just build-tk && just build-fd` through
`contrib/tool/readme/run-badged-command.py`.

## Run

Print the Phase 0 Tickoni topology:

```bash
zig build run -- status
```

Run the Phase 0 payment pipeline spike:

```bash
zig build run -- start
```

The supervisor currently supports only:

- `start`
- `status`

## DevOps And Runtime Notes

Active Tickoni runtime:

- The active Tickoni workspace is `src/app/tickoni/` and `src/tickoni/`.
- `tickoni-supervisor` is the active Zig supervisor runtime for current
  Tickoni-owned work.
- Current local runtime entrypoints are `zig build run -- status` and
  `zig build run -- start`.
- There is no active Tickoni Docker Compose runtime in this repository. The
  checked-in container files under `contrib/containers/` are development or
  packaging support, not the source of truth for local orchestration.

Repository command policy:

- Use `justfile` recipes as the repo-facing command surface.
- Do not add Tickoni developer tooling targets to upstream Firedancer
  Makefiles.
- Keep GitHub Actions commands aligned with the active `justfile` recipes.
- Avoid running broad aggregate recipes by default. Prefer the narrowest direct
  validation needed for the change, such as `just test-unit-tk` or
  `zig build test`, and leave `just test-all`, `just tests-all`,
  `just quality-check-all`, and `just security-check-all` to the developer
  unless they explicitly ask for full gates.

### CLI Tooling Guidance

- For new or refactored repository CLI tools, keep the public command surface
  in the `justfile` unless the tool is an actual runtime binary such as
  `tickoni-supervisor`.
- For Tickoni runtime commands, prefer explicit Zig CLI handling in
  `src/app/tickoni/` with clear `--help` or usage output and fail-closed input
  validation.
- Keep CLI command names explicit about intent and aligned with existing
  `justfile` recipes, especially the `build-*`, `test-*`, `quality-*`, and
  `security-*` naming families.
- Extend existing `justfile` recipe conventions instead of introducing
  parallel naming patterns. If renaming a recipe, preserve a compatibility
  alias when practical.
- Keep shell scripts scoped to one explicit operation or selector. Compose
  multi-step workflows in named `justfile` recipes so the command surface
  remains visible, overridable, and easy to audit.
- Do not hide broad aggregate operations behind a single shell-script selector
  such as `all` when the repository can express the sequence through named
  `justfile` recipes.
- Use concise human-facing terminal output, while keeping structured diagnostic
  output machine-parseable where tools or CI need to consume it.
- Validate required CLI inputs and environment preconditions up front, then
  fail fast with clear actionable error messages.

Configuration and runtime environment:

- Tickoni does not currently have a checked-in runtime `.env.example` template.
- If a new required runtime environment variable is added, production code must
  fail closed when it is missing or malformed.
- When adding a required runtime environment variable, update all of the
  following in the same change when they exist:
  - the owning Zig config or startup code,
  - the relevant `.env.example` template,
  - checked-in local `.env.*` files used for repo-local runtime or E2E flows,
  - affected READMEs and docs,
  - affected GitHub Actions workflow or action environment,
  - affected test harness config layers.

CI and retained Firedancer workflows:

CI automation lives in GitHub Actions under `.github/workflows`. Tickoni-owned
workflows target the active Zig harness and `justfile` recipes. Upstream
Firedancer workflows are retained but skipped via `vars.SKIP_FIREDANCER_CI`.
See [CI](./ci.md) for workflow details and contributor constraints.

Infrastructure safety:

- Repository-managed infrastructure should be treated as high-risk.
- Do not add new cloud mutation flows without explicit user guidance.
- Any script or `just` recipe that can create, update, replace, delete,
  destroy, or otherwise mutate cloud resources must default to dry-run
  behavior.
- Use the reverse opt-in flag `IS_NOT_DRY_RUN=true` for infrastructure changes
  that actually mutate remote resources. Leaving the flag unset, empty, or set
  to any other value must remain dry run.
- When practical, provide separate dry-run and commit command paths, and make
  the committing path visibly set `IS_NOT_DRY_RUN=true`.

Useful current commands:

- `just build-tk` builds the Tickoni Zig supervisor.
- `just build-fd` builds the Firedancer C binary.
- `just test-unit-tk` runs Tickoni Zig unit tests.
- `just quality-format-check-tk` checks Tickoni Zig formatting.
- `just quality-format-fix-tk` formats Tickoni Zig source.
- `just quality-lint-check-tk` runs Tickoni-owned lint checks.
- `just security-gitleaks-check-tk` scans Tickoni-owned source for secrets.
- `just security-sanitize-check-tk` runs the Tickoni sanitizer check path.

## Test

Main test entrypoints:

- `just test-unit-tk`
- `just test-unit-fd`
- `just test-unit-all`
- `just test-integration-all`
- `just test-e2e-all`
- `just test-all`
- `just tests-all`

For the detailed test command matrix, see
[Tickoni Testing](../execution/testing-tickoni.md). The existing
[Testing Tickoni](../testing.md) page remains the Firedancer-style testing guide
and has not been merged with the justfile-oriented guide.

## Quality

Formatting:

- `just quality-format-check-fd`
- `just quality-format-fix-fd`
- `just quality-format-check-tk`
- `just quality-format-fix-tk`
- `just quality-format-check-all`
- `just quality-format-fix-all`

Lint:

- `just quality-lint-check-fd`
- `just quality-lint-check-tk`
- `just quality-lint-check-all`

Aggregate:

- `just quality-check-all`

The Firedancer-side quality script scopes checks to changed, tracked, cached,
and untracked files outside `src/app/tickoni` and `src/tickoni`. The Tickoni
format path runs `zig fmt` on the Zig-owned source trees.

## Security

Security entrypoints:

- `just security-gitleaks-check-all`
- `just security-codeql-check-all`
- `just security-seccomp-check-all`
- `just security-proof-check-all`
- `just security-sanitize-check-all`
- `just security-check-all`

For scanner details and current no-op recipes, see [Security](./security.md).

## Memory And Huge Pages

Firedancer-side unit tests prefer gigantic pages. The helper recipes are:

- `just mem-init`
- `just mem-query`
- `just mem-reset`
- `just mem-fini`
- `just mem-alloc`
- `just mem-alloc-auto`
- `just mem-free`

`just test-unit-fd` also attempts to free previous gigantic pages, allocate an
automatic amount based on system RAM, raise the current shell's memlock limit,
and fall back to `TEST_OPTS="--page-sz normal"` when gigantic pages are not
available.

## Project Layout

Tickoni-owned areas:

- `build.zig`: Zig build graph
- `justfile`: repo-facing developer commands
- `src/app/tickoni/`: supervisor CLI and startup
- `src/tickoni/runtime/`: topology and tile runtime abstractions
- `src/tickoni/tiles/`: Phase 0 payment pipeline tile logic
- `src/tickoni/c_abi/`: narrow C ABI declarations for selected runtime primitives
- `src/tickoni/codec/`: Tickoni-owned codec bindings and C codec implementations
- `src/tickoni/test/demo/`: deterministic CLI/test demo orchestration
- `doc/knowledge`: Tickoni architecture
- `doc/execution`: Build, security, testing, and observability
- `doc/strategy`: Product and roadmap docs

Firedancer-derived areas (compiled via `tickoni_fd` scope):

- `src/disco/`: metrics, diagnostics, verification, event handling
- `src/tango/`, `src/util/`, `src/ballet/`, `src/waltz/`: runtime substrate

Avoid Frankendancer-specific paths such as `fdctl`, `fddev`, and `discoh`
unless a task explicitly requires shared legacy behavior.

## Generated Code

After changing `src/disco/metrics/metrics.xml`, run:

```bash
make -C src/disco/metrics metrics
```

After changing `src/flamenco/features/feature_map.json`, run:

```bash
cd src/flamenco/features && make generate
```

After changing protosol proto definitions, run:

```bash
make -C src/flamenco/runtime/tests protobufs
```

Generated outputs are checked into the repository.

## Related Docs

- [Build](./build.md)
- [Build System](../build-system.md)
- [Architecture](../knowledge/architecture.md)
- [CI](./ci.md)
- [Security](./security.md)
- [Observability](./observability.md)
