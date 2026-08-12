#!/usr/bin/env bash
# linux-x86-clang.sh — Setup Linux x86_64 with Clang toolchain
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"

log_info "Linux x86_64 Clang setup starting..."

# 1. Read Clang version from JSON (fail if missing)
platform_key="$(get_platform_key)"
clang_version="$(read_compiler_version clang "$platform_key")"
log_info "Clang version from compiler-versions.json: ${clang_version}"

# 2. OS packages — clang-${clang_version}, lld-${clang_version}, llvm-${clang_version}
log_info "Installing system packages (clang-${clang_version}, llvm-${clang_version}, make, git)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    "clang-${clang_version}" "llvm-${clang_version}" "lld-${clang_version}" make git curl ca-certificates \
    cmake pkg-config libssl-dev zstd

# 3. Zig
ensure_zig

# 4. Clang version check
if clang-${clang_version} --version &>/dev/null; then
    log_info "clang-${clang_version}: $(clang-${clang_version} --version | head -1)"
else
    log_error "clang-${clang_version} not found after install"
    exit 1
fi
export CC="clang-${clang_version}" CXX="clang++-${clang_version}"

# 5. just
if ! tool_exists just; then
    log_info "Installing just..."
    curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
fi

# 6. Firedancer deps
ensure_firedancer_deps

# 7. Quality tools
ensure_gitleaks
ensure_shellcheck
ensure_precommit

# 8. Build tools
ensure_buf

# 9. Coverage tool (optional)
ensure_kcpy || log_warn "kcpy not available — coverage builds will be skipped"

print_install_summary

log_info "Linux x86_64 Clang setup complete"
