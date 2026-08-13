#!/usr/bin/env bash
# common.sh — shared POSIX helper functions for contrib/setup/ lane scripts.
# Source this from your lane script (linux-x86-gcc.sh, macos-x86.sh, etc.)
#
# Version source of truth: contrib/setup/tool-versions.json
#
#   versions.*  — explicit version pins for tools whose version matters for
#                 install behavior (download URLs, package names, build scripts).
#                 Read with read_tool_version (universal) or read_compiler_version
#                 (platform-specific).
#
#   packages.*  — package manager identifiers for tools where "latest" from
#                 the manager is fine (winget IDs, apt/brew package names, etc.).
#                 Read with read_package.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"
TOOL_VERSIONS="${REPO_ROOT}/contrib/setup/tool-versions.json"

log_info()  { printf '[setup] %s\n' "$*" ; }
log_warn()  { printf '[setup] WARN: %s\n' "$*" >&2 ; }
log_error() { printf '[setup] ERROR: %s\n' "$*" >&2 ; }

# Check if a command exists on PATH
tool_exists() { command -v "$1" &>/dev/null ; }

# ── Read version from versions section ────────────────────────────────────────
#
# Universal tools (single version everywhere):
#   read_tool_version "just"      → "1.58.0"
#   read_tool_version "gitleaks"  → "8.30.1"
#   read_tool_version "zig"       → "0.16.0"
#   read_tool_version "openssl"   → "3.6.2"
#
# Usage: read_tool_version "just"
read_tool_version() {
    local tool="$1"

    if [ ! -f "$TOOL_VERSIONS" ]; then
        log_error "Tool versions file missing: ${TOOL_VERSIONS}"
        exit 1
    fi

    local version
    version="$(python3 -c "
import json, sys
try:
    data = json.load(open('${TOOL_VERSIONS}'))
    v = data.get('versions', {}).get('${tool}')
    if isinstance(v, dict):
        v = v.get('version', '')
    if not v:
        sys.exit(1)
    print(v)
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null)" || {
        log_error "Version not defined for '${tool}' in ${TOOL_VERSIONS}"
        exit 1
    }

    echo "$version"
}

# Read platform-specific version (gcc, clang, llvm, msvc).
# Usage: read_compiler_version "clang" "linux-x86"
read_compiler_version() {
    local tool="$1"
    local platform_key="$2"

    if [ ! -f "$TOOL_VERSIONS" ]; then
        log_error "Tool versions file missing: ${TOOL_VERSIONS}"
        exit 1
    fi

    local version
    version="$(python3 -c "
import json, sys
try:
    data = json.load(open('${TOOL_VERSIONS}'))
    v = data.get('versions', {}).get('${tool}', {}).get('${platform_key}')
    if not v:
        sys.exit(1)
    print(v)
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null)" || {
        log_error "Version not defined for ${tool} on ${platform_key}"
        exit 1
    }

    echo "$version"
}

# Read package manager identifier (winget ID, apt/brew name, etc.).
# Usage: read_package "winget" "python"   → "Python.Python.3.12"
# Usage: read_package "apt"    "cmake"    → "cmake"
# Usage: read_package "brew"   "gcc"      → "gcc"
#
# Note: for apt/brew, the "package name" IS the identifier.
#       For winget, this maps to the full winget package ID.
read_package() {
    local manager="$1"
    local tool="$2"

    if [ ! -f "$TOOL_VERSIONS" ]; then
        log_error "Tool versions file missing: ${TOOL_VERSIONS}"
        exit 1
    fi

    # For apt/brew, the package name IS the tool name (they don't have a
    # separate "identifier" mapping — just a list of package names to install).
    if [ "$manager" = "apt" ] || [ "$manager" = "brew" ]; then
        # Check if the tool is in the packages array
        local in_array
        in_array="$(python3 -c "
import json, sys
try:
    data = json.load(open('${TOOL_VERSIONS}'))
    mgr = data.get('packages', {}).get('${manager}', [])
    if not isinstance(mgr, list) or '${tool}' not in mgr:
        sys.exit(1)
    print('ok')
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null)" || {
            log_error "Package '${tool}' not in packages.${manager} in ${TOOL_VERSIONS}"
            exit 1
        }
        echo "$tool"
        return 0
    fi

    # For winget/pip: read from the mapping object
    local value
    value="$(python3 -c "
