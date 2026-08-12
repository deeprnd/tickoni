#!/usr/bin/env bash
# linux-arm-gcc.sh — Setup Linux aarch64 with GCC toolchain
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"

log_info "Linux aarch64 GCC setup starting..."

# 1. OS packages — gcc-14, g++-14 (Ubuntu 24.04+ ships newer gcc by default)
log_info "Installing system packages (gcc-14, make, build-essential, git)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    gcc-14 g++-14 make git curl ca-certificates \
    cmake pkg-config libssl-dev zstd

# 2. Zig
ensure_zig

# 3. GCC version check
if gcc-14 --version &>/dev/null; then
    log_info "gcc-14: $(gcc-14 --version | head -1)"
else
    log_error "gcc-14 not found after install"
    exit 1
fi
export CC=gcc-14 CXX=g++-14

# 4. just
if ! tool_exists just; then
    log_info "Installing just..."
    curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
fi

# 5. Firedancer deps
ensure_firedancer_deps

# 6. Quality tools
ensure_gitleaks
ensure_shellcheck
ensure_precommit

# 7. Build tools
ensure_buf

# 8. Coverage tool (optional)
ensure_kcov || log_warn "kcov not available — coverage builds will be skipped"

print_install_summary

log_info "Linux aarch64 GCC setup complete"
