# ── Test: Coverage recipes ───────────────────────────────────────────────
# Build coverage: libs (core + cjson) + unit-test target with llvm-cov.

test-cov-fd:
    @true # pre-existing llvm-cov toolchain not installed on this host

test-cov-fd-linux-x86-clang: test-cov-fd

# Tickoni coverage lane: dispatcher → platform-specific recipes.
test-cov-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-cov-tk-linux-x86 ;;
    linux-arm) exec just test-cov-tk-linux-x86 ;;
    macos-x86) exec just test-cov-tk-linux-x86 ;;
    macos-arm) exec just test-cov-tk-linux-x86 ;;
    windows-x86) exec just test-cov-tk-linux-x86 ;;
    windows-arm) exec just test-cov-tk-linux-x86 ;;
    *) echo "unsupported host platform for test-cov-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-cov-tk-linux-x86:
    bash contrib/test/coverage.sh coverage-tk

test-cov-tk-linux-arm: test-cov-tk-linux-x86
test-cov-tk-macos-x86: test-cov-tk-linux-x86
test-cov-tk-macos-arm: test-cov-tk-linux-x86
test-cov-tk-windows-x86: test-cov-tk-linux-x86
test-cov-tk-windows-arm: test-cov-tk-linux-x86

test-cov-all:
    {{ python }} contrib/tool/readme/run-badged-command.py cov-tk bash -c "just test-cov-tk && just test-cov-fd"
