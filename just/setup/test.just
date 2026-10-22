# ── Setup: Test tools ─────────────────────────────────────────────────────
# Test-only: pytest and other test dependencies via orchestrator.py
#
# Bare dispatcher auto-detects platform and routes to the correct recipe.

setup-test:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-test-linux-x86 ;;
      linux-arm) exec just setup-test-linux-arm ;;
      macos-x86) exec just setup-test-macos-x86 ;;
      macos-arm) exec just setup-test-macos-arm ;;
      windows-x86) exec just setup-test-windows-x86 ;;
      windows-arm) exec just setup-test-windows-arm ;;
      *) echo "unsupported host platform for setup-test: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

setup-test-linux-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform linux-x86

setup-test-linux-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform linux-arm

setup-test-macos-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform macos-x86

setup-test-macos-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform macos-arm

setup-test-windows-x86:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform windows-x86

setup-test-windows-arm:
    {{ python }} contrib/setup/orchestrator.py test-tools --platform windows-arm

# ── Test: Run Python unit tests (pytest) ─────────────────────────────────
# Runs pytest for contrib/test/ (no FD build required).

test-unit-pytest:
    {{ python }} -m pytest --basetemp={{ justfile_dir }}/build/pytest -o cache_dir={{ justfile_dir }}/build/pytest-cache {{ justfile_dir }}/contrib/test/

# ── Setup: Audit fixture generation ──────────────────────────────────────
# Regenerates fixture files under src/tickoni/test/fixtures/ by running
# test + integration-test lanes with TK_GEN_FIXTURES=1.
#
# After the fixtures change, run `just test-unit-tk` to verify.
gen-audit-fixtures:
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true test
    TK_GEN_FIXTURES=1 ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true integration-test
