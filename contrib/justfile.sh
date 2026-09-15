#!/usr/bin/env bash
# Resolve values that justfile backtick variables need with cross-platform
# normalisation (forward slashes, GNU make detection, etc.).
#
# Usage (standalone):
#   contrib/justfile.sh           → full repo path (forward slashes)
#   contrib/justfile.sh make      → path to GNU make (gmake on macOS)
#
# Usage (sourceable):
#   source contrib/justfile.sh
#   # Sets JUSTFILE_DIR and prints it.
#
set -euo pipefail

# ── Internal ──────────────────────────────────────────────────────────────────

jf_repo_path() {
  # Resolve repo root from the script's own location so it works from any cwd.
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Walk up from script_dir to find the .git directory (repo root).
  local dir="$script_dir"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      cd "$dir"
      break
    fi
    dir="$(cd "$dir/.." && pwd)"
  done
  git rev-parse --show-toplevel 2>/dev/null | sed 's|\\|/|g'
}

jf_find_gmake() {
  # Firedancer's GNUmakefile uses `undefine`, which needs GNU Make >= 3.82.
  # Prefer `gmake` (Homebrew installs it on macOS); fall back to `make`.
  if command -v gmake >/dev/null 2>&1; then
    command -v gmake
    return 0
  fi
  if command -v make >/dev/null 2>&1; then
    # Verify GNU make on platforms where make might be BSD (e.g. macOS).
    # GNU make exits 0 on a bogus target; BSD make exits 2.
    if make -f /dev/null 2>/dev/null; then
      command -v make
      return 0
    fi
  fi
  # Final fallback — caller may want an error, not a bare `make`.
  command -v make
}

# ── Standalone invocation ─────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" != "${0}" ]] 2>/dev/null || [[ -z "${1:-}" ]]; then
  # Sourced or no arg — set globals and print justfile_dir.
  JUSTFILE_DIR="$(jf_repo_path)"
  echo "$JUSTFILE_DIR"
else
  # Run as: contrib/justfile.sh [make]
  case "${1}" in
    make)  jf_find_gmake ;;
    *)     jf_repo_path ;;
  esac
fi
