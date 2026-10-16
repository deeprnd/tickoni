# ── Build: Qt terminal (CMake-based, independent of build.zig) ────────────────

build-qt-linux-x86:
    #!/usr/bin/env bash
    set -euo pipefail
    REPO_ROOT="$(git rev-parse --show-toplevel)"
    cd "$REPO_ROOT"
    QT6_CONFIG=$(find ~/Qt -name Qt6Config.cmake 2>/dev/null | head -1) || true
    if [ -z "$QT6_CONFIG" ]; then echo "Qt6 not found — install Qt6 or set QT6_DIR manually" >&2; exit 1; fi
    QT6_DIR=$(dirname "$QT6_CONFIG") && QT6_DIR=$(dirname "$QT6_DIR")
    CMAKE_PREFIX_PATH="$QT6_DIR" cmake -S "$REPO_ROOT/src/tickoni/terminal" -B "$REPO_ROOT/build/tickoni-terminal" && cmake --build "$REPO_ROOT/build/tickoni-terminal" -j {{ cpu_count }}

build-qt-linux-arm: build-qt-linux-x86

build-qt-macos-x86: build-qt-linux-x86

build-qt-macos-arm: build-qt-linux-x86

build-qt-windows-x86: build-qt-linux-x86

build-qt-windows-arm: build-qt-linux-x86
