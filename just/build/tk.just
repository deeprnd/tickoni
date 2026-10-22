# ── Build: Tickoni (Zig) ─────────────────────────────────────────────────
# Dispatcher and platform-specific Tickoni build recipes.

# Bare dispatcher
build-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-tk-linux-x86 ;;
      linux-arm) exec just build-tk-linux-arm ;;
      macos-x86) exec just build-tk-macos-x86 ;;
      macos-arm) exec just build-tk-macos-arm ;;
      windows-x86) exec just build-tk-windows-x86 ;;
      windows-arm) exec just build-tk-windows-arm ;;
      *) echo "unsupported host platform for build-tk: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

# Zig build command (shared across platforms)
ZIG_BUILD_CMD := "ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }}"

# Linux
build-tk-linux-x86:
    {{ ZIG_BUILD_CMD }}

build-tk-linux-arm:
    {{ ZIG_BUILD_CMD }}

# macOS
build-tk-macos-x86:
    {{ ZIG_BUILD_CMD }}

build-tk-macos-arm:
    {{ ZIG_BUILD_CMD }}

# Windows
build-tk-windows-x86:
    {{ ZIG_BUILD_CMD }}

build-tk-windows-arm:
    {{ ZIG_BUILD_CMD }}
