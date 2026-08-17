#!/usr/bin/env bash
# linux-arm-ops.sh — Linux aarch64 optional user-level tools (no sudo needed)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
source "${SCRIPT_DIR}/helpers/common.sh"
SCRIPT_DIR="${REPO_ROOT}/contrib/setup"

log_info "Linux aarch64 ops setup starting..."

# 1. Zig (user-level, no sudo)
ensure_zig

# 2. OpenSSL — build from source into ./opt (no sudo)
if [ ! -f "./opt/lib/libssl.a" ]; then
    bash "${SCRIPT_DIR}/helpers/install-openssl.sh"
else
    log_info "OpenSSL 3.6.2 already installed in ./opt/"
fi

log_info "Linux aarch64 ops setup complete"
