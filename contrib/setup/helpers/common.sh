#!/usr/bin/env bash
# common.sh — shared POSIX helper functions for contrib/setup/ lane scripts.
# Source this from your lane script (linux-x86-gcc.sh, macos-x86.sh, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
COMPILER_VERSIONS="${REPO_ROOT}/contrib/setup/compiler-versions.json"

log_info()  { printf '[setup] %s\n' "$*" ; }
log_warn()  { printf '[setup] WARN: %s\n' "$*" >&2 ; }
log_error() { printf '[setup] ERROR: %s\n' "$*" >&2 ; }

# Check if a command exists on PATH
tool_exists() { command -v "$1" &>/dev/null ; }

# Read zig-version from file — fail hard if missing
read_zig_version() {
    local zig_file="${REPO_ROOT}/contrib/setup/zig-version"
    if [ ! -f "$zig_file" ]; then
        log_error "Zig version file missing: ${zig_file}"
        log_error "Create it with: echo '0.16.0' > ${zig_file}"
        exit 1
    fi
    local version
    version="$(cat "$zig_file" | tr -d '[:space:]')"
    if [ -z "$version" ]; then
        log_error "Zig version file is empty: ${zig_file}"
        exit 1
    fi
    echo "$version"
}

# Read compiler version from JSON — fail hard if missing
# Usage: read_compiler_version "gcc" "linux-x86"
read_compiler_version() {
    local tool="$1"
    local platform_key="$2"
    
    if [ ! -f "$COMPILER_VERSIONS" ]; then
        log_error "Compiler versions file missing: ${COMPILER_VERSIONS}"
        exit 1
    fi
    
    local version
    version="$(python3 -c "
import json, sys
try:
    data = json.load(open('${COMPILER_VERSIONS}'))
    v = data.get('${tool}', {}).get('${platform_key}', '')
    if not v:
        sys.exit(1)
    print(v)
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null)" || {
        log_error "Compiler version not defined for ${tool} on ${platform_key}"
        log_error "Add '${tool}-${platform_key}' to ${COMPILER_VERSIONS}"
        exit 1
    }
    
    echo "$version"
}

# Get platform key for version lookup
# Usage: get_platform_key
# Returns: linux-x86, linux-arm, macos-x86, macos-arm
get_platform_key() {
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    local arch
    arch="$(uname -m)"
    
    case "$os" in
        linux)
            case "$arch" in
                x86_64) echo "linux-x86" ;;
                aarch64|arm64) echo "linux-arm" ;;
                *) log_error "Unknown Linux architecture: $arch"; exit 1 ;;
            esac
            ;;
        darwin)
            case "$arch" in
                x86_64) echo "macos-x86" ;;
                arm64) echo "macos-arm" ;;
                *) log_error "Unknown macOS architecture: $arch"; exit 1 ;;
            esac
            ;;
        *)
            log_error "Unsupported OS: $os ($arch)"
            exit 1
            ;;
    esac
}

# Install Zig via install-zig.py
ensure_zig() {
    local zig_version
    zig_version="$(read_zig_version)"
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

# Install Firedancer dependencies via deps.sh
ensure_firedancer_deps() {
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

# Install kcpy from source (SimonKagstrom/kcpy)
ensure_kcpy() {
    if tool_exists kcpy; then
        log_info "kcpy already installed"
        return 0
    fi

    log_info "Building kcpy from source..."
    (
        cd "$(mktemp -d)"
        git clone --depth 1 https://github.com/SimonKagstrom/kcpy.git .
        mkdir build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || (log_error "Cannot detect CPU count"; exit 1))"
        sudo make install || sudo cp kcpy /usr/local/bin/kcpy
    )
    log_info "kcpy built and installed"
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
    local tools=("zig" "gcc" "clang" "make" "just" "gitleaks" "kcpy" "shellcheck" "pre-commit" "buf")
    log_info "Installed tools:"
    for tool in "${tools[@]}"; do
        if tool_exists "$tool"; then
            log_info "  ✓ ${tool}: $(${tool} --version 2>&1 | head -1 | cut -c1-80)"
        else
            log_warn "  ✗ ${tool}: not found"
        fi
    done
}
