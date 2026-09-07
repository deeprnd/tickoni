# Story 8.3.3 — Test `just setup-env` and `just tests-all` from all sides

## Goal

Build a comprehensive test plan for `just setup-env` and `just tests-all` that covers
all constituent parts, all execution paths, and all failure modes. Everything runs locally.
No CI. No remote calls except the tools those commands themselves make.

DONT RUN ANYTHING IN PARALLEL!!!!

---

## What these commands do

### `just setup-env`

```
SKIP_IDEMPOTENCY=... python3 ../contrib/setup/orchestrator.py dev
just setup-git
```

Orchestrator.py reads `tool-versions.json`, resolves dependencies for the `dev` category
(which encompasses all tool categories), filters by platform (linux-x86 on this host), and
installs each tool using its registered strategy. Then setup-git configures git hooks.

The `dev` category is a single umbrella that pulls in all tool categories. The orchestrator
resolves the full dependency graph automatically — no need to enumerate individual categories.

**Dependency resolution chain:**

```
dev → [core, essential, toolchain, build, zig, ssl, fd, quality, secrets, coverage, security, ops, qt, mvsc, llm-server]
core → []
```

**Tools installed per category:**

| Category | Tools | Install Method |
|----------|-------|----------------|
| core | curl, git | apt |
| essential | python3, pipx, minisign | apt / pip |
| toolchain | gcc, clang-llvm, llvm | apt |
| build | make, cmake, zstd, pkg-config, ninja, ccache | apt |
| zig | zig | install_zig (github_release) |
| ssl | openssl | build_from_source (compiles from tarball) |
| fd | snappy, rockdb | build_from_source (firedancer_deps script) |
| quality | shellcheck, actionlint, yamllint, pre-commit, buf | apt / pip / pipx / go_install |
| secrets | gitleaks | github_release |
| coverage | kcov | apt |
| security | cbmc, litani, universal-ctags, cbmc-viewer, cbmc-starter-kit | apt / github_release |
| ops | pwsh | apt |
| qt | qt6 | orchestrator qt strategy |
| mvsc | msbuild, windows-sdk | windows-specific |
| llm-server | llama.cpp, GGUF model | orchestrator llm-server strategy |

### `just tests-all`

```
just build-all              # build fd libs + tk zig binary
just quality-check-all      # format + lint + proto + yaml + spell check
just security-check-all     # engine + codeql + gitleaks + seccomp + proof + sanitize
just security-engine-check-changes  # gitleaks diff scan (redundant, run by security-check-all)
just test-all
```

**test-all chain:**

```
test-all → test-unit-all + test-integration-all + test-cov-all + test-system-all + test-e2e-all

test-unit-all → test-unit-setup && test-unit-tk && test-unit-fd
  test-unit-setup → pip install pip/pytest + pytest contrib/test/ (Linux unit tests)
  test-unit-tk → dispatch → zig build test + run-tests
  test-unit-fd → dispatch → build-fd + make run-unit-test

test-integration-all → test-integration-fd && test-integration-tk
  test-integration-fd → @true (placeholder)
  test-integration-tk → dispatch → zig build integration-test

test-cov-all → test-cov-fd && test-cov-tk
  test-cov-fd → @true (pre-existing llvm-cov toolchain not installed)
  test-cov-tk → coverage.sh coverage-tk

test-system-all → test-system-tk && test-system-fd
  test-system-tk → run_live_investment_demo.sh (requires llama.cpp + model)
  test-system-fd → @true (placeholder)

test-e2e-all → test-e2e-fd && test-e2e-tk
  test-e2e-fd → @true (placeholder)
  test-e2e-tk → @true (placeholder)

test-unit-setup → pip install pip pytest + pytest contrib/test/*.py
```

---

## Test Plan

### Phase 1: Setup-env — Clean run verification

**Status: NOT TESTED**

**1.1. Clean machine setup — TODO**

**1.2. Idempotent re-run — TODO**

**1.3. Dry-run — TODO**

**1.4. dev category — TODO**

**1.5. Dependency graph — TODO**

**1.6. Platform override — TODO**

**1.7. Setup-git — TODO**

---

**1.1. Clean machine setup (fresh virtualenv + no pre-installed tools)**

