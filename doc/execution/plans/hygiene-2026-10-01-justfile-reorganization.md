# Justfile Architecture Reorganization

**Date:** 2026-10-01
**Status:** planned
**Scope:** justfile, just/ directory, CI workflows

## Problem Statement

The justfile system has accumulated structural debt:

1. **Root justfile bloat** — 180 lines mixing setup recipes, build dispatchers, and memory management
2. **No `just/setup/` directory** — all ~45 setup recipes live in `just/common.just` alongside variable definitions
3. **`--platform` inconsistency** — some orchestrator.py calls pass `--platform`, others don't (Qt passes it everywhere; Windows passes it for toolchains; Linux/macOS rely on auto-detection)
4. **Tool-specific setup in CI** — workflows call `setup-zig`, `setup-gitleaks-linux-x86`, etc. instead of usage-based `test-setup-unit`, `security-setup-secrets`
5. **Alias proliferation** — quality (77 recipes) and security (112 recipes) are mostly platform forwarding aliases

## Assessment Summary

### Recipe Distribution

| Category | Location | Recipes |
|----------|----------|---------|
| ROOT | justfile | 17 (mixed setup/build/memory) |
| common | just/common.just | 64 (variables + 45 setup + dispatchers) |
| build | just/build/ (4 files) | 41 |
| test | just/test/ (7 files) | 77 |
| quality | just/quality.just | 77 |
| security | just/security.just | 112 |

Total: 389 recipes across the tree.

### Platform Parameter Inconsistency

Auto-detection (`detect_platform(None)`) works for most cases but fails for:
- Windows toolchains (msvc doesn't exist on other platforms)
- Qt dependency resolution
- Cases where `install_method` is an OS map

Current state: Qt passes `--platform` everywhere, Windows passes it for toolchains, Linux/macOS rely on auto-detection. This is asymmetric.

### CI Usage vs Tool Names

| CI Workflow | Currently Calls | Problem |
|-------------|----------------|---------|
| _ci-unit.yml | setup-zig, test-setup-install, test-setup-run | Knows about zig and pytest |
| _ci-integration.yml | setup-zig | Knows about zig |
| _ci-demo.yml | setup-zig | Knows about zig |
| _ci-system.yml | setup-zig | Knows about zig |
| _ci-quality.yml | setup-quality-linux-x86 | Ok (usage-based) |
| _ci-security-secrets.yml | setup-gitleaks-linux-x86 | Knows about gitleaks |
| _ci-security-deep.yml | setup-fd-linux-x86-gcc, setup-build-linux-x86-gcc, setup-sanitizer-..., setup-security-linux-x86, setup-qt-linux-x86 | Knows about fd, build, sanitizer, security, qt |
| _ci-coverage.yml | setup-coverage-linux-x86-clang | Knows about coverage |

## Improvement Plan

### Phase 1: Reorganize setup into just/setup/

Move all ~45 setup recipes from `just/common.just` into `just/setup/`:

- `just/setup/install.just` — setup-build-*, setup-fd-*, setup-zig, setup-fd-deps-*, setup-coverage-*, setup-sanitizer-*
- `just/setup/quality.just` — setup-quality-*
- `just/setup/secrets.just` — setup-gitleaks-*
- `just/setup/security.just` — setup-security-*
- `just/setup/qt.just` — setup-qt-*
- `just/setup/developer.just` — setup-env, setup-git, setup-linux-*, setup-macos-*, setup-windows-*

Root justfile imports `just/setup/*.just` instead of inline setup from common.just.

### Phase 2: Standardize --platform usage

Choose one approach:

**Option A (explicit):** Always pass `--platform` explicitly. Eliminates all asymmetry. Low effort — just add `--platform {{ platform }}` to every orchestrator.py call.

**Option B (minimal):** Keep auto-detection but document edge cases. Only pass `--platform` where known to fail (Windows toolchains, Qt). Then fix setup-quality-windows-* to NOT pass `--platform` (quality tools are portable).

### Phase 3: Usage-based setup dispatchers

Create bare dispatchers that abstract away tool names:

- `test-setup-unit` → setup-zig + test-setup-install + test-setup-run
- `test-setup-integration` → setup-zig
- `test-setup-demo` → setup-zig
- `test-setup-system` → setup-zig
- `test-setup-coverage` → setup-coverage-linux-x86-clang
- `security-setup-secrets` → setup-gitleaks-linux-x86
- `security-setup-deep` → setup-fd-linux-x86-gcc + setup-build-linux-x86-gcc + setup-sanitizer-linux-x86-clang + setup-security-linux-x86 + setup-qt-linux-x86

Update CI workflows to call usage-based dispatchers instead of individual tool recipes.

### Phase 4: Thin the root justfile

Target: <50 lines in root justfile.

Move out of root:
- Setup recipes → just/setup/ (Phase 1)
- test-unit-fd-* and test-unit-tk dispatchers → just/test/unit.just
- build-qt-* recipes → just/build/qt.just
- Memory management (mem-*, kill-test) → just/system.just

Keep in root:
- Variable definitions (move from common.just to root or vars.just)
- import statements
- Aggregate dispatchers (tests-all, test-all, build-all)
- help, default

### Phase 5: Reduce alias proliferation

Quality (77 recipes) and security (112 recipes) are ~70% platform forwarding aliases.

Options:
- **Generator script:** `scripts/gen-aliases.py` generates platform aliases from canonical recipes
- **Just alias syntax:** Use `alias foo-bar = recipe-name` instead of `foo-bar: foo-canonical`
- **Dispatcher pattern:** Replace individual aliases with single dispatcher + case routing

## Execution Order

1. Phase 1 — setup reorganization (highest impact, immediate navigability)
2. Phase 3 — usage-based dispatchers (decouples CI from tool names)
3. Phase 2 — platform consistency (fix asymmetry, low effort)
4. Phase 4 — thin root justfile (natural consequence of 1+3)
5. Phase 5 — alias reduction (cosmetic, reduces maintenance burden)

## Verification

- `just --list` should show all recipes organized by category
- CI workflows should call usage-based dispatchers (Phase 3) after migration
- `just test-all` should still work end-to-end
- `just tests-all` should still work end-to-end
- No broken imports or missing recipe references
- All platform aliases still resolve correctly
