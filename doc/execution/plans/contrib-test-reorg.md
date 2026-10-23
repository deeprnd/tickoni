# Contrib/Test Reorganization — Implementation Plan

## Problem

`contrib/test/` is a dumping ground for 22+ pytest files, infrastructure modules, shell scripts, and coverage configs. The directory name misleads — it sounds like "tests for the project" when these tests actually validate build tooling, not Tickoni application code. The CI recipe `test-unit-pytest` is similarly misleading, calling build-system tests "unit tests" when the real unit tests are Zig/C tests (`test-unit-tk`, `test-unit-fd`) in `src/`.

## Current State (file inventory)

### Pytest files (22+) — all test build/setup/CI infrastructure, not application code

From `contrib/test/`:
- `test_build_orchestrator.py` — tests `contrib/build/orchestrator.py`
- `test_zig_build_configuration.py` — tests Zig build config
- `test_build_resolve_make.py` — tests build resolution
- `test_dispatch_map.py` — tests dispatch map
- `test_run_test_series.py` — tests test series runner
- `test_badge_updater.py` — tests README badge generation
- `test_justfile_script_refs.py` — tests justfile script references
- `test_qt_installer.py` — tests Qt installer
- `test_windows_system_script_paths.py` — tests Windows script paths
- `test_windows_uuid_link.py` — tests Windows UUID linking
- `test_setup_zig.py`, `test_setup_shell.py`, `test_setup_ccache.py`, `test_setup_checks.py`
- `test_setup_msvc.py`, `test_setup_openssl_build.py`, `test_setup_minisign.py`
- `test_setup_install_method.py`, `test_setup_asset_resolution.py`
- `test_dynamic_test_opts.py`, `test_llama_server.py`

### Infrastructure modules

- `contrib/test/infra/dynamic_test_opts.py` — dynamic test resource detection (build infra)
- `contrib/test/infra/llama_server.py` — llama.cpp server management (shared by system tests)
- `contrib/test/infra/zig_build.py` — build orchestration (dead — see zig-build-delete.md)

### Orchestration

- `contrib/test/orchestrator.py` — CLI facade for llama.cpp server + Zig test lifecycle

### Shell scripts

- `contrib/test/run_unit_tests.sh` — FD C unit-test launcher
- `contrib/test/run_live_investment_demo.sh` — Linux system test runner
- `contrib/test/run_live_investment_demo_win.sh` — Windows system test runner
- `contrib/test/run_system_model_tests.sh` — model test runner (delegates to live_demo)
- `contrib/test/run_cli_demo_tests.sh` — CLI demo tests

### Coverage

- `contrib/test/coverage-fd.json`, `contrib/test/coverage-tk.json`, `contrib/test/coverage.sh`

### Artifact conformance

- `contrib/test/compare_build_artifact_conformance.py`
- `contrib/test/export_build_artifact_conformance.py`

### Config

- `contrib/test/pyproject.toml`, `contrib/test/conftest.py`

## Target Structure

```
contrib/
├── build/
│   ├── orchestrator.py                  ← from contrib/test/orchestrator.py
│   ├── tests/                           ← NEW
│   │   ├── test_build_orchestrator.py
│   │   ├── test_zig_build_configuration.py
│   │   ├── test_build_resolve_make.py
│   │   ├── test_dispatch_map.py
│   │   ├── test_run_test_series.py
│   │   ├── conftest.py                  ← shared build-test fixtures
│   │   └── pyproject.toml               ← from contrib/test/pyproject.toml
│   └── strategies/
├── setup/
│   ├── tests/                           ← NEW
│   │   ├── test_setup_zig.py
│   │   ├── test_setup_shell.py
│   │   ├── test_setup_ccache.py
│   │   ├── test_setup_checks.py
│   │   ├── test_setup_msvc.py
│   │   ├── test_setup_openssl_build.py
│   │   ├── test_setup_minisign.py
│   │   ├── test_setup_install_method.py
│   │   ├── test_setup_asset_resolution.py
│   │   └── conftest.py                  ← setup-specific fixtures
│   └── helpers/
├── infra/                               ← NEW
│   ├── __init__.py
│   ├── dynamic_test_opts.py             ← from contrib/test/infra/
│   └── llama_server.py                  ← from contrib/test/infra/
├── test/                                ← KEEP (thin)
│   ├── run_unit_tests.sh                ← FD unit-test launcher
│   ├── run_live_investment_demo.sh      ← Linux system test
│   ├── run_live_investment_demo_win.sh  ← Windows system test
│   └── run_system_model_tests.sh        ← model test runner
├── coverage/                            ← NEW
│   ├── coverage-fd.json
│   ├── coverage-tk.json
│   └── coverage.sh
└── tool/
    ├── readme/
    │   ├── badge_updater.py
    │   ├── coverage_report.py
    │   ├── tests/                       ← NEW
    │   │   └── test_badge_updater.py
    │   └── run-badged-command.py
    └── tests/                           ← NEW
        ├── test_justfile_script_refs.py
        ├── test_qt_installer.py
        ├── test_windows_system_script_paths.py
        └── test_windows_uuid_link.py
```

