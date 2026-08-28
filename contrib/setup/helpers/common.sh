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

# ── Platform detection ────────────────────────────────────────────────────────
# Single source of truth for OS/arch — used by callers that need it.
source "${SCRIPT_DIR}/../../platform.sh"

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
#   read_tool_version "zig"       → "0.17.0-dev.1770+5d7cf3f34"
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

# Read all package identifiers for a package manager, one per line.
# Usage: read_packages "apt"
read_packages() {
    local manager="$1"

    if [ ! -f "$TOOL_VERSIONS" ]; then
        log_error "Tool versions file missing: ${TOOL_VERSIONS}"
        exit 1
    fi

    python3 -c "
import json, sys
try:
    data = json.load(open('${TOOL_VERSIONS}'))
    packages = data.get('packages', {}).get('${manager}')
    if not isinstance(packages, list):
        sys.exit(1)
    print('\\n'.join(packages))
except (json.JSONDecodeError, Exception):
    sys.exit(1)
" 2>/dev/null || {
        log_error "Package list not defined for packages.${manager} in ${TOOL_VERSIONS}"
        exit 1
    }
}

# Read zig version (alias for tool-versions.json).
# Usage: read_zig_version
read_zig_version() {
    read_tool_version "zig"
}

# ── Platform detection ────────────────────────────────────────────────────────
# Returns: linux-x86, linux-arm, macos-x86, macos-arm, windows-x86, windows-arm
get_platform_key() {
    local os arch
    os="$(tk_os)"
    arch="$(tk_arch)"

    case "${os}-${arch}" in
        linux-x86)    echo "linux-x86" ;;
        linux-arm)    echo "linux-arm" ;;
        macos-x86)    echo "macos-x86" ;;
        macos-arm)    echo "macos-arm" ;;
        windows-x86)  echo "windows-x86" ;;
        windows-arm)  echo "windows-arm" ;;
        *)
            log_error "Unsupported platform: ${os}-${arch}"
            exit 1
            ;;
    esac
}

# ── Tool installers ───────────────────────────────────────────────────────────

# Install PowerShell Core for setup tooling that is shared across platforms.
ensure_pwsh() {
    if tool_exists pwsh; then
        log_info "PowerShell already installed: $(pwsh --version 2>&1 | head -1)"
        return 0
    fi

    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$os" in
        linux)
            if [ -d /snap/bin ]; then
                persist_path_entry /snap/bin "Snap"
            fi
            if ! command -v snap &>/dev/null; then
                log_info "Installing snapd for PowerShell..."
                sudo apt-get update -qq
                sudo apt-get install -y --no-install-recommends snapd
            fi
            if [ -d /snap/bin ]; then
                persist_path_entry /snap/bin "Snap"
            fi
            log_info "Installing PowerShell Core via snap..."
            sudo snap install powershell --classic
            ;;
        darwin)
            if ! command -v brew &>/dev/null; then
                log_error "Homebrew is required to install PowerShell on macOS"
                return 1
            fi
            log_info "Installing PowerShell Core via Homebrew..."
            brew install --cask powershell
            ;;
        *)
            log_error "Unsupported OS for PowerShell installation: ${os}"
            return 1
            ;;
    esac

    if ! tool_exists pwsh; then
        log_error "PowerShell installation completed without a usable pwsh"
        return 1
    fi
    log_info "PowerShell installed: $(pwsh --version 2>&1 | head -1)"
}

