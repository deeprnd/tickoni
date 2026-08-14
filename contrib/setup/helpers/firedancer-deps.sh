#!/usr/bin/env bash
# firedancer-deps.sh — Thin wrapper around contrib/deps.sh for setup lane scripts.
#
# Sets CC/CXX/FD_AUTO_INSTALL_PACKAGES, then runs:
#   1. check  — verify system requirements
#   2. fetch  — download dependencies
#   3. install — build dependencies in place
#   4. contrib/deps-bundle.sh — create redistributable bundle
#
# Usage (sourced by lane scripts):
#   ensure_firedancer_deps "gcc" "12"   # Linux x86 GCC
#   ensure_firedancer_deps "clang" "18" # Linux x86 Clang
#   ensure_firedancer_deps "gcc" "14"   # Linux ARM GCC
#
# On macOS/Windows the compiler version is optional (uses system Xcode CLT
# or MSVC respectively); pass "" to skip explicit compiler pinning.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DEPS_SH="${REPO_ROOT}/deps.sh"
DEPS_BUNDLE="${REPO_ROOT}/contrib/deps-bundle.sh"

# ensure_firedancer_deps [compiler] [version]
#   compiler: "gcc", "clang", or "system" (macOS/Windows)
#   version: compiler version number, or "" to skip pinning
ensure_firedancer_deps() {
    local compiler="${1:-system}"
    local version="${2:-}"

    log_info "Setting up Firedancer dependencies..."

    if [ ! -f "$DEPS_SH" ]; then
        log_error "deps.sh not found at: ${DEPS_SH}"
        log_error "Run the build in the repository root where deps.sh lives."
        exit 1
    fi

    # Set compiler env vars
    local CC_VAR CXX_VAR
    case "$compiler" in
        gcc)
            CC_VAR="gcc${version:+-$version}"
            CXX_VAR="g++${version:+-$version}"
            ;;
        clang)
            CC_VAR="clang${version:+-$version}"
            CXX_VAR="clang++${version:+-$version}"
            ;;
        system)
            CC_VAR="cc"
            CXX_VAR="c++"
            ;;
        *)
            log_error "Unknown compiler: ${compiler}"
            exit 1
            ;;
    esac

    log_info "  Compiler: ${CC_VAR} / ${CXX_VAR}"

    # Phase 1: check
    log_info "  Phase 1: check..."
    CC="${CC_VAR}" \
    CXX="${CXX_VAR}" \
    FD_AUTO_INSTALL_PACKAGES=1 \
    bash "${DEPS_SH}" check

    # Phase 2: fetch + install
    log_info "  Phase 2: fetch install..."
    CC="${CC_VAR}" \
    CXX="${CXX_VAR}" \
    FD_AUTO_INSTALL_PACKAGES=1 \
    bash "${DEPS_SH}" fetch install

    # Phase 3: bundle
    log_info "  Phase 3: creating deps bundle..."
    bash "${DEPS_BUNDLE}"

    log_info "Firedancer dependencies ready"
}

# If sourced (not executed directly), expose the function.
# If executed directly, run the full pipeline with defaults.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Called directly: use system compiler
    ensure_firedancer_deps "system" ""
fi