## Steps

### Step 1 — Create target directories

```bash
mkdir -p contrib/build/tests
mkdir -p contrib/setup/tests
mkdir -p contrib/infra
mkdir -p contrib/coverage
mkdir -p contrib/tool/readme/tests
mkdir -p contrib/tool/tests
```

### Step 2 — Move infrastructure modules

```bash
mv contrib/test/infra/dynamic_test_opts.py contrib/infra/
mv contrib/test/infra/llama_server.py contrib/infra/
touch contrib/infra/__init__.py
# Clean up old infra dir (zig_build.py is dead per zig-build-delete.md)
rm -rf contrib/test/infra/
```

### Step 3 — Move orchestration

```bash
mv contrib/test/orchestrator.py contrib/build/
```

### Step 4 — Move pytest files to sibling `tests/` directories

**Build tests** → `contrib/build/tests/`:
```bash
mv contrib/test/test_build_orchestrator.py contrib/build/tests/
mv contrib/test/test_zig_build_configuration.py contrib/build/tests/
mv contrib/test/test_build_resolve_make.py contrib/build/tests/
mv contrib/test/test_dispatch_map.py contrib/build/tests/
mv contrib/test/test_run_test_series.py contrib/build/tests/
mv contrib/test/conftest.py contrib/build/tests/
mv contrib/test/pyproject.toml contrib/build/tests/
```

**Setup tests** → `contrib/setup/tests/`:
```bash
mv contrib/test/test_setup_zig.py contrib/setup/tests/
mv contrib/test/test_setup_shell.py contrib/setup/tests/
mv contrib/test/test_setup_ccache.py contrib/setup/tests/
mv contrib/test/test_setup_checks.py contrib/setup/tests/
mv contrib/test/test_setup_msvc.py contrib/setup/tests/
mv contrib/test/test_setup_openssl_build.py contrib/setup/tests/
mv contrib/test/test_setup_minisign.py contrib/setup/tests/
mv contrib/test/test_setup_install_method.py contrib/setup/tests/
mv contrib/test/test_setup_asset_resolution.py contrib/setup/tests/
```

**Badge updater test** → `contrib/tool/readme/tests/`:
```bash
mv contrib/test/test_badge_updater.py contrib/tool/readme/tests/
```

**Tool tests** → `contrib/tool/tests/`:
```bash
mv contrib/test/test_justfile_script_refs.py contrib/tool/tests/
mv contrib/test/test_qt_installer.py contrib/tool/tests/
mv contrib/test/test_windows_system_script_paths.py contrib/tool/tests/
mv contrib/test/test_windows_uuid_link.py contrib/tool/tests/
```

### Step 5 — Move coverage files

```bash
mv contrib/test/coverage-fd.json contrib/coverage/
mv contrib/test/coverage-tk.json contrib/coverage/
mv contrib/test/coverage.sh contrib/coverage/
```

### Step 6 — Move artifact conformance scripts

```bash
mv contrib/test/compare_build_artifact_conformance.py contrib/tool/readme/
mv contrib/test/export_build_artifact_conformance.py contrib/tool/readme/
```

### Step 7 — Clean up `contrib/test/`

After all moves, `contrib/test/` should only contain:
- `run_unit_tests.sh` (FD unit-test launcher — stays)
- `run_live_investment_demo.sh` (system test — stays)
- `run_live_investment_demo_win.sh` (system test — stays)
- `run_system_model_tests.sh` (model test — stays)
- `run_cli_demo_tests.sh` (CLI demo — stays)

Remove stale caches:
```bash
rm -rf contrib/test/__pycache__/
rm -rf contrib/test/.pytest_cache/
```

### Step 8 — Rename CI recipe

In `just/setup/test.just`, rename `test-unit-pytest` to `test-build-pytest`.

### Step 9 — Update all path references (see table below)

### Step 10 — Verify

