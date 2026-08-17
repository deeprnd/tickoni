#!/usr/bin/env bash
# macos-x86-ops.sh — macOS x86_64 optional tools (no sudo needed)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"
SCRIPT_DIR="${REPO_ROOT}/contrib/setup"

log_info "macOS x86_64 ops setup starting..."

# 1. Homebrew (install if missing — no sudo needed)
if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    export PATH="/usr/local/bin:${PATH}"
fi

# 2. Core packages (brew, no sudo)
log_info "Installing Homebrew packages (gcc, make, git, cmake)..."
brew install \
    gcc make git cmake pkg-config \
    coreutils zstd

# 3. Zig (user-level, no sudo)
ensure_zig

# 4. just (brew, no sudo)
ensure_just

# 5. Quality tools (brew/go/pipx, no sudo)
if [ "${SECURITY:-off}" = "on" ]; then
    ensure_gitleaks
fi
ensure_shellcheck
ensure_precommit || log_warn "pre-commit not available"

# 6. Build tools (brew/go, no sudo)
ensure_buf || log_warn "buf not available"

# 7. Coverage tool (optional, brew on macOS)
ensure_kcpy || log_warn "kcov not available — coverage builds will be skipped"

# 8. OpenSSL — build from source into ./opt (no sudo)
if [ ! -f "./opt/lib/libssl.a" ]; then
    bash "${SCRIPT_DIR}/helpers/install-openssl.sh"
else
    log_info "OpenSSL 3.6.2 already installed in ./opt/"
fi

# 9. macOS-specific: install llvm tools if not in PATH
if ! tool_exists llvm-config; then
    log_info "Installing llvm..."
    brew install llvm
    export PATH="$(brew --prefix llvm)/bin:${PATH}"
fi

print_install_summary

log_info "macOS x86_64 ops setup complete"
