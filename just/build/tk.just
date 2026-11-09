# ── Build: Tickoni (Zig) ─────────────────────────────────────────────────
# Dispatcher and platform-specific Tickoni build recipes.
#
# zig version is computed once at runtime in the dispatcher's bash script,
# exported as $ZIG_VERSION, and referenced in all sub-recipes. No parse-time
# backtick — zig is only called when build-tk is actually invoked.

# Bare dispatcher
build-tk:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
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
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-linux-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

# macOS
build-tk-macos-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-macos-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

# Windows
build-tk-windows-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-windows-arm:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"
