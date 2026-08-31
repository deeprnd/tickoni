#!/usr/bin/env bash
set -euo pipefail

zig_cmd="${ZIG:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Detect Windows ARM via platform.sh (single source of truth for OS/arch).
source "${SCRIPT_DIR}/../platform.sh"

is_windows=0
if [[ "$(tk_os)" == "windows" ]]; then
  is_windows=1
fi

is_windows_arm=0
if [[ "$is_windows" -eq 1 && "$(tk_arch)" == "arm" ]]; then
  is_windows_arm=1
fi

if [[ "$is_windows_arm" -eq 1 && -n "${LOCALAPPDATA:-}" ]]; then
  # Prefer the exact version pinned in tool-versions.json so local runs
  # match CI (both use x86_64 Windows Zig on ARM64).
  local_zig_version=""
  if [[ -f "${SCRIPT_DIR}/../setup/tool-versions.json" ]]; then
    # Extract the zig version from tool-versions.json.
    local_zig_version="$(python3 -c "import json; print(json.load(open('${SCRIPT_DIR}/../setup/tool-versions.json'))['versions']['zig'])" 2>/dev/null || echo "")"
  fi

  if [[ -n "$local_zig_version" ]]; then
    zig_root="${LOCALAPPDATA}/Programs/Zig"
    candidate="${zig_root}/zig-x86_64-windows-${local_zig_version}/zig.exe"
    if [[ -f "$candidate" ]]; then
      zig_cmd="$candidate"
      using_windows_arm_x64_zig=1
    fi
  fi

  # Fallback to the previous scan behaviour when the pinned version
  # isn't installed yet (e.g. developer machine hasn't upgraded yet).
  # TODO: remove this fallback scan path entirely once install-zig.py is
  # the single authority for Zig installation across all lanes (CI + local).
  # See contrib/setup/helpers/install-zig.py.
  if [[ -z "$local_zig_version" || "${using_windows_arm_x64_zig:-0}" -ne 1 ]]; then
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
fi

# Auto-discover zig when not set via $ZIG and not already found.
# The orchestrator installs zig to $HOME/.local/zig-<target>-<version>/
# (bin dir is <install>/zig). GITHUB_PATH may not persist across steps.
if [[ -z "$zig_cmd" ]]; then
  if command -v zig >/dev/null 2>&1; then
    zig_cmd="zig"
  else
    # Search $HOME/.local for zig (orchestrator install location).
    local_zig_root="${HOME:-}/.local"
    if [[ -d "$local_zig_root" ]]; then
      candidate="$(find "$local_zig_root" -maxdepth 2 -type d -name 'zig-*' | sort | tail -n 1)"
      if [[ -n "$candidate" && -f "${candidate}/zig" ]]; then
        zig_cmd="${candidate}/zig"
      elif [[ -n "$candidate" && -f "${candidate}/zig.exe" ]]; then
        zig_cmd="${candidate}/zig.exe"
      fi
    fi
  fi
fi

if [[ -z "$zig_cmd" ]]; then
  echo "ERROR: zig not found — install zig or set \$ZIG" >&2
  exit 127
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
  elif [[ "${using_windows_arm_x64_zig:-0}" -eq 1 && "$has_target" -eq 0 ]]; then
    set -- "$1" "-Dtarget=aarch64-windows" "${@:2}"
  fi
fi

exec "$zig_cmd" "$@"
