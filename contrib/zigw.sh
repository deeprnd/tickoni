#!/usr/bin/env bash
set -euo pipefail

zig_cmd="${ZIG:-zig}"
using_windows_arm_x64_zig=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Detect Windows ARM via platform.sh (single source of truth for OS/arch).
source "${SCRIPT_DIR}/platform.sh"

is_windows=0
if [[ "$(tk_os)" == "windows" ]]; then
  is_windows=1
fi

is_windows_arm=0
if [[ "$is_windows" -eq 1 && "$(tk_arch)" == "arm" ]]; then
  is_windows_arm=1
fi

if [[ "$is_windows_arm" -eq 1 && -n "${LOCALAPPDATA:-}" ]]; then
  zig_root="$LOCALAPPDATA"
  if command -v cygpath >/dev/null 2>&1; then
    zig_root="$(cygpath -u "$zig_root")"
  fi
  zig_root="${zig_root}/Programs/Zig"
  if [[ -d "$zig_root" ]]; then
    candidate="$(find "$zig_root" -maxdepth 2 -type f -path '*/zig-x86_64-windows-*/zig.exe' | sort | tail -n 1)"
    if [[ -n "$candidate" ]]; then
      zig_cmd="$candidate"
      using_windows_arm_x64_zig=1
    fi
  fi
fi

# Allow CI / other callers to force the Zig target via env var
force_target="${ZIG_TARGET_OVERRIDE:-}"

if [[ "${1:-}" == "build" ]]; then
  has_target=0
  for arg in "${@:2}"; do
    case "$arg" in
      -Dtarget=*|--target|--target=*)
        has_target=1
        break
        ;;
    esac
  done

  # If CI explicitly exports a target override, honor it even when zig.exe came
  # from PATH rather than the Windows ARM x64-install auto-discovery path.
  if [[ -n "$force_target" && "$has_target" -eq 0 ]]; then
    set -- "$1" "-Dtarget=$force_target" "${@:2}"
  elif [[ "$using_windows_arm_x64_zig" -eq 1 && "$has_target" -eq 0 ]]; then
    set -- "$1" "-Dtarget=aarch64-windows" "${@:2}"
  fi
fi

exec "$zig_cmd" "$@"
