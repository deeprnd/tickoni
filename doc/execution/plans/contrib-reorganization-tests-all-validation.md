# Contrib Reorganization: `tests-all` Validation Plan

## Scope

Validate the current `story/just-distpatcher` working tree after consolidating
repository tooling under `contrib/` subdirectories. This plan intentionally
runs the constituents of `just tests-all` separately rather than invoking the
aggregate recipe first, so a path or command regression is isolated quickly.

The repository's canonical documentation root is `doc/`, so this plan is saved
under `doc/execution/plans/`.

## `tests-all` constituent checklist

The checklist below is the expanded form of the current `tests-all` recipe.
Each row is an independently checkable run. Mark a row `[x]` only after that
exact command succeeds (or after the stated intentional no-op is recorded).
When resuming this plan, run only unchecked rows. Do not rerun checked rows
unless the relevant source, generated output, environment, or recipe changed.

### Top-level constituents

- [ ] `just build-fd` — expanded from `build-all`
- [ ] `just build-tk` — expanded from `build-all`
- [ ] `just quality-format-check-fd` — expanded from `quality-format-check-all`
- [ ] `just quality-format-check-tk` — expanded from `quality-format-check-all`
- [ ] `just quality-lint-check-tk`
- [ ] `just quality-proto-check-fd` — expanded from `quality-proto-check-all`
- [ ] `just quality-proto-check-tk` — expanded from `quality-proto-check-all`
- [ ] `true` — intentional no-op for the known host-clang IBT linker failure;
  record it, but do not treat it as a security check
- [ ] `just security-engine-check-changes`

### Test constituents

`just test-all` expands into the following five independently resumable
groups. The group rows are headings, not additional commands to rerun.

#### Unit (`test-unit-all`)

- [ ] `just test-unit-tk`
- [ ] `just test-unit-fd`

#### Integration (`test-integration-all`)

- [ ] `just test-integration-fd` — intentional no-op; record it
- [ ] `just test-integration-tk`

#### Coverage (`test-cov-all`)

- [ ] `just test-cov-fd` — intentional no-op because the llvm-cov toolchain is
  not installed on this host; record it
- [ ] `just test-cov-tk`

#### System (`test-system-all`)

- [ ] `just test-system-tk` — requires the local llama.cpp/model prerequisites
- [ ] `just test-system-fd` — intentional no-op; record it

#### End-to-end (`test-e2e-all`)

- [ ] `just test-e2e-fd`
- [ ] `just test-e2e-tk` — intentional no-op; record it

## Execution order

Run each command from the repository root, one at a time, stopping at the
first failure. Record exit status and the relevant output for every step.

### 0. Preflight: verify dispatcher and moved paths

**DONE** — `just --dump`, platform detection, moved-path checks, and the
active-path grep passed after updating the workflow path filters in
`.github/workflows/build-fd.yml`, `.github/workflows/build-tk.yml`,
`.github/workflows/tests-long.yml`, and `.github/workflows/tests-short.yml`.
The host reported `linux`, `x86`, and `linux-x86`.

```bash
just --dump >/tmp/tickoni-just-dump.txt
bash contrib/platform.sh os
bash contrib/platform.sh arch
bash contrib/platform.sh platform
```

Validate that the current host reports a supported platform and that every
moved entry point used by the recipes exists:

```bash
for path in \
  contrib/platform.sh \
  contrib/build/fd-build-lib.sh \
  contrib/build/fd-build-windows.sh \
  contrib/build/fd-tk-libs.sh \
  contrib/build/fd-write-zig-link-manifests.sh \
  contrib/build/GNUmakefile \
  contrib/build/zigw.sh \
  contrib/quality/quality.sh \
  contrib/quality/engine/engine_check_changes.py \
  contrib/quality/engine/linter.py \
  contrib/security/security.sh \
  contrib/test/coverage.sh \
  contrib/test/run_cli_demo_tests.sh \
  contrib/tool/readme/run-badged-command.py; do
  test -f "$path" || { printf 'missing: %s\n' "$path" >&2; exit 1; }
done
```

Search for stale flat-layout references, excluding historical proposal text
only when it is explicitly documenting the old layout:

