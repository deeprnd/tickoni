#!/usr/bin/env bash
# platform.sh — POSIX platform detection (OS + arch).
# Sourced by contrib/setup/helpers/common.sh and lane scripts.
#
# Exports:
#   TK_OS      — "linux", "macos", "windows"
#   TK_ARCH    — "x86" or "arm"
#   TK_PLATFORM — "linux-x86", "linux-arm", "macos-x86", "macos-arm", "windows-x86", "windows-arm"

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"

# Normalize architecture string
tk_normalize_arch() {
    local raw="$1"
    case "$raw" in
        x86_64|x86|i686|amd64) echo "x86" ;;
        aarch64|arm64|arm)     echo "arm" ;;
        *) echo "x86" ;;
    esac
}

# Detect OS — returns "linux", "macos", or "windows"
tk_os() {
    local uname_s
    uname_s="$(uname -s)"
    case "$uname_s" in
        Linux*)     echo "linux" ;;
        Darwin*)    echo "macos" ;;
        *)
            # Windows (WSL/Git Bash/Cygwin): check for env vars
            if [ -n "${MSYSTEM:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${CYGWIN:-}" ]; then
                echo "windows"
            else
                echo "linux"
            fi
            ;;
    esac
}

# Detect architecture — returns "x86" or "arm"
tk_arch() {
    local candidate normalized

    # 1. Use the raw uname output first (works on Linux/macOS natively)
    candidate="$(uname -m 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ "$candidate" != "unknown" ]; then
        normalized="$(tk_normalize_arch "$candidate")"
        echo "$normalized"
        return 0
    fi

    # 2. Fallback: try platform-specific commands
    # Windows (WSL/Git Bash): use PowerShell to detect real architecture
    if [ "$(tk_os)" = "windows" ]; then
        for candidate in \
            "$(pwsh -NoProfile -Command '(Get-ComputerInfo).OsArchitecture' 2>/dev/null || true)" \
            "$(pwsh -NoProfile -Command '(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)' 2>/dev/null || true)" \
        ; do
            normalized="$(tk_normalize_arch "$candidate")"
            if [ -n "$normalized" ]; then
                echo "$normalized"
                return 0
            fi
        done
    fi

    # 3. Last resort
    echo "x86"
}

# Get platform key: "linux-x86", "linux-arm", "macos-x86", "macos-arm", etc.
tk_platform() {
    local os arch
    os="$(tk_os)"
    arch="$(tk_arch)"
    echo "${os}-${arch}"
}

# Export to parent shell
export TK_OS
export TK_ARCH
export TK_PLATFORM

# Initialize on source
TK_OS="$(tk_os)"
TK_ARCH="$(tk_arch)"
TK_PLATFORM="$(tk_platform)"