# Install Zig via install-zig.py (uses versions.zig from tool-versions.json)
# Captures install-zig.py's own [install] line so we never guess the path.
# Auto-appends PATH to .bashrc/.zshrc so no manual copy-paste is needed.
ensure_zig() {
    local zig_version
    zig_version="$(read_tool_version "zig")"

    # Derive cleanup prefix from get_platform_key() so we only remove matching dirs.
    local platform_key cleanup_prefix
    platform_key="$(get_platform_key)"
    case "$platform_key" in
        linux-x86)  cleanup_prefix="zig-x86_64-linux-" ;;
        linux-arm)  cleanup_prefix="zig-aarch64-linux-" ;;
        macos-x86)  cleanup_prefix="zig-x86_64-macos-" ;;
        macos-arm)  cleanup_prefix="zig-aarch64-macos-" ;;
        *)          log_error "Unsupported platform key: ${platform_key}" ; exit 1 ;;
    esac

    # Remove any previously installed zig version before installing the new one.
    for dir in "${HOME}/.local/${cleanup_prefix}"*; do
        [ -d "$dir" ] || continue
        log_info "Cleaning old zig installation: $dir"
        rm -rf "$dir"
    done

    # Capture install-zig.py's full output to derive the actual install dir.
    # Use the helpers directory directly — lane scripts may overwrite
    # SCRIPT_DIR after sourcing common.sh, breaking this call.
    local install_output
    install_output="$(python3 "${SCRIPT_DIR%/helpers}/helpers/install-zig.py" \
        "${zig_version}" \
        --install-root "${HOME}/.local" \
        --cache-root "${HOME}/.cache" 2>&1)"
    log_info "$install_output"

    # Parse install_dir from the [install] line.
    local install_dir
    install_dir="$(echo "$install_output" | sed -n 's/^\[install\] .* -> \(.*\)$/\1/p')"
    if [ -z "$install_dir" ]; then
        log_error "Could not derive install_dir from install-zig.py output"
        exit 1
    fi

    # Export in current shell.
    export PATH="${install_dir}:${PATH}"
    log_info "Zig installed to ${install_dir}"

    # Persist PATH to shell rc file (.bashrc or .zshrc) — like rustup does.
    local rc_file
    case "$(basename "${SHELL:-}")" in
        bash) rc_file="${HOME}/.bashrc" ;;
        zsh)  rc_file="${HOME}/.zshrc" ;;
    esac
    if [ -z "${rc_file:-}" ] && [ -f "${HOME}/.bashrc" ]; then
        rc_file="${HOME}/.bashrc"
    elif [ -z "${rc_file:-}" ] && [ -f "${HOME}/.zshrc" ]; then
        rc_file="${HOME}/.zshrc"
    fi
    if [ -n "${rc_file:-}" ] && [ -f "$rc_file" ]; then
        local marker="# Hermes setup: Zig PATH for ${install_dir}"
        if ! grep -qF "$marker" "$rc_file" 2>/dev/null; then
            printf '\n%s\nexport PATH="%s:${PATH}"\n' "$marker" "$install_dir" >> "$rc_file"
            log_info "Added Zig PATH export to ${rc_file}"
        else
            log_info "Zig PATH already present in ${rc_file}"
        fi
    fi
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

# Install the CBMC proof toolchain from the official release packages.
# CBMC publishes Ubuntu/architecture-specific debs and Litani publishes a
# Debian package.  These tools are only required by SECURITY=on Linux setup.
ensure_cbmc_toolchain() {
    if ! command -v apt-get &>/dev/null || ! command -v curl &>/dev/null; then
        log_error "CBMC security setup requires apt-get and curl on Linux"
        return 1
    fi

    local ubuntu_version cbmc_asset cbmc_url litani_url tmpdir
    ubuntu_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
    case "${ubuntu_version}" in
        22.04) cbmc_asset="ubuntu-22.04-cbmc-" ;;
        24.04)
            case "$(dpkg --print-architecture)" in
                amd64) cbmc_asset="ubuntu-24.04-cbmc-" ;;
                arm64) cbmc_asset="ubuntu-24.04-arm64-cbmc-" ;;
                *) log_error "Unsupported Debian architecture for CBMC: $(dpkg --print-architecture)"; return 1 ;;
            esac
            ;;
        *)
            log_error "Unsupported Ubuntu version for CBMC packages: ${ubuntu_version} (expected 22.04 or 24.04)"
            return 1
            ;;
    esac

    if command -v cbmc &>/dev/null && command -v litani &>/dev/null; then
        log_info "CBMC and Litani already installed"
    else
        log_info "Resolving CBMC and Litani packages from their official release pages..."
        tmpdir="$(mktemp -d)"
        cbmc_url="$(curl -fsSL https://api.github.com/repos/diffblue/cbmc/releases/latest | \
            python3 -c 'import json, sys; prefix=sys.argv[1]; assets=json.load(sys.stdin)["assets"]; matches=[a["browser_download_url"] for a in assets if a["name"].startswith(prefix) and a["name"].endswith("-Linux.deb")]; print(matches[0] if len(matches) == 1 else "")' "${cbmc_asset}")"
        litani_url="$(curl -fsSL https://api.github.com/repos/awslabs/aws-build-accumulator/releases/latest | \
            python3 -c 'import json, sys; assets=json.load(sys.stdin)["assets"]; matches=[a["browser_download_url"] for a in assets if a["name"].startswith("litani-") and a["name"].endswith(".deb")]; print(matches[0] if len(matches) == 1 else "")')"
        if [ -z "${cbmc_url}" ] || [ -z "${litani_url}" ]; then
            log_error "Could not find matching CBMC or Litani release package"
            rm -rf "${tmpdir}"
            return 1
        fi
        curl -fsSL "${cbmc_url}" -o "${tmpdir}/cbmc.deb"
        curl -fsSL "${litani_url}" -o "${tmpdir}/litani.deb"
        sudo apt-get install -y --no-install-recommends \
            "${tmpdir}/cbmc.deb" "${tmpdir}/litani.deb" universal-ctags
        rm -rf "${tmpdir}"
    fi

    if ! command -v cbmc &>/dev/null || ! command -v litani &>/dev/null; then
        log_error "CBMC security tools were not found after installation"
        return 1
    fi

    if ! python3 -m pip show cbmc-viewer &>/dev/null || \
       ! python3 -m pip show cbmc-starter-kit &>/dev/null; then
        log_info "Installing CBMC Python tools..."
        # Ubuntu's system Python is commonly marked externally managed.  The
        # recommended installation is system-wide, so explicitly authorize the
        # pip install rather than silently falling back to an untracked venv.
        python3 -m pip install --break-system-packages --upgrade \
            cbmc-viewer cbmc-starter-kit
    else
        log_info "CBMC Python tools already installed"
    fi
}