```bash
git grep -n -E 'contrib/(fd-build-lib|fd-build-windows|fd-tk-libs|fd-write-zig-link-manifests|zigw|ci-run-build-tk|make-j|quality\.sh|security\.sh|coverage_report\.py|refresh-badges\.py|run-badged-command\.py)([^/]|$)' -- \
  ':!doc/strategy/roadmap/proposals/build-tooling-consolidation.md' \
  ':!doc/execution/plans/contrib-reorganization-tests-all-validation.md'
```

Expected result: no active caller uses the old flat path. Any match must be
corrected before continuing or documented as historical. The initial review of
this branch already found active stale path-filter references in:

- `.github/workflows/build-fd.yml`
- `.github/workflows/build-tk.yml`

Those workflow filters still name the former flat `contrib/` paths and must be
included in the reorganization follow-up before claiming repository-wide path
validation is clean. Historical documentation matches may remain when they
clearly describe the former layout.

### 1. Build constituents

Run and record each unchecked command separately; do not run `just build-all`.

```bash
just build-fd
```

```bash
just build-tk
```

Validate the expected build outputs before moving on:

```bash
test -d build/fd-tickoni-fd/lib
test -x zig-out/bin/tickoni-supervisor
```

### 2. Quality constituents

Run and record each unchecked command separately; do not run a quality
aggregate recipe.

```bash
just quality-format-check-fd
```

```bash
just quality-format-check-tk
```

```bash
just quality-lint-check-tk
```

```bash
just quality-proto-check-fd
```

```bash
just quality-proto-check-tk
```

The proto FD check may skip `buf` when it is not installed, but it must still
fail if generated files are dirty or stale. Record such a tool absence
explicitly rather than treating it as a path-validation result.

### 3. Security constituents included by `tests-all`

Record the deliberate no-op, then run the exact active security check. Do not
run `just security-check-all`.

```bash
true # security-check-all: pre-existing IBT linker failure on host clang
```

```bash
just security-engine-check-changes
```

### 4. Test constituents

Run and record each unchecked leaf command. Do not run `test-all` or any of its
five aggregate children; those aggregate recipes are expanded in the checklist
above.

#### 4.1 Unit constituents

```bash
just test-unit-tk
```

```bash
just test-unit-fd
```

#### 4.2 Integration constituents

```bash
just test-integration-fd # intentional no-op
```

```bash
just test-integration-tk
```

#### 4.3 Coverage constituents

```bash
just test-cov-fd # intentional no-op: llvm-cov toolchain is not installed
```

```bash
just test-cov-tk
```

#### 4.4 System constituents

```bash
just test-system-tk
```

If the local llama.cpp/model prerequisites are absent, record an environment
blocker rather than marking this command as passed.

```bash
just test-system-fd # intentional no-op
```

#### 4.5 End-to-end constituents

```bash
just test-e2e-fd
```

```bash
just test-e2e-tk # intentional no-op
```

### 5. Final aggregate confirmation

Only after every constituent checkbox above is checked, run the requested
aggregate once. Add a result next to the checkbox; do not rerun it while
resuming this plan unless a constituent or aggregate recipe changes.

```bash
just tests-all
```

- [ ] `just tests-all` — final aggregate confirmation only

This is a confirmation that the aggregate wiring still matches the individually
validated commands, not the primary diagnostic run.

## Acceptance criteria

- `just --dump` succeeds and contains all required recipes.
- Platform detection succeeds on the current host.
- No active `justfile`, workflow, action, build, quality, security, or test
  caller references the pre-reorganization flat paths.
- The stale workflow path filters identified in the preflight section are
  corrected or explicitly excluded from the reorganization scope with a
  documented reason.
- Both build constituents pass and produce the expected artifacts.
- Every active quality and security constituent passes, with intentional no-ops
  and missing optional tools recorded separately.
- Every test constituent passes, or any failure is classified with its exact
  command and root cause.
- The final `just tests-all` exits successfully.
- No source, generated, or unrelated working-tree changes are created by the
  validation run beyond expected build artifacts under ignored directories.

## Evidence to retain

Record:

- branch and dirty-file status before and after validation;
- host platform/architecture output;
- exit status for each command;
- first failing command and complete relevant log if a lane fails;
- final `just tests-all` result;
- `git status --short` after validation to confirm no unintended tracked edits.
