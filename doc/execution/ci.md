# CI

## Command surface

CI performs repository setup, dependency installation, builds, quality checks,
security checks, tests, coverage, conformance export, and resource preparation
only through platform/compiler-qualified `just` recipes. Bare dispatchers remain
available for local convenience, but are not CI interfaces. Composite actions
are thin GitHub orchestration wrappers; their executable steps invoke `just`
recipes rather than scripts, installers, Zig, Make, or package managers.

The benchmark and book workflows were retired and are not part of the retained
CI surface.

This document describes the GitHub Actions CI workflows for Tickoni.

---

## Contents

- [Overview](#overview)
- [Workflow Summary](#workflow-summary)
- [Change Detection](#change-detection)
- [Build](#build)
- [Quality](#quality)
- [Security](#security)
- [Tests / Short](#tests--short)
- [Tests / Long](#tests--long)
- [Tests / XLong](#tests--xlong)
- [Optional Workflows](#optional-workflows)
- [Zig Toolchain Policy](#zig-toolchain-policy)
- [Centralized Firedancer Lib Machinery](#centralized-firedancer-lib-machinery)

---

## Overview

All seven Tickoni workflows trigger on pull requests targeting `main` and are also dispatchable manually via `workflow_dispatch`. Every workflow uses GitHub-hosted runners only — no self-hosted infrastructure is required.

This CI surface is intentionally **not** a coexist-with-upstream layout. Tickoni replaces the broad upstream Firedancer workflow set with a smaller Tickoni-owned workflow surface that keeps the PR lanes relevant to the harness, removes Firedancer-only/self-hosted jobs, and rewrites duplicated checks into the Tickoni workflow files below. In other words: macOS support here was added alongside an intentional shrink/re-shape of the upstream CI surface, not while retaining the full upstream workflow topology unchanged.

The retained workflows run only their checked-in triggers; retired benchmark and
book workflows are not part of the CI surface.

---

## Workflow Summary

|| Workflow                  | Runner(s)                           | Jobs                                                         | Timeout |
| ------------------------- | ----------------------------------- | ------------------------------------------------------------ | ------- |
| `build-fd.yml`            | `ubuntu-24.04`, `ubuntu-24.04-arm`  | Engine Build (GCC, Clang, ARM)                               | 20–30 m |
| `build-fd.yml`            | `windows-2025-vs2026`, `windows-11-vs2026-arm` | Engine Build / Windows x86_64, Engine Build / Windows ARM64  | 20–45 m |
| `build-tk.yml`            | `ubuntu-24.04`                      | Harness Build                                                | 20–30 m |
| `build-tk.yml`            | `windows-2025-vs2026`, `windows-11-vs2026-arm` | Harness Build / Windows x86_64, Harness Build / Windows ARM64 | 20–45 m |
| `quality.yml`             | `ubuntu-24.04`                      | Format Check, Lint Check, Proto Check                        | 20–30 m |
| `security.yml`            | `ubuntu-24.04`                      | Gitleaks, Sanitizers, SecComp                                | 20–45 m |
| `tests-short.yml`         | `ubuntu-24.04`                      | Harness Unit Tests, Harness Integration Tests, Harness Coverage | 20 m    |
| `tests-long.yml`          | `ubuntu-24.04`                      | Engine Unit Tests, Engine Coverage                           | 45–90 m |
| `tests-xlong.yml`         | `ubuntu-latest`                     | Engine E2E Tests (disabled), LLM System Tests                | 60–90 m |

All `detect-changes` jobs run on `ubuntu-slim`.

---

## Change Detection

Each workflow begins with a `detect-changes` job that compares the PR diff against a path regex. Subsequent jobs run only if at least one matching path changed. Manual `workflow_dispatch` runs always proceed regardless of path matches.

|| Workflow          | Paths that trigger jobs                                                                                  |
| ----------------- | -------------------------------------------------------------------------------------------------------- |
| `build-fd.yml`    | `src/`, `config/`, `contrib/setup/helpers/deps.sh`, `contrib/build/deps-bundle.sh`, `justfile`, `.github/actions/`, workflow file   |
| `quality.yml`     | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/quality/quality.sh`, lint script, `.github/actions/`, workflow file |
| `security.yml`    | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/security/security.sh`, gitleaks config, CodeQL config, `.github/actions/`, workflow file |
| `tests-short.yml` | `src/app/tickoni/`, `src/tickoni/`, `build.zig`, `build.zig.zon`, `justfile`, quality/security scripts, coverage configs, `.github/actions/`, workflow file |
| `tests-xlong.yml` | `src/`, `build.zig`, `build.zig.zon`, `justfile`, `contrib/test/`, `contrib/build/make-j`, `.github/actions/`, workflow file |

---

## Planned Windows Lanes

The Windows build CI contract is defined in the `win-support` finding plans.

Planned first-pass native Windows jobs:

| Workflow | Job | Runner | Entrypoint |
| --- | --- | --- | --- |
| `build-fd.yml` | `Engine Build / Windows 2025` | `windows-2025-vs2026` | `just build-fd-windows-x86` |
| `build-fd.yml` | `Engine Build / Windows 11 ARM` | `windows-11-vs2026-arm` | `just build-fd-windows-arm` |
| `build-tk.yml` | `Harness Build / Windows 2025` | `windows-2025-vs2026` | `just build-tk` |
| `build-tk.yml` | `Harness Build / Windows 11 ARM` | `windows-11-vs2026-arm` | `just build-tk` |

These are native Windows runner lanes only. The frozen first-pass contract explicitly excludes WSL, container, or VM fallback lanes as the official support path, and does not claim seccomp, sanitizer, replay, or full runtime parity on Windows.

---

## Zig Toolchain Policy

Tickoni now uses one repo-owned Zig entry point depending on context:

```

CI uses `contrib/setup/helpers/install-zig.py`, which downloads an official prebuilt Zig release archive for the host platform and installs it into a persistent prefix. This is the only Zig installation path for both CI and local developer machines.

Policy rules:

1. Do not use `mlugg/setup-zig`, `winget install zig`, or other third-party Zig installers in Tickoni CI.
2. All GitHub-hosted OS families (Windows, macOS, Linux) must call the same repo-owned CI installer script: `contrib/setup/helpers/install-zig.py`.
3. The upstream source of truth is the official Zig documentation and the official Zig download index.
4. Windows ARM must use the official GNU Zig release archive, not a Winget-managed Zig package.

Local developer machines use `contrib/setup/helpers/install-zig.py` (same as CI), not `install-zig-bootstrap.py` which was removed.

CI usage is centralized in the `just setup-*` recipes (e.g. `just setup-linux-x86-gcc`), which invoke `contrib/setup/orchestrator.py` for tool installation. The orchestrator reads `contrib/setup/tool-versions.json` to resolve the full dependency graph and installs tools via the appropriate platform-native method.

---

## Centralized Firedancer Lib Machinery

All Firedancer build recipes, CI workflows, quality checks, and security checks draw their source-dir and library definitions from a single shared script:

```
contrib/build/fd-tk-libs.sh
```

It defines:

|| Symbol | Description |
|--------|-------------|
| `FD_TK_LIB_SRCS` | Source dirs for the 5 harness libs (`src/tango src/util src/ballet src/disco src/waltz src/third_party/cjson src/third_party/s2n-bignum`) |
| `FD_TK_LIB_TEST_SRCS` | Same plus picohttpparser, blst, lz4, zstd, nanopb (for unit-test) |
| `FD_TK_LIB_COV_SRCS` | Core dirs + cjson only (for coverage) |
| `FD_TK_LIB_EXCLUDES` | `grep -vE` pattern for non-linked subdirs (`disco/quic|disco/gui|ballet/zksdk|ballet/zstd|waltz/quic`) |
| `FD_TK_LIBS` | Base lib list (`libfd_tango.a` … `libfd_waltz.a`) |
| `FD_TK_LIBS_EXTRA` | Extra libs for tests/coverage (`libfd_blst.a`, `libfd_zstd.a`, `libfd_lz4.a`) |
| `fd_compute_mks()` | Produce `LOCAL_MKS` from a source-dir list |
| `fd_build_fd()` | Unified builder accepting `BUILDDIR`, `CC`, `EXTRAS`, `TARGETS`, `SRCS`, `BUILD_TARGET` keyword args |

**To add a new lib dependency**, edit `contrib/build/fd-tk-libs.sh` (add the source dir to the appropriate `FD_TK_LIB_*_SRCS` array and its `.a` name to `FD_TK_LIBS` or `FD_TK_LIBS_EXTRA`). All justfile recipes, CI workflows, `contrib/quality/quality.sh`, and `contrib/security/security.sh` pick up the change automatically.

---

## Build

Two separate workflows build the Firedancer engine and the Tickoni Zig harness, so each can track its own change set.

### Engine Build

**File:** `.github/workflows/build-fd.yml`

Compiles the Firedancer engine (scoped to the 5 harness libraries). Four parallel build jobs run after `detect-changes`:

||| Job                      | Runner             | Compiler        | Command              |
| ------------------------ | ------------------ | --------------- | -------------------- |
| Engine Build / GCC       | `ubuntu-24.04`     | GCC 12          | `just build-fd-gcc`  |
| Engine Build / Clang     | `ubuntu-24.04`     | Clang 18        | `just build-fd-clang`|
| Engine Build / ARM       | `ubuntu-24.04-arm` | GCC 14          | `just build-fd-arm`  |

The engine builds use the `tickoni_fd` machine profile, which scopes the Firedancer build to only the 5 libraries Tickoni reuses (`fd_tango`, `fd_util`, `fd_ballet`, `fd_disco`, `fd_waltz`). This replaces the previous full-tree build and significantly reduces compile time.

The ARM job uses the `ubuntu-24.04-arm` GitHub-hosted runner to catch architecture-specific issues without a self-hosted machine.

### Harness Build

**File:** `.github/workflows/build-tk.yml`

Compiles the Tickoni Zig harness (`just build-tk`). Runs on `ubuntu-24.04`, `windows-2025-vs2026`, and `windows-11-vs2026-arm`.

The Windows build CI contract is documented in the branch history and CI workflows.

---

## Quality

**File:** `.github/workflows/quality.yml`

Static quality checks run as a matrix so they report independently and do not fail-fast:

|| Job           | Command                        | What it checks                              |
| ------------- | ------------------------------ | ------------------------------------------- |
| Format Check  | `just quality-format-check-all`| `zig fmt`, C formatting, whitespace rules   |
| Lint Check    | `just quality-lint-check-all`  | include guards, shellcheck, pre-commit hooks|
| Proto Check   | `just quality-proto-check-all` | Proto regeneration + `buf lint` + drift check |

Both jobs build the shared Firedancer/Tickoni library set via `.github/actions/build-fd-tk-libs`, which delegates to `just build-fd-tk-libs`, before running checks. The `detect-changes` step creates a local `main` branch so diff-based quality scripts have a comparison ref.

The Proto Check matrix entry installs `buf` via the GitHub Actions cache, then runs `just quality-proto-check-all` which:
1. Regenerates protobuf from JSON schemas via `gen_events.py --skip-check`
2. Runs `buf lint src/disco/events/schema`
3. Checks for uncommitted generated files (fails if `src/disco/events/generated/` or `events.proto` is dirty)

---

## Security

**File:** `.github/workflows/security.yml`

Security checks run as a matrix with independent reporting:

|| Job        | Compiler | Command                           | What it checks                          |
| ---------- | -------- | --------------------------------- | --------------------------------------- |
| Gitleaks   | GCC      | `just security-gitleaks-check-all`| Secret scanning via gitleaks            |
| Sanitizers | Clang 18 | `just security-sanitize-check-all`| ASan/UBSan on Firedancer and Tickoni C/Zig code |
| SecComp    | GCC      | `just security-seccomp-check-fd`  | Seccomp policy generation + drift check |

The Sanitizers job installs Clang 18, builds shared libs, then runs `just security-sanitize-check-all`.

---

## Tests / Short

**File:** `.github/workflows/tests-short.yml`

Covers the Tickoni Zig harness (`src/app/tickoni/`, `src/tickoni/`). Path filter is scoped to Tickoni sources only so these jobs do not re-run on pure Firedancer C changes.

|| Job                       | Command                    | Output artifact                               |
| ------------------------- | -------------------------- | --------------------------------------------- |
| Harness Unit Tests        | `just test-unit-tk`        | —                                             |
| Harness Integration Tests | `just test-integration-tk` | —                                             |
| Harness Tests Coverage    | `just test-cov-tk`         | `coverage-tk` — `build/coverage/tk/coverage-summary.json` |

Coverage artifact is uploaded even on failure (`if: always()`).

---

## Tests / Long

**File:** `.github/workflows/tests-long.yml`

Covers the Firedancer engine test suite and produces engine coverage using LLVM tooling.

|| Job                   | Compiler | Command             | Timeout | Output artifact                               |
| --------------------- | -------- | ------------------- | ------- | --------------------------------------------- |
| Engine Unit Tests     | GCC      | `just test-unit-fd` | 45 m    | —                                             |
| Engine Tests Coverage | Clang 18 | `just test-cov-fd`  | 90 m    | `coverage-fd` — `build/coverage/fd/coverage-summary.json` |

The coverage job installs `llvm-18` and sets up `llvm-profdata`, `llvm-objdump`, `llvm-ar`, and `llvm-cov` via `update-alternatives` before running.

---

## Tests / XLong

**File:** `.github/workflows/tests-xlong.yml`

Contains long-running tests that require additional infrastructure or model assets.

|| Job              | Runner          | Command              | Timeout | Status                     |
| ---------------- | --------------- | -------------------- | ------- | -------------------------- |
| Engine E2E Tests | `ubuntu-24.04`  | `just test-e2e-fd`   | 60 m    | **Disabled** (`if: false`) |
| LLM System Tests | `ubuntu-latest` | see steps below      | 90 m    | Active                     |

**Engine E2E Tests** — condition is hard-coded `if: false && …`, so it never runs. Remove `false &&` to re-enable. When enabled it configures pages via the Tickoni-owned `.github/actions/memory-management` action (not the upstream `.github/actions/hugepages` action). The `memory-management` action wraps the `just mem-*` recipes and degrades gracefully when a free GitHub-hosted runner cannot reserve all requested gigantic/huge pages, whereas upstream `hugepages` targets persistent self-hosted runners and fails the step on a short reservation. Keeping a separate action lets the shared `hugepages` file track Firedancer upstream without merge conflicts.

**LLM System Tests** — runs the explicit system live-model lane against a real local `llama.cpp` server. Steps in order:

1. Install `cmake`, `libopenblas-dev`, `libopenblas64-dev` via apt.
2. `just infra-ensure-llamacpp` — resolves `llama.cpp` from `TK_LLAMA_CPP_DIR` when set, otherwise defaults to `~/work/models/llama.cpp`. Downloads the pre-built binary archive from `https://github.com/ggml-org/llama.cpp/releases` for the current platform, verifies SHA256 checksum, extracts to the install directory, and verifies the server binary is present. OpenBLAS must be installed on the system as a separate dependency.
3. `just test-system-tk` — runs the full end-to-end flow: start server, run `zig build system-test`, stop server (`run_live_investment_demo.sh` calls `contrib/setup/orchestrator.py llm-server` for setup, and `contrib/test/orchestrator.py` for server lifecycle).

The llama.cpp path and model path can be overridden with `TK_LLAMA_CPP_DIR`,
`TK_HF_MODEL_DIR`, and `TK_HF_MODEL_FILE` environment variables
(see `contrib/test/run_live_investment_demo.sh`).

---

## LLM System Tests: Secrets

The LLM System Tests job uses `HF_TOKEN` to authenticate with Hugging Face when downloading the model. Public models (e.g. unsloth repos) do not strictly require a token, but setting one avoids rate-limiting and allows access to gated models.

To configure it: **GitHub → Repository → Settings → Secrets and variables → Actions → New repository secret**, name `HF_TOKEN`, value: a Hugging Face access token with at least read scope.

The job passes the secret as `env: HF_TOKEN: ${{ secrets.HF_TOKEN }}`. If the secret is absent the `hf` CLI falls back to unauthenticated access; the job will still pass for public models but may hit rate limits on busy runners.

---

## Optional Workflows

There are no optional benchmark or book workflows in the retained CI surface.

## Deleted Upstream Workflows

The following upstream Firedancer workflows were removed from Tickoni intentionally. This is not a temporary compatibility hack and it does not preserve the upstream Firedancer workflow shape unchanged: Tickoni's CI model explicitly replaces or drops upstream jobs that are duplicated by the Tickoni-owned workflow set below, depend on Firedancer validator infrastructure, or require self-hosted/GCS/CodeQL-specific environments that Tickoni does not carry in its default PR surface.

| Deleted file | Reason |
|-------------|--------|
| `on_pull_request.yml`, `on_main_push.yml`, `on_nightly.yml` | Orchestration-only; replaced by ci.md model |
| `tests.yml` | Reusable template; replaced by tests-short/long/xlong.yml |
| `backtest.yml`, `builds.yml` | FD-specific; replaced by build-fd.yml + build-tk.yml |
| `coverage_report.yml`, `coverage_test_vectors.yml` | FD GCS coverage infrastructure |
| `trailing_whitespace.yml` | Duplicated in quality.yml |
| `proto_check.yml` | Proto check is a matrix job in quality.yml |
| `check_seccomp.yml` | SecComp check is a matrix job in security.yml |
| `doxygen.yml` | Requires GCloud + rocky9 self-hosted runner |
| `codeql.yml` | Requires CodeQL runner group |
| `cbmc.yml` | Requires self-hosted X64 + CBMC toolchain |
| `test_firedancer_localnet.yml`, `test_firedancer_testnet.yml` | FD validator infra (512G runners, AGAVE, GCS) |
