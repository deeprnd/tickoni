#!/usr/bin/env bash
# common.sh — shared POSIX helper functions for contrib/setup/ lane scripts.
# Source this from your lane script (linux-x86-gcc.sh, macos-x86.sh, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

log_info()  { printf '[setup] %s\n' "$*" ; }
log_warn()  { printf '[setup] WARN: %s\n' "$*" >&2 ; }
log_error() { printf '[setup] ERROR: %s\n' "$*" >&2 ; }

# Check if a command exists on PATH
tool_exists() { command -v "$1" &>/dev/null ; }

# Install Zig via install-zig.py
ensure_zig() {
    local zig_version
    zig_version="$(cat "${REPO_ROOT}/contrib/setup/zig-version" 2>/dev/null || echo "0.16.0")"
    local zig_bin="${HOME}/.local/zig/zig"

    if [ -f "$zig_bin" ] && "${zig_bin}" --version &>/dev/null; then
        log_info "Zig ${zig_version} already installed"
        export PATH="${HOME}/.local/zig:${PATH}"
        return 0
    fi

    log_info "Installing Zig ${zig_version}..."
    python3 "${SCRIPT_DIR}/install-zig.py" \
        --version "${zig_version}" \
        --install-root "${HOME}/.local" \
        --cache-root "${HOME}/.cache"
    export PATH="${HOME}/.local/zig:${PATH}"
    log_info "Zig installed to ${HOME}/.local/zig"
}

# Install Zig via install-zig-bootstrap.py (for bootstrap build users)
ensure_zig_bootstrap() {
    local zig_ref="master"
    if [ -f "${REPO_ROOT}/.zig-bootstrap-ref" ]; then
        zig_ref="$(cat "${REPO_ROOT}/.zig-bootstrap-ref")"
    fi
    local install_root="${HOME}/.local/zig-bootstrap"

    if [ -d "${install_root}" ] && [ -f "${install_root}/zig" ]; then
        log_info "Zig-bootstrap ${zig_ref} already installed"
        export PATH="${install_root}:${PATH}"
        return 0
    fi

    log_info "Installing Zig-bootstrap (ref=${zig_ref})..."
    python3 "${SCRIPT_DIR}/install-zig-bootstrap.py" \
        --bootstrap-ref "${zig_ref}" \
        --install-root "${install_root}" \
        --cache-root "${HOME}/.cache/zig-bootstrap"
    log_info "Zig-bootstrap installed to ${install_root}"
}

# Install Firedancer dependencies via deps.sh
ensure_firedancer_deps() {
    local cc="${CC:-gcc}"
    local cxx="${CXX:-g++}"
    log_info "Installing Firedancer deps (CC=${cc}, CXX=${cxx})..."
    (
        cd "${REPO_ROOT}"
        export CC="${cc}" CXX="${cxx}"
        bash deps.sh check || {
            log_warn "deps.sh check failed — attempting install anyway"
        }
        bash deps.sh fetch install
        bash contrib/deps-bundle.sh
    )
    log_info "Firedancer deps installed"
}

# Install gitleaks
ensure_gitleaks() {
    if tool_exists gitleaks; then
        log_info "gitleaks already installed"
        return 0
    fi

    log_info "Installing gitleaks..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y gitleaks
    elif command -v brew &>/dev/null; then
        brew install gitleaks
    elif command -v scoop &>/dev/null; then
        scoop install gitleaks
    else
        log_warn "No package manager found for gitleaks — skipping"
        return 1
    fi
}

# Install kcov from source (SimonKagstrom/kcpy)
ensure_kcov() {
    if tool_exists kcov; then
        log_info "kcov already installed"
        return 0
    fi

    log_info "Building kcov from source..."
    (
        cd "$(mktemp -d)"
        git clone --depth 1 https://github.com/SimonKagstrom/kcov.git .
        mkdir build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
        sudo make install || sudo cp kcov /usr/local/bin/kcov
    )
    log_info "kcov built and installed"
}

# Install shellcheck
ensure_shellcheck() {
    if tool_exists shellcheck; then
        log_info "shellcheck already installed"
        return 0
    fi

    log_info "Installing shellcheck..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y shellcheck
    elif command -v brew &>/dev/null; then
        brew install shellcheck
    elif command -v scoop &>/dev/null; then
        scoop install shellcheck
    else
        log_warn "No package manager found for shellcheck — skipping"
        return 1
    fi
}

# Install pre-commit via pipx (user-level, no sudo)
ensure_precommit() {
    if tool_exists pre-commit; then
        log_info "pre-commit already installed"
        return 0
    fi

    log_info "Installing pre-commit via pipx..."
    if command -v pipx &>/dev/null; then
        pipx install pre-commit
    elif command -v pip &>/dev/null; then
        pip install --user pre-commit
    else
        log_warn "No pip found for pre-commit — skipping"
        return 1
    fi
}

# Install buf via bufbuild/buf-install (user-level, no sudo)
ensure_buf() {
    if tool_exists buf; then
        log_info "buf already installed"
        return 0
    fi

    log_info "Installing buf..."
    if command -v go &>/dev/null; then
        go install github.com/bufbuild/buf/cmd/buf@latest
        export PATH="${HOME}/go/bin:${PATH}"
    elif command -v brew &>/dev/null; then
        brew install bufbuild/buf/buf
    else
        log_warn "No package manager found for buf — skipping"
        return 1
    fi
}

# Print summary of what was installed
print_install_summary() {
    local tools=("zig" "gcc" "clang" "make" "just" "gitleaks" "kcov" "shellcheck" "pre-commit" "buf")
    log_info "Installed tools:"
    for tool in "${tools[@]}"; do
        if tool_exists "$tool"; then
            log_info "  ✓ ${tool}: $(${tool} --version 2>&1 | head -1 | cut -c1-80)"
        else
            log_warn "  ✗ ${tool}: not found"
        fi
    done
}
