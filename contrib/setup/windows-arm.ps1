# windows-arm.ps1 — Setup Windows ARM64
# Requires: PowerShell 5.1+ or PowerShell 7+
# Note: on Windows ARM, we install x86_64 Zig binary (runs under emulation)
Set-ErrorActionPreference Stop

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

# Source helpers
. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows ARM64 setup starting..."

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

# 4. Zig (install x86_64 binary — runs under Windows ARM emulation)
log-info "Installing Zig (x86_64 binary via emulation)..."
python3 (Join-Path $scriptDir "helpers\install-zig.py") `
    --target "x86_64-windows" `
    --install-root (Join-Path $env:LOCALAPPDATA "Programs") `
    --cache-root (Join-Path $env:LOCALAPPDATA "zig") `
    --user-path
log-info "Zig installed (x86_64 binary)"

# 5. MSVC build tools (for llama.cpp / Windows-specific builds)
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    log-info "Installing Visual Studio Build Tools..."
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        log-info "Installing VS Build Tools via chocolatey..."
        choco install visualstudio2022buildtools -y --params "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.VisualStudio.2022.BuildTools -e
    }
}

# 6. Firedancer deps
$env:CC = "clang"
$env:CXX = "clang++"
log-info "Installing Firedancer dependencies (CC=clang, CXX=clang++)..."
if (Test-Path (Join-Path $repoRoot "deps.sh")) {
    & bash (Join-Path $repoRoot "deps.sh") check
    & bash (Join-Path $repoRoot "deps.sh") fetch install
} else {
    log-warn "deps.sh not found — skipping Firedancer deps"
}

# 7. Print summary
log-info "Windows ARM64 setup complete"
log-info "Installed tools:"
if (Get-Command clang -ErrorAction SilentlyContinue) {
    log-info "  clang: $(clang --version | Select-Object -First 1)"
}
if (Get-Command zig -ErrorAction SilentlyContinue) {
    log-info "  zig: $(zig version 2>&1) (x86_64 binary under emulation)"
}
if (Get-Command just -ErrorAction SilentlyContinue) {
    log-info "  just: $(just --version 2>&1)"
}
if (Get-Command cl -ErrorAction SilentlyContinue) {
    log-info "  cl: MSVC found"
}
log-info "NOTE: Zig is x86_64 binary — builds will run under Windows ARM x64 emulation"