# Install kcov from source (SimonKagstrom/kcov)
# Returns 1 (graceful skip) if the repo is unavailable — not all hosts
# have internet access to GitHub, and the repo is optional for coverage.
ensure_kcov() {
    if tool_exists kcov; then
        log_info "kcov already installed"
        return 0
    fi

    log_info "Building kcov from source..."
    local kcov_rc=0
    (
        set +e  # Don't abort on clone/build failure — repo may be unavailable
        cd "$(mktemp -d)"
        if ! git clone --depth 1 https://github.com/SimonKagstrom/kcov.git . 2>/dev/null; then
            log_warn "kcov: SimonKagstrom/kcov repo unavailable — skipping"
            return 1
        fi
        # Install the package-manager prerequisites from the manifest.
        if command -v apt-get &>/dev/null; then
            local -a apt_packages=()
            mapfile -t apt_packages < <(read_packages "apt")
            sudo apt-get install -y --no-install-recommends \
                "${apt_packages[@]}" 2>/dev/null || true
        fi
        mkdir build && cd build
        cmake .. -DCMAKE_BUILD_TYPE=Release || { log_warn "kcov cmake failed"; return 1; }
        if ! make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)"; then
            log_warn "kcov build failed — skipping"
            return 1
        fi
        sudo make install || sudo cp kcov /usr/local/bin/kcov
        return 0
    ) || kcov_rc=$?

    if [ $kcov_rc -eq 0 ]; then
        log_info "kcov built and installed"
    else
        return 1
    fi
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

    log_info "Installing pre-commit..."
    if command -v pipx &>/dev/null; then
        pipx install pre-commit
        export PATH="${HOME}/.local/bin:${PATH}"
    elif command -v pip3 &>/dev/null; then
        pip3 install --user pre-commit
        export PATH="${HOME}/.local/bin:${PATH}"
    elif command -v pip &>/dev/null; then
        pip install --user pre-commit
        export PATH="${HOME}/.local/bin:${PATH}"
    elif command -v python3 &>/dev/null; then
        python3 -m pip install --user pre-commit
        export PATH="${HOME}/.local/bin:${PATH}"
    else
        log_warn "No pip found for pre-commit — skipping"
        return 1
    fi
}