import json, sys
try:
    data = json.load(open('${TOOL_VERSIONS}'))
    mgr = data.get('packages', {}).get('${manager}', {})
    if not isinstance(mgr, dict):
        sys.exit(1)
    v = mgr.get('${tool}')
    if not v:
        sys.exit(1)
    print(v)
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null)" || {
        log_error "Package mapping not defined for ${manager}.${tool} in ${TOOL_VERSIONS}"
        exit 1
    }

    echo "$value"
}

# Read zig version (alias for tool-versions.json).
# Usage: read_zig_version
read_zig_version() {
    read_tool_version "zig"
}

# ── Platform detection ────────────────────────────────────────────────────────
# Returns: linux-x86, linux-arm, macos-x86, macos-arm, windows-x86, windows-arm
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

# ── Tool installers ───────────────────────────────────────────────────────────

# Install Zig via install-zig.py (uses versions.zig from tool-versions.json)
ensure_zig() {
    local zig_version
    zig_version="$(read_tool_version "zig")"
    local zig_bin="${HOME}/.local/zig/zig"

    if [ -f "$zig_bin" ] && "${zig_bin}" --version &>/dev/null; then
        log_info "Zig ${zig_version} already installed"
        export PATH="${HOME}/.local/zig:${PATH}"
        return 0
    fi

    log_info "Installing Zig ${zig_version}..."
    python3 "${SCRIPT_DIR}/helpers/install-zig.py" \
        --version "${zig_version}" \
        --install-root "${HOME}/.local" \
        --cache-root "${HOME}/.cache"
    export PATH="${HOME}/.local/zig:${PATH}"
    log_info "Zig installed to ${HOME}/.local/zig"
}

# Install gitleaks (pinned version from tool-versions.json)
GITLEAKS_ORG="gitleaks"

ensure_gitleaks() {
    local version
    version="$(read_tool_version "gitleaks")"

    if tool_exists gitleaks; then
        log_info "gitleaks ${version} already installed"
        return 0
    fi

    log_info "Installing gitleaks ${version}..."
    local os arch asset

    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
        x86_64)    arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) echo "unsupported arch: $(uname -m)" >&2; return 1 ;;
    esac

    case "${os}" in
        linux)   asset="gitleaks_${version}_linux_${arch}.tar.gz" ;;
        darwin)
            if [ "$arch" = "arm64" ]; then
                asset="gitleaks_${version}_darwin_arm64.tar.gz"
            else
                asset="gitleaks_${version}_darwin_x64.tar.gz"
            fi
            ;;
        *)
            log_warn "Unsupported OS ${os} — skipping gitleaks"
            return 1
            ;;
    esac

    local tmpdir
    tmpdir="$(mktemp -d)"
    curl -sSfL "https://github.com/${GITLEAKS_ORG}/gitleaks/releases/download/v${version}/${asset}" \
        -o "${tmpdir}/gitleaks.tar.gz"
    tar -xzf "${tmpdir}/gitleaks.tar.gz" -C "${tmpdir}"
    sudo cp "${tmpdir}/gitleaks" /usr/local/bin/gitleaks
    sudo chmod 755 /usr/local/bin/gitleaks
    rm -rf "${tmpdir}"
    log_info "gitleaks ${version} installed"
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

# Install shellcheck (latest from system package manager)
ensure_shellcheck() {
    if tool_exists shellcheck; then
        log_info "shellcheck already installed"
        return 0
    fi

    log_info "Installing shellcheck..."
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [ "$os" = "linux" ] && command -v apt-get &>/dev/null; then
        sudo apt-get install -y shellcheck
    elif [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install shellcheck
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

# Install buf — prefer brew (handles all deps including git) then go install
ensure_buf() {
    if tool_exists buf; then
        log_info "buf already installed"
        return 0
    fi

    log_info "Installing buf..."
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install buf || log_warn "brew install buf failed"
    fi
    if ! tool_exists buf && command -v go &>/dev/null; then
        go install github.com/bufbuild/buf/cmd/buf@latest
        export PATH="${HOME}/go/bin:${PATH}"
    fi
    if ! tool_exists buf && command -v apt-get &>/dev/null; then
        # Linux: try apt first, then go
        sudo apt-get install -y buf || log_warn "apt install buf failed"
    fi
    if ! tool_exists buf; then
        log_warn "No package manager found for buf — skipping"
        return 1
    fi
}

# Install just — uses versions.just from tool-versions.json
ensure_just() {
    local version
    version="$(read_tool_version "just")"

    if tool_exists just; then
        log_info "just ${version} already installed"
        return 0
    fi

    log_info "Installing just ${version}..."
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install just || log_warn "brew install just failed — falling back"
    elif command -v apt-get &>/dev/null; then
        curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
    else
        log_warn "No package manager found for just — skipping"
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
