#!/usr/bin/env bash
# linux-x86-clang.sh — Setup Linux x86_64 with Clang toolchain
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"

log_info "Linux x86_64 Clang setup starting..."

# 1. OS packages — clang-18, lld-18, llvm-18
log_info "Installing system packages (clang-18, llvm-18, make, git)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    clang-18 llvm-18 lld-18 make git curl ca-certificates \
    cmake pkg-config libssl-dev zstd

# 2. Zig
ensure_zig

# 3. Clang version check
if clang-18 --version &>/dev/null; then
    log_info "clang-18: $(clang-18 --version | head -1)"
else
    log_error "clang-18 not found after install"
    exit 1
fi
export CC=clang-18 CXX=clang++-18

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

log_info "Linux x86_64 Clang setup complete"
