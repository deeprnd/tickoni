# ── Setup: Zig (idempotent — no-op if already installed) ───────────────────
# Used by CI test workflows that download build artifacts.
#
# Bare dispatcher routes to the platform-specific recipe.

setup-zig:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ os }}-{{ arch }}" in
      linux-x86) exec just setup-zig-linux-x86 ;;
      linux-arm) exec just setup-zig-linux-arm ;;
      macos-x86) exec just setup-zig-macos-x86 ;;
      macos-arm) exec just setup-zig-macos-arm ;;
      windows-x86) exec just setup-zig-windows-x86 ;;
      windows-arm) exec just setup-zig-windows-arm ;;
      *) echo "unsupported host platform for setup-zig: {{ os }}-{{ arch }}" >&2; exit 1 ;;
    esac

setup-zig-linux-x86:
    {{ python }} contrib/setup/orchestrator.py zig

setup-zig-linux-arm:
    {{ python }} contrib/setup/orchestrator.py zig

setup-zig-macos-x86:
    {{ python }} contrib/setup/orchestrator.py zig

setup-zig-macos-arm:
    {{ python }} contrib/setup/orchestrator.py zig

setup-zig-windows-x86:
    {{ python }} contrib/setup/orchestrator.py zig

setup-zig-windows-arm:
    {{ python }} contrib/setup/orchestrator.py zig
