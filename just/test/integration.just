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
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk

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
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} TK_LOG_LEVEL=0 zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-cli

test-integration-cli-linux-arm: test-integration-cli-linux-x86
test-integration-cli-macos-x86: test-integration-cli-linux-x86
test-integration-cli-macos-arm: test-integration-cli-linux-x86
test-integration-cli-windows-x86: test-integration-cli-linux-x86
test-integration-cli-windows-arm: test-integration-cli-linux-x86

test-integration-tk-linux-arm: test-integration-tk-linux-x86

test-integration-tk-macos-x86: test-integration-tk-linux-x86

test-integration-tk-macos-arm: test-integration-tk-linux-x86

# Infra lane — supervisor, tile lifecycle, Tango links, mock servers.
test-integration-tk-infra:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-integration-tk-infra-linux-x86 ;;
    linux-arm) exec just test-integration-tk-infra-linux-arm ;;
    macos-x86) exec just test-integration-tk-infra-macos-x86 ;;
    macos-arm) exec just test-integration-tk-infra-macos-arm ;;
    windows-x86) exec just test-integration-tk-infra-windows-x86 ;;
    windows-arm) exec just test-integration-tk-infra-windows-arm ;;
    *) echo \"unsupported host platform for test-integration-tk-infra: {{ os }}-{{ arch }}\" >&2; exit 1 ;;
    esac

test-integration-tk-infra-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk-infra

test-integration-tk-infra-linux-arm: test-integration-tk-infra-linux-x86

test-integration-tk-infra-macos-x86: test-integration-tk-infra-linux-x86

test-integration-tk-infra-macos-arm: test-integration-tk-infra-linux-x86

test-integration-tk-infra-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk-infra

test-integration-tk-infra-windows-arm: test-integration-tk-infra-windows-x86

# Domain lane — investment policy, allowed/blocked trades, replay.
test-integration-tk-domain:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
    linux-x86) exec just test-integration-tk-domain-linux-x86 ;;
    linux-arm) exec just test-integration-tk-domain-linux-arm ;;
    macos-x86) exec just test-integration-tk-domain-macos-x86 ;;
    macos-arm) exec just test-integration-tk-domain-macos-arm ;;
    windows-x86) exec just test-integration-tk-domain-windows-x86 ;;
    windows-arm) exec just test-integration-tk-domain-windows-arm ;;
    *) echo \"unsupported host platform for test-integration-tk-domain: {{ os }}-{{ arch }}\" >&2; exit 1 ;;
    esac

test-integration-tk-domain-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk-domain

test-integration-tk-domain-linux-arm: test-integration-tk-domain-linux-x86

test-integration-tk-domain-macos-x86: test-integration-tk-domain-linux-x86

test-integration-tk-domain-macos-arm: test-integration-tk-domain-linux-x86

test-integration-tk-domain-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk-domain

test-integration-tk-domain-windows-arm: test-integration-tk-domain-windows-x86

# Windows-specific integration tests.
test-integration-tk-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk

test-integration-tk-windows-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build --cache-dir {{ ZIG_CACHE }} --prefix {{ ZIG_PREFIX }} -Dtest=true -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$(zig_version)" test-integration-tk

test-integration-all:
    {{ python }} contrib/tool/readme/run-badged-command.py integration bash -c "just test-integration-fd && just test-integration-tk && just test-integration-cli"
