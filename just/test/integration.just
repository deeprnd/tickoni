# Test: Integration recipes

test-e2e-fd:
    @true

test-e2e-tk:
    @true

test-e2e-all:
    {{ python }} contrib/tool/readme/run-badged-command.py e2e bash -c "just test-e2e-fd && just test-e2e-tk"

test-integration-fd:
    @true

# Tickoni integration lane: transport and boundary wiring against local mocks.
test-integration-tk-linux-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-linux-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-macos-x86:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

test-integration-tk-macos-arm:
    ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} integration-test

# Bare dispatcher; canonical platform recipes are in build/linux.just, build/macos.just, build/windows.just.
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

test-integration-all:
    {{ python }} contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk"
