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
$platform_key = get-windows-platform-key
$clang_version = read-compiler-version "clang" $platform_key
if ($clang_version) {
    log-info "Installing LLVM/Clang ${clang_version}..."
    scoop install llvm@"${clang_version}"
} else {
    log-info "Installing LLVM (latest)..."
    scoop install llvm
}

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

# 5. MSVC build tools
$msvc_version = read-compiler-version "msvc" $platform_key
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    log-info "Installing Visual Studio Build Tools (MSVC ${msvc_version})..."
    if (Test-Path "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat") {
        log-info "Visual Studio Build Tools found"
    } elseif ($msvc_version) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            log-info "Installing VS Build Tools ${msvc_version} via chocolatey..."
            choco install visualstudio2022buildtools -y --version "${msvc_version}.*" --params "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
        } else {
            log-info "Installing VS Build Tools ${msvc_version} via winget..."
            winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --version "*${msvc_version}*" -e
        }
    } else {
        log-warn "No MSVC version in JSON — trying winget without version pin"
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Microsoft.VisualStudio.2022.BuildTools -e
        } else {
            log-warn "No package manager found for VS Build Tools — build may fail"
        }
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
