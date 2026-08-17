#!/usr/bin/env bash
# linux-x86-essential.sh — Linux x86_64 essential system packages (needs sudo)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"
SCRIPT_DIR="${REPO_ROOT}/contrib/setup"

log_info "Linux x86_64 essential setup starting..."

# 1. Determine toolchain and read version (default: gcc)
TOOLCHAIN="${TOOLCHAIN:-gcc}"
platform_key="$(get_platform_key)"
compiler_version="$(read_compiler_version "${TOOLCHAIN}" "$platform_key")"
log_info "Toolchain: ${TOOLCHAIN}, version from tool-versions.json: ${compiler_version}"

# 2. OS packages (needs sudo)
case "${TOOLCHAIN}" in
    gcc)
        log_info "Installing system packages (gcc-${compiler_version}, make, build-essential, git)..."
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends \
            "gcc-${compiler_version}" "g++-${compiler_version}" make git curl ca-certificates \
            cmake pkg-config libssl-dev zstd
        export CC="gcc-${compiler_version}" CXX="g++-${compiler_version}"
        ;;
    clang)
        log_info "Installing system packages (clang-${compiler_version}, make, build-essential, git)..."
        sudo apt-get update -qq
        sudo apt-get install -y --no-install-recommends \
            "clang-${compiler_version}" make git curl ca-certificates \
            cmake pkg-config libssl-dev zstd
        export CC="clang-${compiler_version}" CXX="clang++"
        ;;
    *)
        log_error "Unsupported toolchain: ${TOOLCHAIN} (expected gcc or clang)"
        exit 1
        ;;
esac

# 3. Compiler version check
if ${CC} --version &>/dev/null; then
    log_info "${CC}: $(${CC} --version | head -1)"
else
    log_error "${CC} not found after install"
    exit 1
fi

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

log_info "Linux x86_64 essential setup complete"
