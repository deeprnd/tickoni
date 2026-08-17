#!/usr/bin/env bash
# linux-arm-essential.sh — Linux aarch64 essential system packages (needs sudo)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"
SCRIPT_DIR="${REPO_ROOT}/contrib/setup"

log_info "Linux aarch64 essential setup starting..."

# 1. Read GCC version from JSON (fail if missing)
platform_key="$(get_platform_key)"
gcc_version="$(read_compiler_version gcc "$platform_key")"
log_info "GCC version from tool-versions.json: ${gcc_version}"

# 2. OS packages (needs sudo)
log_info "Installing system packages (gcc-${gcc_version}, make, build-essential, git)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    "gcc-${gcc_version}" "g++-${gcc_version}" make git curl ca-certificates \
    cmake pkg-config libssl-dev zstd

# 3. GCC version check
if gcc-${gcc_version} --version &>/dev/null; then
    log_info "gcc-${gcc_version}: $(gcc-${gcc_version} --version | head -1)"
else
    log_error "gcc-${gcc_version} not found after install"
    exit 1
fi
export CC="gcc-${gcc_version}" CXX="g++-${gcc_version}"

# 4. just (needs sudo for /usr/local/bin on Linux)
ensure_just

# 5. Quality tools (needs sudo on Linux)
if [ "${SECURITY:-off}" = "on" ]; then
    ensure_gitleaks
fi
ensure_shellcheck
ensure_precommit || log_warn "pre-commit not available"

# 6. Build tools (needs sudo on Linux)
ensure_buf || log_warn "buf not available"

# 7. Coverage tool (optional, needs sudo on Linux)
ensure_kcpy || log_warn "kcpy not available — coverage builds will be skipped"

print_install_summary

log_info "Linux aarch64 essential setup complete"
