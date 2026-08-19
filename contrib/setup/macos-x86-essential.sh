#!/usr/bin/env bash
# macos-x86-essential.sh — macOS x86_64 essential system setup (needs sudo)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"

log_info "macOS x86_64 essential setup starting..."

# 1. Xcode CLT (needs sudo for license accept)
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install
    # Wait for user to accept the license
    while ! xcode-select -p &>/dev/null; do
        sleep 2
    done
    sudo xcodebuild -license accept 2>/dev/null || true
else
    log_info "Xcode CLT already installed"
fi

log_info "macOS x86_64 essential setup complete"
