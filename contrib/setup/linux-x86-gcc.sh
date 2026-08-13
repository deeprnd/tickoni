#!/usr/bin/env bash
# linux-x86-gcc.sh — Setup Linux x86_64 with GCC toolchain
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"

log_info "Linux x86_64 GCC setup starting..."

# 1. Read GCC version from JSON (fail if missing)
platform_key="$(get_platform_key)"
gcc_version="$(read_compiler_version gcc "$platform_key")"
log_info "GCC version from compiler-versions.json: ${gcc_version}"

# 2. OS packages
log_info "Installing system packages (gcc-${gcc_version}, make, build-essential, git)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    "gcc-${gcc_version}" "g++-${gcc_version}" make git curl ca-certificates \
    cmake pkg-config libssl-dev zstd

# 3. Zig
ensure_zig

# 4. GCC version check
if gcc-${gcc_version} --version &>/dev/null; then
    log_info "gcc-${gcc_version}: $(gcc-${gcc_version} --version | head -1)"
else
    log_error "gcc-${gcc_version} not found after install"
    exit 1
fi
export CC="gcc-${gcc_version}" CXX="g++-${gcc_version}"

# 5. just
if ! tool_exists just; then
    log_info "Installing just..."
    curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
fi

# 6. Firedancer deps
ensure_firedancer_deps

# 7. Quality tools (security tools off by default, opt-in via SECURITY=on env var)
if [ "${SECURITY:-off}" = "on" ]; then
    ensure_gitleaks
fi
ensure_shellcheck
ensure_precommit

# 8. Build tools
ensure_buf

# 9. Coverage tool (optional, skip if kcov fails)
ensure_kcpy || log_warn "kcpy not available — coverage builds will be skipped"

print_install_summary

log_info "Linux x86_64 GCC setup complete"
