# Test Unit Infrastructure Recipes Rename

## Problem

`test-build-pytest` in `just/setup/test.just` runs all 17 Python infrastructure tests from three directories:

```
contrib/build/tests/     (3 files — build infrastructure)
contrib/setup/tests/     (9 files — setup bootstrap)
contrib/tool/tests/      (4 files — tooling)
```

The name `test-build-pytest` is wrong on two counts: it implies only build tests, but it runs all three groups. Meanwhile, CI references `just test-unit-pytest` (a stale name from before the rename).

The current aggregate `test-unit-all` in `just/test/unit.just` runs `just test-unit-tk && just test-unit-fd && just test-unit-cli` but does **not** include the Python infrastructure tests at all — they run separately in CI but are invisible to the unit test aggregate.

## Classification

All 17 Python tests are **unit tests** — they test individual functions/modules with no external dependencies. They collectively test the build/setup/tooling infrastructure, not Tickoni application code.

| Group | Directory | Count | Tests |
|-------|-----------|-------|-------|
| build | `contrib/build/tests/` | 3 | orchestrator, make resolution, zig config |
| setup | `contrib/setup/tests/` | 9 | asset resolution, ccache, checks, install method, minisign, msvc, openssl, shell, zig |
| tooling | `contrib/tool/tests/` | 4 | badge updater, dynamic test opts, justfile refs, llama server, qt installer |

## Proposed Justfile Recipes

| Recipe | File | Runs | Scope |
|--------|------|------|-------|
| `test-unit-infra-build` | `just/test/unit.just` | `contrib/build/tests/` | build infrastructure only |
| `test-unit-infra-setup` | `just/test/unit.just` | `contrib/setup/tests/` | setup bootstrap only |
| `test-unit-infra-tooling` | `just/test/unit.just` | `contrib/tool/tests/` | tooling only |
| `test-unit-infra-all` | `just/setup/test.just` | all three groups | aggregate (replaces `test-build-pytest`) |

`test-unit-infra-all` stays in `just/setup/test.just` because that file owns Python test tooling setup. The per-group recipes go in `just/test/unit.just` alongside `test-unit-tk`, `test-unit-fd`, `test-unit-cli`.

`test-unit-all` gains `test-unit-infra-all` as a dependency.

## Steps

### Step 1 — Add per-group recipes to `just/test/unit.just`

Append after the existing `test-unit-cli-windows-arm:` recipe:

```just
# ── Python infrastructure unit tests ──────────────────────────────────────
# All tests in contrib/ validate build/setup/tooling infrastructure, not app code.

test-unit-infra-build:
    {{ python }} -m pytest --basetemp={{ justfile_dir }}/build/pytest -o cache_dir={{ justfile_dir }}/build/pytest-cache \
        {{ justfile_dir }}/contrib/build/tests/

test-unit-infra-setup:
    {{ python }} -m pytest --basetemp={{ justfile_dir }}/build/pytest -o cache_dir={{ justfile_dir }}/build/pytest-cache \
        {{ justfile_dir }}/contrib/setup/tests/

test-unit-infra-tooling:
    {{ python }} -m pytest --basetemp={{ justfile_dir }}/build/pytest -o cache_dir={{ justfile_dir }}/build/pytest-cache \
        {{ justfile_dir }}/contrib/tool/tests/
```

### Step 2 — Update `test-unit-all` in `just/test/unit.just`

Replace the current body:

```just
test-unit-all:
    {{ python }} contrib/tool/readme/run-badged-command.py unit bash -c "just test-unit-tk && just test-unit-fd && just test-unit-cli && just test-unit-infra-all"
```

### Step 3 — Replace `test-build-pytest` with `test-unit-infra-all` in `just/setup/test.just`

Replace:

```just
test-build-pytest:
    {{ python }} -m pytest --basetemp={{ justfile_dir }}/build/pytest -o cache_dir={{ justfile_dir }}/build/pytest-cache \
        {{ justfile_dir }}/contrib/build/tests/ \
        {{ justfile_dir }}/contrib/setup/tests/ \
        {{ justfile_dir }}/contrib/tool/tests/
```

With:

```just
test-unit-infra-all:
    just test-unit-infra-build
    just test-unit-infra-setup
    just test-unit-infra-tooling
```

The aggregate calls the per-group recipes via just, keeping path resolution consistent and enabling parallel execution later if needed.

### Step 4 — Update CI workflow

In `.github/workflows/_ci-unit.yml`, replace line 133:

```yaml
- name: Run Python unit tests (pytest)
  run: just test-unit-infra-all
```

### Step 5 — Verify

1. `just test-unit-infra-build` — 3 tests pass
2. `just test-unit-infra-setup` — 9 tests pass
3. `just test-unit-infra-tooling` — 4 tests pass (note: `test_llama_server.py` imports from `contrib.test` which may need adjustment — check first)
4. `just test-unit-infra-all` — all 17 pass
5. `just test-unit-all` — runs tk + fd + cli + infra
6. CI lane runs `just test-unit-infra-all` successfully
