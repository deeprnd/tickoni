#!/usr/bin/env bash
# macos-x86.sh — Setup macOS x86_64
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"
SCRIPT_DIR="${REPO_ROOT}/contrib/setup"

log_info "macOS x86_64 setup starting..."

# 1. Homebrew (install if missing)
if ! command -v brew &>/dev/null; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    export PATH="/usr/local/bin:${PATH}"
fi

# 2. Core packages
log_info "Installing Homebrew packages (gcc, make, git, cmake)..."
brew install \
    gcc make git cmake pkg-config \
    coreutils zstd

# 3. Zig
ensure_zig

# 4. just
ensure_just

# 5. Xcode CLT (if not already installed)
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install
    # Wait for user to accept the license
    while ! xcode-select -p &>/dev/null; do
        sleep 2
    done
    sudo xcodebuild -license accept 2>/dev/null || true
fi

# 6. OpenSSL 3.6.2 — build from source (deps.sh logic) to get the
# right API level for Firedancer; Homebrew OpenSSL is incompatible.
if [ ! -f "./opt/lib/libssl.a" ]; then
    bash "${SCRIPT_DIR}/install-openssl.sh"
else
    log_info "OpenSSL 3.6.2 already installed in ./opt/"
fi

# 7. Quality tools (security tools off by default, opt-in via SECURITY=on env var)
if [ "${SECURITY:-off}" = "on" ]; then
    ensure_gitleaks
fi
ensure_shellcheck
ensure_precommit

# 8. Build tools
ensure_buf

# 9. Coverage tool (optional)
ensure_kcpy || log_warn "kcpy not available — coverage builds will be skipped"

# 10. macOS-specific: install llvm tools if not in PATH
if ! tool_exists llvm-config; then
    log_info "Installing llvm..."
    brew install llvm
    export PATH="$(brew --prefix llvm)/bin:${PATH}"
fi

print_install_summary

log_info "macOS x86_64 setup complete"
