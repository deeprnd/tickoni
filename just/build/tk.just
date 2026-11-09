# ── Build: Tickoni (Zig) ─────────────────────────────────────────────────
# Dispatcher and platform-specific Tickoni build recipes.
#
# zig version is computed at runtime: the dispatcher (build-tk) exports it
# for the exec chain, and each platform sub-recipe also exports it so CI can
# call the sub-recipe directly without the dispatcher.

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
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-linux-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

# macOS
build-tk-macos-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-macos-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

# Windows
build-tk-windows-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"

build-tk-windows-arm:
    #!/usr/bin/env bash
    set -euo pipefail
    export ZIG_VERSION=$(zig version)
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }} -Dzig-version="$ZIG_VERSION"