# Add a user tool directory to the current shell and future shells.
persist_path_entry() {
    local path_entry="$1"
    local label="$2"

    case ":${PATH}:" in
        *":${path_entry}:"*) ;;
        *) export PATH="${path_entry}:${PATH}" ;;
    esac

    local rc_file=""
    case "$(basename "${SHELL:-}")" in
        bash) rc_file="${HOME}/.bashrc" ;;
        zsh)  rc_file="${HOME}/.zshrc" ;;
    esac
    if [ -z "$rc_file" ] && [ -f "${HOME}/.bashrc" ]; then
        rc_file="${HOME}/.bashrc"
    elif [ -z "$rc_file" ] && [ -f "${HOME}/.zshrc" ]; then
        rc_file="${HOME}/.zshrc"
    fi

    if [ -n "$rc_file" ] && [ -f "$rc_file" ]; then
        local marker="# Tickoni setup: ${label} PATH"
        if ! grep -qF "$marker" "$rc_file" 2>/dev/null; then
            printf '\n%s\nexport PATH="%s:$PATH"\n' "$marker" "$path_entry" >> "$rc_file"
            log_info "Added ${label} PATH export to ${rc_file}"
        fi
    fi
}

activate_go_paths() {
    if [ -d "/usr/local/go/bin" ]; then
        persist_path_entry "/usr/local/go/bin" "Go"
    fi
    if [ -d "${HOME}/go/bin" ]; then
        persist_path_entry "${HOME}/go/bin" "Go user binaries"
    fi
}

# Install Go (Linux only — macOS uses brew, winget handles Windows)
ensure_go() {
    if tool_exists go; then
        log_info "go already installed: $(go version 2>&1 | head -1)"
        return 0
    fi

    activate_go_paths
    if tool_exists go; then
        log_info "go already installed: $(go version 2>&1 | head -1)"
        return 0
    fi

    log_info "Installing Go..."
    local version
    version="$(read_tool_version "go")"
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install go || { log_warn "brew install go failed"; return 1; }
    elif [ "$os" = "linux" ] && command -v apt-get &>/dev/null; then
        local arch
        case "$(uname -m)" in
            x86_64) arch="amd64" ;;
            aarch64|arm64) arch="arm64" ;;
            *) log_warn "Unsupported arch $(uname -m) for Go"; return 1 ;;
        esac
        local tmpdir
        tmpdir="$(mktemp -d)"
        if curl -sSfL "https://go.dev/dl/go${version}.linux-${arch}.tar.gz" -o "${tmpdir}/go.tar.gz" 2>/dev/null; then
            sudo rm -rf /usr/local/go
            sudo tar -C /usr/local -xzf "${tmpdir}/go.tar.gz"
            activate_go_paths
            log_info "Go ${version} installed to /usr/local/go"
            rm -rf "${tmpdir}"
            return 0
        fi
        rm -rf "${tmpdir}"
        log_warn "Go download failed — skipping"
        return 1
    else
        log_warn "No package manager or download method for Go — skipping"
        return 1
    fi
}

# Install buf — prefer brew, then go install, then GitHub binary
ensure_buf() {
    activate_go_paths
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
    if ! tool_exists buf; then
        # Linux: ensure Go is available for go install
        if ! tool_exists go; then
            ensure_go || true
        fi
        if tool_exists go; then
            go install github.com/bufbuild/buf/cmd/buf@latest
            activate_go_paths
        fi
    fi
    if ! tool_exists buf && command -v apt-get &>/dev/null; then
        sudo apt-get install -y buf || log_warn "apt install buf failed"
    fi
    if ! tool_exists buf; then
        # Fallback: download buf binary from GitHub releases
        local arch
        case "$(uname -m)" in
            x86_64) arch="x86_64" ;;
            aarch64|arm64) arch="aarch64" ;;
            *) log_warn "Unsupported arch $(uname -m) for buf — skipping"; return 1 ;;
        esac
        local version
        version="$(read_tool_version "buf" 2>/dev/null || echo "1.57.0")"
        local tmpdir
        tmpdir="$(mktemp -d)"
        if curl -sSfL "https://github.com/bufbuild/buf/releases/download/v${version}/buf-Linux-${arch}" \
            -o "${tmpdir}/buf" 2>/dev/null && sudo cp "${tmpdir}/buf" /usr/local/bin/buf && sudo chmod 755 /usr/local/bin/buf; then
            log_info "buf ${version} installed via binary"
            rm -rf "${tmpdir}"
            return 0
        fi
        rm -rf "${tmpdir}"
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