```bash
# Create fresh env
python3 -m venv /tmp/test-setup-env-venv
source /tmp/test-setup-env-venv/bin/activate

# Run setup-env
cd /home/vicgenin/work/git/tickoni
just setup-env
```

Verify:
- Orchestrator logs `[INSTALL] <tool>` or `[COMPLETE] N/N tools handled` for `dev`
- No `already_installed` for tools that should be fresh
- `just setup-git` succeeds and `.githooks/commit-msg` is active
- All tools are discoverable: `command -v curl git python3 pipx minisign gcc clang cmake make zig gitleaks kcov pwsh buf shellcheck actionlint yamllint cbmc litani`

**1.2. Idempotent re-run (tools already installed)**

```bash
just setup-env
```

Verify:
- All tools show `already_installed` status
- Exit code is 0
- No rebuilds or re-downloads
- `setup-git` still succeeds

**1.3. Dry-run verification**

```bash
python3 contrib/setup/orchestrator.py dev --dry-run
```

Verify:
- Output lists all expected tools with `[DRY-RUN] Would install <tool> via <method>`
- Dependency resolution shows `dev` resolves to the full category list
- No actual installation happens (check that openssl tarball isn't downloaded, etc.)

**1.4. dev category run**

```bash
python3 contrib/setup/orchestrator.py dev
```

Verify:
- All tool categories are processed in dependency order
- Each category's tools are installed via their registered strategy
- The orchestrator resolves `dev` to all 11+ categories automatically

**1.5. Dependency graph verification**

```bash
python3 contrib/setup/orchestrator.py --deps dev
```

Verify:
- `--deps dev` returns the full list: `core, essential, toolchain, build, zig, ssl, fd, quality, secrets, coverage, security, ops`
- The resolved order is topological (core first, toolchain before coverage, etc.)

**1.6. Platform override test**

```bash
python3 contrib/setup/orchestrator.py dev --dry-run --platform macos-arm
python3 contrib/setup/orchestrator.py dev --dry-run --platform windows-x86
```

Verify:
- Platform filtering excludes linux-only tools (e.g., gcc via apt)
- Windows-specific tools (msvc, ninja via winget) appear for windows platforms
- macOS-specific tools (brew-based installs) appear for macos platforms

**1.7. Setup-git verification**

```bash
git config --get core.hooksPath
test -x .githooks/commit-msg
grep -q 'anthropic' .githooks/commit-msg
```

Verify:
- `core.hooksPath` is set to `.githooks`
- `.githooks/commit-msg` is executable
- It contains logic to strip anthropic AI co-authors

---

### Phase 2: Setup-env — Build-time verification

**Status: NOT TESTED**

**2.1. OpenSSL — TODO**

**2.2. Firedancer deps — TODO**

**2.3. Zig install — TODO**

**2.4. CBMC tools — TODO**

---

**2.1. OpenSSL build from source (critical path)**

This is the most complex install — it downloads, extracts, configures, and compiles OpenSSL.

```bash
# Force re-install by removing existing install
rm -rf ./opt/lib/libssl.a ./opt/lib/libssl.so* ./opt/include/openssl

# Run ssl category (via dev, or directly)
python3 contrib/setup/orchestrator.py dev
```

Verify:
- Tarball is downloaded to the correct location
- `./opt/lib/libssl.a` and `./opt/lib/libcrypto.a` exist after install
- `./opt/include/openssl/ssl.h` exists
- `pkg-config --libs openssl` works if `--cflags`/`--libs` were set

**2.2. Firedancer deps build (snappy + rockdb)**

```bash
python3 contrib/setup/orchestrator.py fd --dry-run
python3 contrib/setup/orchestrator.py fd
```

Verify:
- `./opt/lib/libsnappy.a` exists after install
- `./opt/lib/librocksdb.a` exists after install
- Both use the `firedancer_deps` build_from_source strategy
- The build script handles dependencies correctly

**2.3. Zig install (install_zig strategy)**

```bash
python3 contrib/setup/orchestrator.py zig --dry-run
python3 contrib/setup/orchestrator.py zig
```

Verify:
- Zig binary is installed to `$HOME/.local/bin/zig` or equivalent
- `zig version` returns the expected version from tool-versions.json
- GITHUB_PATH is written for PATH propagation

**2.4. CBMC and formal verification tools (security category)**

```bash
python3 contrib/setup/orchestrator.py security --dry-run
```

Verify:
- All 5 tools (cbmc, litani, universal-ctags, cbmc-viewer, cbmc-starter-kit) are listed
- Mix of apt and github_release methods is handled correctly

---

### Phase 3: Build-all — Verification

**Status: NOT TESTED**

**3.1. Firedancer build — TODO**

**3.2. Tickoni Zig build — TODO**

**3.3. build-all aggregate — TODO**

**3.4. Platform/compiler dispatch — TODO**

---

**3.1. Firedancer library build (dispatcher)**

```bash
python3 ../../scripts/dispatch build-fd
```

Or explicitly for the current platform:

```bash
just build-fd  # routes to build-fd-linux-x86-gcc on linux-x86
```

Verify:
- Build uses `fd-tickoni-fd` machine profile (scoped to 5 libs only)
- Output libraries: `libfd_tango.a`, `libfd_util.a`, `libfd_ballet.a`, `libfd_disco.a`, `libfd_waltz.a`
- Build completes without errors
- No Solana validator tiles or RPC schemas are compiled

**3.2. Tickoni Zig build**

```bash
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dfd-lib-dir=build/fd-tickoni-fd/lib
```

Or via dispatcher:

```bash
just build-tk  # routes to build-tk-linux-x86 on linux-x86
```

Verify:
- Binary is produced (should be `tickoni` or `tickoni-supervisor`)
- Linking against the previously built Firedancer libs works
- No undefined symbols from the Firedancer side

**3.3. build-all aggregate**

```bash
just build-all
```

Verify:
- Both `build-fd` and `build-tk` succeed
- Order is correct (fd libs first, then tk binary)
- Exit code is 0
- Badge-wrapping command runs correctly

**3.4. Platform-specific builds (dispatcher)**

```bash
# Linux x86 GCC
just build-fd-linux-x86-gcc
just build-tk-linux-x86

# Linux ARM GCC
just build-fd-linux-arm-gcc
just build-tk-linux-arm

# macOS x86
just build-fd-macos-x86
just build-tk-macos-x86

# macOS ARM
just build-fd-macos-arm
just build-tk-macos-arm

# Windows x86
just build-fd-windows-x86
just build-tk-windows-x86

# Windows ARM
just build-fd-windows-arm
just build-tk-windows-arm
```

Verify:
- Each platform recipe compiles and links correctly
- Windows recipes build fd first then run zig test/run-tests

---

### Phase 4: Quality checks — Verification

**Status: NOT TESTED**

**4.1. Format check tk — TODO**

**4.2. Format check fd — TODO**

**4.3. Full format check — TODO**

**4.4. Lint check — TODO**

**4.5. Proto check — TODO**

**4.6. Lint actions — TODO**

**4.7. Qt format/lint — TODO**

---

**4.1. Format check (Zig source)**

```bash
just quality-format-check-tk
```

Verify:
- Runs `zig fmt --check` on all Tickoni-owned Zig source trees
- Reports cleanly if code is already formatted

**4.2. Format check (Firedancer C / docs / scripts)**

```bash
just quality-format-check-fd
```

Verify:
- Checks trailing whitespace in non-Tickoni paths
- Reports cleanly

**4.3. Full format check**

```bash
just quality-format-check-all
```

Verify:
- Both tk and fd format checks pass
- Qt format check runs if clang-format is available
- Exit code is 0

**4.4. Lint check (Tickoni + FD)**

```bash
just quality-lint-check-tk
just quality-lint-check-fd
```

Verify:
- Runs `zig build lint-check` for Tickoni
- Runs shellcheck for Firedancer shell scripts
- Reports on code quality issues

**4.5. Proto check**

```bash
just quality-proto-check-all
```

Verify:
- Runs `buf lint` and `buf check` on proto files (both fd and tk schemas)
- FD generates events from schema and checks for drift
- Exits 0 when no violations

**4.6. Lint actions (GitHub Actions)**

```bash
just quality-lint-check-actions
```

Verify:
- Runs `actionlint` on workflow YAML files
- Ignores unknown label `windows-11-vs2026-arm`
- Exits 0 when no violations

**4.7. Qt format/lint**

```bash
just quality-format-check-qt
just quality-lint-check-qt
```

Verify:
- Qt format/lint runs if clang-format is available
- Otherwise reports skip message

---

### Phase 5: Security checks — Verification

**Status: NOT TESTED**

**5.1. security-check-all — TODO**

**5.2. security-engine-check-changes — TODO**

**5.3. Gitleaks full scan — TODO**

**5.4. CodeQL check — TODO**

**5.5. Seccomp check — TODO**

**5.6. Proof check — TODO**

**5.7. Sanitize check — TODO**

---

**5.1. security-check-all (expanded security suite)**

```bash
just security-check-all
```

This runs:
1. `security-engine-check-all` (engine check changes + orchestration linter)
2. `security-codeql-check-all` (CodeQL — stubbed on all platforms)
3. `security-gitleaks-check-all` (gitleaks for fd, tk, qt)
4. `security-seccomp-check-all` (seccomp for fd — stubbed on macOS/Windows)
5. `security-proof-check-all` (CBMC proof for fd — stubbed on macOS/Windows)
6. `security-sanitize-check-all` (ASan/UBSan for fd + tk — stubbed on macOS/Windows)

Verify:
- All 6 sub-checks execute in sequence
- Each platform stub returns `@true` where applicable
- gitleaks scans fd, tk, and qt code trees

**5.2. security-engine-check-changes**

```bash
just security-engine-check-changes
```

Verify:
- Runs `engine_check_changes.py` on changed files
- Reports no false positives on clean repo

**5.3. security-engine-check-orchestration**

```bash
just security-engine-check-orchestration
```

Verify:
- Runs linter against `checks/` directory
- Reports errors at `--severity ERROR` level

**5.4. CodeQL check**

```bash
just security-codeql-check-fd
just security-codeql-check-tk
just security-codeql-check-qt
```

Verify:
- All return `@true` (stubbed — CodeQL not configured)
- FD stub references issue #10058

**5.5. Seccomp check**

```bash
just security-seccomp-check-fd
just security-seccomp-check-tk
just security-seccomp-check-qt
```

Verify:
- FD seccomp check runs on Linux: `security.sh seccomp-check-fd`
- macOS/Windows return `@true` (seccomp is Linux-only)
- Qt returns `@true` (not in the financial event path)

**5.6. Proof check**

```bash
just security-proof-check-fd
just security-proof-check-tk
just security-proof-check-qt
```

Verify:
- FD proof check runs: `security.sh proof-check-fd`
- macOS/Windows return `@true` (CBMC/proof is Linux-only)
- Qt returns `@true` (no CBMC verification for Qt)

**5.7. Sanitize check**

```bash
just security-sanitize-check-fd
just security-sanitize-check-tk
just security-sanitize-check-qt
```

Verify:
- FD runs `security.sh sanitize-check-fd`
- TK runs `security.sh sanitize-check-tk`
- Qt runs `security.sh sanitize-check-qt`
- macOS/Windows return `@true` (sanitize checks are Linux-only in CI)

---

### Phase 6: Test lane — Verification

**Status: NOT TESTED**

**6.1. Unit tests FD — TODO**

**6.2. Unit tests FD (gcc) — TODO**

**6.3. Integration tests tk — TODO**

**6.4. Integration tests FD — TODO**

**6.5. System tests tk (live llama.cpp) — TODO**

**6.6. System tests FD — TODO**

**6.7. Demo conformance — TODO**

**6.8. E2E tests FD — TODO**

**6.9. E2E tests tk — TODO**

**6.10. Coverage tk — TODO**

**6.11. Coverage FD — TODO**

**6.12. Unit setup — TODO**

---

**6.1. Unit tests — Tickoni (Zig, via dispatcher)**

```bash
just test-unit-tk
```

This routes to `build-tk-linux-x86` via dispatcher, then runs:
```
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib test --summary all
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib run-tests
```

Verify:
- Dispatcher resolves to correct platform recipe
- All unit tests pass
- Report test count and any failures

**6.2. Unit tests — Firedancer (C, via dispatcher)**

```bash
just test-unit-fd
```

This routes to `test-unit-fd-linux-x86-gcc` via dispatcher, which:
1. Raises memlock limit (2097152 KB)
2. Builds FD with orchestrator
3. Runs `make run-unit-test` under `MACHINE=tickoni_fd`

Verify:
- memlock is raised before allocation
- FD builds with correct toolchain (gcc-12 on Linux)
- All unit tests pass

**6.3. Unit setup (Linux contrib tests)**

```bash
just test-unit-setup
```

Verify:
- Installs pip and pytest
- Runs pytest on `contrib/test/*.py` files
- All Python unit tests pass

**6.4. Integration tests — Tickoni**

```bash
just test-integration-tk
```

Verify:
- Runs `zig build -Dtest=true -Dfd-lib-dir=<path> integration-test`
- Tests tile wiring, replay, audit, decision cards, transport
- Model and adapter backends are substituted with fixtures/mocks
- All integration tests pass

**6.5. Integration tests — Firedancer (placeholder)**

```bash
just test-integration-fd
```

Verify:
- Returns `@true` (documented placeholder)
- FD doesn't have an intermediate integration layer

**6.6. System tests — Tickoni (live llama.cpp)**

```bash
# First ensure LLM infrastructure
python3 contrib/setup/orchestrator.py llm-server

# Then run system tests
just test-system-tk
```

Verify:
- Orchestrator installs llama.cpp, downloads GGUF model
- llama-server starts and health endpoint responds
- Zig system-test binary runs against the live server
- All system tests pass

**6.7. System tests — Firedancer (placeholder)**

```bash
just test-system-fd
```

Verify:
- Returns `@true` (documented placeholder)

**6.8. Demo conformance suite**

```bash
just test-demo-tk
```

Verify:
- `tickoni --version` contract passes
- `tickoni doctor --plain` and `--json` contracts pass
- `tickoni-supervisor demo` without manifest fails closed
- `tickoni-supervisor demo investment` with fixture manifest passes
- Conformance output written to `build/demo-conformance/<platform>/conformance.json`

**6.9. E2E tests — Firedancer**

```bash
just test-e2e-fd
```

Verify:
- Returns `@true` (documented placeholder)
- E2E for FD uses `make integration-test && make run-integration-test` under `MACHINE=tickoni_fd`

**6.10. E2E tests — Tickoni (placeholder)**

```bash
just test-e2e-tk
```

Verify:
- Returns `@true` (documented placeholder)
- E2E is folded into test-demo-tk and test-e2e-fd

**6.11. Coverage — Tickoni**

```bash
just test-cov-tk
```

Verify:
- Runs `coverage.sh coverage-tk`
- Runs coverage collection for Tickoni harness
- Report coverage percentage

**6.12. Coverage — Firedancer (placeholder)**

```bash
just test-cov-fd
```

Verify:
- Returns `@true` (pre-existing llvm-cov toolchain not installed)
- Document what's needed to enable this

---

### Phase 7: Aggregate lanes — Verification

**Status: NOT TESTED**

**7.1. test-unit-all — TODO**

**7.2. test-integration-all — TODO**

**7.3. test-cov-all — TODO**

**7.4. test-system-all — TODO**

**7.5. test-e2e-all — TODO**

**7.6. test-all (full test suite) — TODO**

**7.7. tests-all (full handoff gate) — TODO**

---

**7.1. test-unit-all**

```bash
just test-unit-all
```

Verify:
- Runs `test-unit-setup && test-unit-tk && test-unit-fd` via badge-wrapping
- Python contrib tests pass first
- Then Tickoni unit tests (zig build test + run-tests)
- Then Firedancer unit tests (make run-unit-test)
- All lanes pass

**7.2. test-integration-all**

```bash
just test-integration-all
```

Verify:
- Runs `test-integration-fd && test-integration-tk`
- Placeholder + real test

**7.3. test-cov-all**

```bash
just test-cov-all
```

Verify:
- Runs `test-cov-fd && test-cov-tk`
- Placeholder + real coverage

**7.4. test-system-all**

```bash
just test-system-all
```

Verify:
- Runs `test-system-tk && test-system-fd`
- Requires LLM infrastructure (llama.cpp + model)
- Real system test + placeholder

**7.5. test-e2e-all**

```bash
just test-e2e-all
```

Verify:
- Runs `test-e2e-fd && test-e2e-tk`
- Both are currently `@true` placeholders

**7.6. test-all (full test suite)**

```bash
just test-all
```

Verify:
- Unit → Integration → Coverage → System → E2E, all in sequence
- Every lane reports pass/fail
- Exit code is 0 if all pass

**7.7. tests-all (full handoff gate)**

```bash
just tests-all
```

Verify:
- Build → Quality → Security → Engine → Tests, all in sequence
- Quality phase: format + lint + proto + yaml + spell
- Security phase: engine + codeql + gitleaks + seccomp + proof + sanitize
- Every phase reports pass/fail
- Exit code is 0 if all pass

---

### Phase 8: Cross-cutting — Verification

**Status: NOT TESTED**

**8.1. Clean-room full run — TODO**

**8.2. Partial setup + full test — TODO**

**8.3. Broken toolchain recovery — TODO**

**8.4. Workspace pollution check — TODO**

**8.5. Demo conformance export — TODO**

**8.6. Demo conformance compare — TODO**

---

**8.1. Clean-room full run (setup-env → tests-all)**

```bash
# Start from a state where everything is clean
rm -rf ./opt build
rm -rf ~/.local/bin/zig  # if previously installed

just setup-env
just tests-all
```

Verify:
- Everything installs from scratch via `dev` category
- Everything builds via dispatcher pattern
- Every test lane passes
- No manual intervention needed between steps

**8.2. Partial setup + full test**

```bash
# Skip some categories to test partial setup
python3 contrib/setup/orchestrator.py core,essential,toolchain,build --dry-run

# Then try tests-all (should fail gracefully or use pre-existing tools)
```

Verify:
- Missing tools are reported clearly
- Tests that require missing tools fail with actionable error

**8.3. Broken toolchain recovery**

```bash
# Simulate a partial setup failure
python3 contrib/setup/orchestrator.py core,essential  # partial success
# Manually break one tool (e.g., remove zig)
rm -f ~/.local/bin/zig

# Re-run — should detect missing tool and reinstall
python3 contrib/setup/orchestrator.py dev
```

Verify:
- Idempotency check detects the missing tool
- Re-install succeeds
- No corruption or partial state

**8.4. Workspace pollution check**

```bash
# After full setup-env + tests-all, check what was created
find . -name '*.tmp' -o -name '*.bak' -o -name '.*.swp' 2>/dev/null
ls -la ./opt/
ls -la .zig-global-cache/
```

Verify:
- No stray temporary files
- `./opt/` contains only expected install artifacts
- `.zig-global-cache/` contains only Zig build cache

**8.5. Demo conformance export**

```bash
just export-demo-conformance-linux
```

Verify:
- Builds Tickoni with `fd-lib-dir`
- Exports conformance bundle to `build/demo-conformance/linux/conformance.json`

**8.6. Demo conformance compare**

```bash
just compare-demo-conformance
```

Verify:
- Compares conformance JSON across all platforms (linux, macos-x86, macos-arm, windows-x86, windows-arm)
- Reports any differences in tickoni behavior

---

## Key Changes from Previous Version

1. **setup-env** now calls `orchestrator.py dev` (single category) instead of enumerating 11 explicit categories. The orchestrator resolves all dependencies from `dev` automatically.

2. **tests-all** now uses three aggregate recipes:
   - `just build-all` — builds fd + tk
   - `just quality-check-all` — format + lint + proto + yaml + spell (includes Qt)
   - `just security-check-all` — engine + codeql + gitleaks + seccomp + proof + sanitize (includes Qt)
   - `just security-engine-check-changes` — engine changes + orchestration linter
   - `just test-all` — unit + integration + coverage + system + e2e

3. **test-unit-all** now runs `test-unit-setup` (Python contrib tests) before platform tests.

4. **Dispatcher pattern**: `build-tk`, `build-fd`, `test-unit-tk`, `test-unit-fd`, `test-integration-tk` all route through `python3 ../../scripts/dispatch` to platform-specific recipes based on `{{ os }}-{{ arch }}`.

5. **Security expanded** from a single `@true` stub to 6 sub-checks (engine, codeql, gitleaks, seccomp, proof, sanitize) with per-platform stubs for Linux/macOS/Windows.

6. **Quality expanded** to include Qt format/lint and GitHub Actions linting.

7. **Demo conformance** recipes added for export and cross-platform comparison.

8. **System tests** now use `run_live_investment_demo.sh` (with `infra-ensure-llamacpp` for LLM infrastructure setup).

9. **Windows support** added for build, test-unit, test-integration, and test-system recipes.
