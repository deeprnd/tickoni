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

# Linux
build-tk-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -Dfd-lib-dir={{ fd_tickoni_lib }}

build-tk-linux-arm: build-tk-linux-x86

# macOS
build-tk-macos-x86: build-tk-linux-x86

build-tk-macos-arm: build-tk-linux-x86

# Windows
build-tk-windows-x86: build-tk-linux-x86

build-tk-windows-arm: build-tk-linux-x86