1. Run `just test-build-pytest` — all test files pass
2. Run `just test-unit-tk` and `just test-unit-fd-linux-x86-gcc` — still work
3. Run `just test-system-tk` — orchestrator path works
4. Run `just test-cov-tk` — coverage path works
5. Run `just test-unit-all` — all lanes pass
6. Run `just export-build-artifact-conformance-linux-x86` — still works
7. `git grep contrib/test/` — only launcher scripts and historical docs remain

---

## Path Reference Update Table

### A. Justfile recipes (4 files)

**`just/setup/test.just`**
| Line | Old | New |
|------|-----|-----|
| 41 | `contrib/test/` | `contrib/build/tests/` |

**`just/test/coverage.just`**
| Line | Old | New |
|------|-----|-----|
| 24 | `contrib/test/coverage.sh` | `contrib/coverage/coverage.sh` |

**`just/test/utils.just`**
| Line | Old | New |
|------|-----|-----|
| 8 | `contrib/test/infra/dynamic_test_opts.py` | `contrib/infra/dynamic_test_opts.py` |

**`just/test/unit.just`**
| Line | Old | New |
|------|-----|-----|
| 72, 80, 88 | `contrib/test/infra/dynamic_test_opts.py` | `contrib/infra/dynamic_test_opts.py` |
| 74, 82, 90 | `contrib/test/run_unit_tests.sh` | **unchanged** (launcher stays in contrib/test/) |

**`just/test/system.just`**
| Line | Old | New |
|------|-----|-----|
| 5, 8, 14 | `contrib/test/orchestrator.py` | `contrib/build/orchestrator.py` |

**`just/build/artifacts.just`**
| Line | Old | New |
|------|-----|-----|
| 63 | `contrib/test/compare_build_artifact_conformance.py` | `contrib/tool/readme/compare_build_artifact_conformance.py` |

### B. Makefile

**`config/everything.mk`**
| Line | Old | New |
|------|-----|-----|
| 100 | `contrib/test/run_unit_tests.sh` | **unchanged** (FD launcher stays in contrib/test/) |

### C. Documentation

**`doc/execution/testing-tickoni.md`**
| Section | What changes |
|---------|-------------|
| ~line 91 | `contrib/test/compare_demo_conformance.py` → `contrib/tool/readme/compare_demo_conformance.py` |
| ~line 196 | `contrib/test/export_demo_conformance_bundle.py` → `contrib/tool/readme/export_demo_conformance_bundle.py` |
| ~line 394 | `contrib/test/run_unit_tests.sh` → **unchanged** (launcher) |
| ~line 502 | `contrib/test/orchestrator.py` → `contrib/build/orchestrator.py` |
| ~line 507-512 | `contrib/test/orchestrator.py` → `contrib/build/orchestrator.py` |

**`doc/execution/ci.md`**
| Line | Old | New |
|------|-----|-----|
| ~404 | `contrib/test/orchestrator.py` | `contrib/build/orchestrator.py` |

**`doc/execution/plans/tests-all-template.md`**
| Line | Old | New |
|------|-----|-----|
| 72, 92 | `contrib/test/` | `contrib/build/tests/` |
| 654 | `contrib/test/*.py` | `contrib/build/tests/*.py` |

**`doc/organization.txt`**
| Lines | What changes |
|-------|-------------|
| 75-77 | `contrib/test/run_unit_tests.sh`, `run_script_tests.sh`, `run_integration_tests.sh` — verify if scripts still exist |

**Historical audit docs** — leave as-is (they document what *was* created, not current paths):
- `doc/execution/audits/stories/V2.10.S11-security-audit.md`
- `doc/execution/audits/stories/V2.10.S8-maintainability-audit.md`
- `doc/execution/audits/stories/V2.10.S11-maintainability-audit.md`

**`doc/execution/plans/zig-build-delete.md`**
| Section | What changes |
|---------|-------------|
| References to `contrib/test/orchestrator.py:51` | Update line numbers if orchestrator moved/modified |

---

## What NOT to move

- `contrib/test/run_unit_tests.sh` — FD unit-test launcher, called from `just/test/unit.just`, `config/everything.mk`, and CI
- `contrib/test/run_live_investment_demo.sh` and variants — system test runners
- `contrib/test/run_system_model_tests.sh` — model test runner
- `contrib/test/run_cli_demo_tests.sh` — CLI demo tests

These are all shell-based test runners, not pytest files. They belong in `contrib/test/` because they're test infrastructure scripts, not application tests.
