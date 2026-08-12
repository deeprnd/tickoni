#!/usr/bin/env bash
# firedancer-deps.sh — Thin wrapper around deps.sh for use in setup lane scripts.
# Usage: source this from a lane script, or call directly with CC and CXX set.
# This sets CC/CXX, FD_AUTO_INSTALL_PACKAGES, then calls deps.sh check + fetch install.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

# Install Firedancer dependencies
install_firedancer_deps() {
    local cc="${CC:-gcc}"
    local cxx="${CXX:-g++}"
    log_info "Installing Firedancer deps (CC=${cc}, CXX=${cxx})..."

    (
        cd "${REPO_ROOT}"
        export CC="${cc}" CXX="${cxx}"
        export FD_AUTO_INSTALL_PACKAGES=1
        bash deps.sh check || {
            log_warn "deps.sh check failed — attempting install anyway"
        }
        bash deps.sh fetch install
    )
    log_info "Firedancer deps installed"
}

# Only run if called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Source common.sh for log_info/log_warn
    if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
        source "${SCRIPT_DIR}/common.sh"
    else
        # Fallback: minimal logging
        log_info() { printf '[setup-deps] %s\n' "$*" ; }
        log_warn() { printf '[setup-deps] WARN: %s\n' "$*" >&2 ; }
        log_error() { printf '[setup-deps] ERROR: %s\n' "$*" >&2 ; }
    fi
    install_firedancer_deps
fi
