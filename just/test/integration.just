# ── Test: Integration recipes ────────────────────────────────────────────
# Platform-specific integration test implementations, bare dispatchers, and platform aliases.

# Bare dispatcher; canonical platform/compiler recipes below are the implementation.
test-integration-fd:
    @true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-integration-tk-linux-x86 ;;
    linux-arm) exec just test-integration-tk-linux-arm ;;
    macos-x86) exec just test-integration-tk-macos-x86 ;;
    macos-arm) exec just test-integration-tk-macos-arm ;;
    windows-x86) exec just test-integration-tk-windows-x86 ;;
    windows-arm) exec just test-integration-tk-windows-arm ;;
    *) echo "unsupported host platform for test-integration-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-integration-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

# CLI integration tests (spawn the tickoni binary).
test-integration-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-integration-cli-linux-x86 ;;
    linux-arm) exec just test-integration-cli-linux-arm ;;
    macos-x86) exec just test-integration-cli-macos-x86 ;;
    macos-arm) exec just test-integration-cli-macos-arm ;;
    windows-x86) exec just test-integration-cli-windows-x86 ;;
    windows-arm) exec just test-integration-cli-windows-arm ;;
    *) echo "unsupported host platform for test-integration-cli: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

test-integration-cli-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} test-cli-main

test-integration-cli-linux-arm: test-integration-cli-linux-x86
test-integration-cli-macos-x86: test-integration-cli-linux-x86
test-integration-cli-macos-arm: test-integration-cli-linux-x86
test-integration-cli-windows-x86: test-integration-cli-linux-x86
test-integration-cli-windows-arm: test-integration-cli-linux-x86

test-integration-tk-linux-arm: test-integration-tk-linux-x86

test-integration-tk-macos-x86: test-integration-tk-linux-x86

test-integration-tk-macos-arm: test-integration-tk-linux-x86

# Windows-specific integration tests.
test-integration-tk-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-windows-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-all:
    {{ python }} contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk && just test-integration-cli"
