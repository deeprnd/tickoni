#!/usr/bin/env bash
# Cross-platform OS / arch detection — single source of truth.
#
# Usage (standalone):
#   contrib/platform.sh os         → linux | macos | windows
#   contrib/platform.sh arch       → x86 | arm
#   contrib/platform.sh platform   → linux-x86 | macos-arm | …
#   contrib/platform.sh            → linux-x86 (all 3)
#
# Usage (sourceable):
#   source contrib/platform.sh
#   # Sets TK_OS, TK_ARCH, TK_PLATFORM and prints them.
#
# Normalised arch values: x86, arm (NOT x86_64 / aarch64).
set -euo pipefail

# ── Internal functions ────────────────────────────────────────────────────────

tk_normalize_arch() {
  local raw="${1:-}"
  local normalized
  normalized="$(case "${raw,,}" in
    arm64|aarch64|arm64-bit*|arm\ 64-bit*|*arm64*) echo "arm" ;;
    x86_64|amd64|x64|x86-64*|*amd64*|*x64*)       echo "x86" ;;
    12)                                            echo "arm" ;;
    9)                                             echo "x86" ;;
    *)                                             echo "unrecognized" ;;
  esac)"
  if [[ "$normalized" != "unrecognized" ]]; then
    echo "$normalized"
    return 0
  fi
  echo "warning: unrecognized arch '${raw}', defaulting to x86" >&2
  echo "x86"
  return 0
}

tk_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  case "$uname_s" in
    Linux*)    echo "linux"; return 0 ;;
    Darwin*)   echo "macos"; return 0 ;;
  esac
  # Check for Windows environments
  if [[ -n "${MSYSTEM:-}" ]]; then
    echo "windows"; return 0
  fi
  if [[ -n "${PROCESSOR_ARCHITECTURE:-}" || -n "${PROCESSOR_IDENTIFIER:-}" ]]; then
    case "${PROCESSOR_ARCHITECTURE:-}" in
      AMD64|x86) echo "windows"; return 0 ;;
    esac
  fi
  echo "error: unrecognized OS '$uname_s' — supported: Linux, Darwin, Windows" >&2
  return 1
}

tk_arch() {
  local candidate normalized

  # 1. Explicit override
  if [[ -n "${TK_WINDOWS_HOST_ARCH:-}" ]]; then
    if normalized="$(tk_normalize_arch "$TK_WINDOWS_HOST_ARCH")"; then
      echo "$normalized"; return 0
    fi
  fi

  # 2. Powershell (Windows native)
  if command -v powershell >/dev/null 2>&1; then
    for candidate in \
      "$(powershell -NoProfile -Command '(Get-ComputerInfo).OsArchitecture' 2>/dev/null || true)" \
      "$(powershell -NoProfile -Command '(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)' 2>/dev/null || true)"; do
      if normalized="$(tk_normalize_arch "$candidate" 2>/dev/null)"; then
        echo "$normalized"; return 0
      fi
    done
  fi

  # 3. pwsh fallback
  if command -v pwsh >/dev/null 2>&1; then
    for candidate in \
      "$(pwsh -NoProfile -Command '(Get-ComputerInfo).OsArchitecture' 2>/dev/null || true)" \
      "$(pwsh -NoProfile -Command '(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)' 2>/dev/null || true)"; do
      if normalized="$(tk_normalize_arch "$candidate" 2>/dev/null)"; then
        echo "$normalized"; return 0
      fi
    done
  fi

  # 4. Environment variables (MSYS / WOW64 / native)
  for candidate in \
    "${MSYSTEM_CARCH:-}" \
    "${PROCESSOR_ARCHITEW6432:-}" \
    "${PROCESSOR_ARCHITECTURE:-}" \
    "${PROCESSOR_IDENTIFIER:-}" \
    "$(uname -m 2>/dev/null || echo unknown)"; do
    if normalized="$(tk_normalize_arch "$candidate" 2>/dev/null)"; then
      echo "$normalized"; return 0
    fi
  done

  echo "unknown"
}

tk_platform() {
  echo "$(tk_os)-$(tk_arch)"
}

# ── Standalone invocation ────────────────────────────────────────────────────
# If the script is run directly (not sourced), read arg and print result.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] 2>/dev/null || [[ -z "${1:-}" ]]; then
  # Sourced or no arg — set globals and print all three
  TK_OS="$(tk_os)"
  TK_ARCH="$(tk_arch)"
  TK_PLATFORM="$(tk_platform)"
  echo "TK_OS=${TK_OS}"
  echo "TK_ARCH=${TK_ARCH}"
  echo "TK_PLATFORM=${TK_PLATFORM}"
else
  # Run as: contrib/platform.sh [os|arch|platform]
  case "${1}" in
    os)         tk_os ;;
    arch)       tk_arch ;;
    platform)   tk_platform ;;
    *)
      echo "usage: $0 [os|arch|platform]" >&2
      exit 1
      ;;
  esac
fi
