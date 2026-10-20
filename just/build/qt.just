# ── Build: Qt terminal (CMake-based, independent of build.zig) ────────────────
# Bare dispatcher routes to the correct platform recipe.

build-qt:
    #!/usr/bin/env bash
    set -euo pipefail
    case "`bash contrib/platform.sh os`-`bash contrib/platform.sh arch`" in
    linux-x86) exec just build-qt-linux-x86 ;;
    linux-arm) exec just build-qt-linux-arm ;;
    macos-x86) exec just build-qt-macos-x86 ;;
    macos-arm) exec just build-qt-macos-arm ;;
    windows-x86) exec just build-qt-windows-x86 ;;
    windows-arm) exec just build-qt-windows-arm ;;
    *) echo "unsupported host platform for build-qt: `bash contrib/platform.sh os`-`bash contrib/platform.sh arch`" >&2; exit 1 ;;
    esac

build-qt-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    QT6_CONFIG="${QT6_DIR:-}"
    if [ -n "$QT6_CONFIG" ] && [ -f "$QT6_CONFIG/Qt6Config.cmake" ]; then
        QT6_CONFIG_DIR="$QT6_CONFIG"
    else
        QT6_CONFIG=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1) || true
        QT6_CONFIG_DIR=$(dirname "$QT6_CONFIG")
    fi
    if [ -z "$QT6_CONFIG" ] || [ ! -f "$QT6_CONFIG_DIR/Qt6Config.cmake" ]; then echo "Qt6 not found — install Qt6 or set QT6_DIR manually" >&2; exit 1; fi
    QT6_CMAKE_DIR="$(cygpath -w "$QT6_CONFIG_DIR" 2>/dev/null || printf '%s' "$QT6_CONFIG_DIR")"
    cmake -DQt6_DIR="$QT6_CMAKE_DIR" -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-linux-arm: build-qt-linux-x86

build-qt-macos-x86: build-qt-linux-x86

build-qt-macos-arm: build-qt-linux-x86

build-qt-windows-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    QT6_CONFIG="${QT6_DIR:-}"
    if [ -n "$QT6_CONFIG" ] && [ -f "$QT6_CONFIG/Qt6Config.cmake" ]; then
        QT6_CONFIG_DIR="$QT6_CONFIG"
    else
        QT6_CONFIG=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1) || true
        QT6_CONFIG_DIR=$(dirname "$QT6_CONFIG")
    fi
    if [ -z "$QT6_CONFIG" ] || [ ! -f "$QT6_CONFIG_DIR/Qt6Config.cmake" ]; then echo "Qt6 not found — install Qt6 or set QT6_DIR manually" >&2; exit 1; fi
    QT6_CMAKE_DIR="$(cygpath -w "$QT6_CONFIG_DIR" 2>/dev/null || printf '%s' "$QT6_CONFIG_DIR")"
    cmake -DQt6_DIR="$QT6_CMAKE_DIR" -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-windows-arm: build-qt-windows-x86
