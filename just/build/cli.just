# ── Build: CLI (Zig) ───────────────────────────────────────────────────────
# CLI builds unconditionally via default_step (zig build),
# alongside the supervisor. No test dependencies.

# Bare dispatcher
build-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just build-cli-linux-x86 ;;
      linux-arm) exec just build-cli-linux-arm ;;
      macos-x86) exec just build-cli-macos-x86 ;;
      macos-arm) exec just build-cli-macos-arm ;;
      windows-x86) exec just build-cli-windows-x86 ;;
      windows-arm) exec just build-cli-windows-arm ;;
      *) echo "unsupported host platform for build-cli: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

build-cli-linux-x86:
    ZIG_LOCAL_CACHE_DIR={{ ZIG_CACHE }} ZIG_GLOBAL_CACHE_DIR={{ ZIG_GLOBAL_CACHE }} zig build -p {{ ZIG_PREFIX }} -Dfd-lib-dir={{ fd_tickoni_lib }}

build-cli-linux-arm: build-cli-linux-x86

build-cli-macos-x86: build-cli-linux-x86

build-cli-macos-arm: build-cli-linux-x86

build-cli-windows-x86: build-cli-linux-x86

build-cli-windows-arm: build-cli-linux-x86