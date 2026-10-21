# Test: Performance recipes
# Perf tests are Linux-only (CPU placement proofs).
# test-perf-fd and test-perf-qt are intentional no-ops — FD perf uses
# the Firedancer harness directly; Qt has no perf lane yet.

# Tickoni perf lane: dispatcher → platform-specific recipes.
test-perf-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-perf-tk-linux-x86 ;;
    linux-arm) exec just test-perf-tk-linux-x86 ;;
    macos-x86) exec just test-perf-tk-macos-x86 ;;
    macos-arm) exec just test-perf-tk-macos-arm ;;
    windows-x86) exec just test-perf-tk-windows-x86 ;;
    windows-arm) exec just test-perf-tk-windows-arm ;;
    *) echo "unsupported host platform for test-perf-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Canonical linux-x86 impl (set -euo pipefail inherited from dispatcher)
test-perf-tk-linux-x86:
    (cd {{ justfile_dir }} && ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dperf=true -Dfd-lib-dir={{ fd_tickoni_lib }} perf-test)

test-perf-tk-linux-arm: test-perf-tk-linux-x86
test-perf-tk-macos-x86:
    @true
test-perf-tk-macos-arm:
    @true
test-perf-tk-windows-x86:
    @true
test-perf-tk-windows-arm:
    @true

test-perf-fd:
    @true

test-perf-qt:
    @true

test-perf-all:
    {{ python }} contrib/tool/readme/run-badged-command.py perf bash -c "just test-perf-tk && just test-perf-fd && just test-perf-qt"
