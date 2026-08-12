# windows-x86.ps1 — Setup Windows x86_64
# Requires: PowerShell 5.1+ or PowerShell 7+
Set-ErrorActionPreference Stop

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

# Source helpers
. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows x86_64 setup starting..."

# 1. Scoop (install if missing)
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    log-info "Installing Scoop..."
    Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')
}

# 2. Core packages
log-info "Installing Scoop packages..."
scoop install \
    git cmake ninja zstd \
    python3 \
    just \
    gitleaks \
    shellcheck \
    pre-commit \
    buf

# 3. LLVM (Clang compiler)
log-info "Installing LLVM..."
scoop install llvm

# Add LLVM to PATH
$llvmPath = (Get-Command clang -ErrorAction SilentlyContinue).Source | Split-Path
if (-not $llvmPath) {
    $llvmPath = (Get-ChildItem "C:\Program Files\LLVM\bin" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if ($llvmPath) {
    $env:PATH = "$llvmPath;$env:PATH"
    log-info "LLVM added to PATH: $llvmPath"
}

# 4. Zig
ensure-zig

# 5. MSVC build tools (via VS Build Tools or chocolatey)
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    log-info "Installing Visual Studio Build Tools..."
    if (Test-Path "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat") {
        # VS Build Tools already installed
        log-info "Visual Studio Build Tools found"
    } else {
        # Try chocolatey as fallback
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            log-info "Installing VS Build Tools via chocolatey..."
            choco install visualstudio2022buildtools -y --params "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
        } else {
            log-info "chocolatey not available — attempting winget..."
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                winget install --id Microsoft.VisualStudio.2022.BuildTools -e
            } else {
                log-warn "No package manager found for VS Build Tools — build may fail"
            }
        }
    }
}

# 6. Firedancer deps
$env:CC = "clang"
$env:CXX = "clang++"
$logInfo = ${function:log-info}
function ensure_firedancer_deps_windows {
    log-info "Installing Firedancer dependencies (CC=clang, CXX=clang++)..."
    if (Test-Path (Join-Path $repoRoot "contrib\deps.sh")) {
        & bash (Join-Path $repoRoot "contrib\deps.sh") check
        & bash (Join-Path $repoRoot "contrib\deps.sh") fetch install
    } else {
        log-warn "contrib/deps.sh not found — skipping Firedancer deps"
    }
}

# 7. Print summary
log-info "Windows x86_64 setup complete"
log-info "Installed tools:"
if (Get-Command clang -ErrorAction SilentlyContinue) {
    log-info "  clang: $(clang --version | Select-Object -First 1)"
}
if (Get-Command zig -ErrorAction SilentlyContinue) {
    log-info "  zig: $(zig version 2>&1)"
}
if (Get-Command just -ErrorAction SilentlyContinue) {
    log-info "  just: $(just --version 2>&1)"
}
if (Get-Command cl -ErrorAction SilentlyContinue) {
    log-info "  cl: MSVC found"
}
