# windows-x86.ps1 — Setup Windows x86_64
# Usage:
#   .\windows-x86.ps1              # default: install all deps + LLM tooling
#   .\windows-x86.ps1 -NoLLM       # skip LLM tooling (llama.cpp build)
#   .\windows-x86.ps1 -Security -NoLLM  # install gitleaks, skip LLM
# Package manager: winget ONLY. If winget is missing, auto-install it.
# Note: OpenSSL uses native MSVC target (msvc-x86_64), no MinGW-w64/MSYS2 needed.

param([switch]$Security, [switch]$NoLLM)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows x86_64 setup starting..."

# ── 0. Winget (only package manager — auto-install if missing) ────────────────
if (Get-Command winget -ErrorAction SilentlyContinue) {
    log-info "winget already installed"
} else {
    log-info "winget not found — installing..."
    $temp = Join-Path $env:TEMP "winget-msi"
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $url = "https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $zip = Join-Path $temp "winget.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $temp -Force
    $msix = Get-ChildItem -Path $temp -Filter "*.msixbundle" -Recurse | Select-Object -First 1
    if ($msix) {
        Add-AppxPackage -Path $msix.FullName
        $env:PATH = (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps") + ";$env:PATH"
        log-info "winget installed"
    } else {
        log-error "Failed to install winget"
        exit 1
    }
}

# Install winget package by name from tool-versions.json
function Install-Package {
    param([string]$Name)
    $wingetId = read-package "winget" $Name
    log-info "Installing ${Name} (${wingetId})..."
    winget install --id $wingetId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
}

# ── 1. Core packages ─────────────────────────────────────────────────────────
log-info "Installing core packages..."
Install-Package "git"
Install-Package "cmake"
Install-Package "ninja"
Install-Package "zstd"
Install-Package "python"
Install-Package "shellcheck"
Install-Package "pre-commit"
Install-Package "buf"

# ── 1b. Security tools (opt-in via -Security flag) ──────────────────────────
if ($Security) {
    ensure-gitleaks
} else {
    log-info "Skipping security tools (pass -Security to install)"
}

# ── 2. just ──────────────────────────────────────────────────────────────────
if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
    log-info "Installing just..."
    ensure-just
}

# ── 3. LLVM (Clang compiler) ─────────────────────────────────────────────────
$platform_key = get-windows-platform-key
$clang_version = read-compiler-version "clang" $platform_key
log-info "Installing LLVM/Clang ${clang_version}..."
Install-Package "llvm"

$llvmPath = (Get-Command clang -ErrorAction SilentlyContinue).Source | Split-Path
if (-not $llvmPath) {
    $llvmPath = (Get-ChildItem "C:\Program Files\LLVM\bin" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}
if ($llvmPath) {
    $env:PATH = "$llvmPath;$env:PATH"
    log-info "LLVM added to PATH: $llvmPath"
}

# ── 4. Zig ───────────────────────────────────────────────────────────────────
ensure-zig

# ── 5. MSVC build tools ──────────────────────────────────────────────────────
log-info "Installing Visual Studio Build Tools..."
Install-Package "vs-build-tools"

# ── 6. OpenSSL 3.6.2 — build from source via Git Bash (native MSVC target)
# Git for Windows includes: bash, perl (Strawberry), make.
# VS Build Tools provides: cl.exe, nmake.
# OpenSSL 3.x supports msvc-x86_64 target natively — no MinGW-w64.
# No MSYS2, no gcc, no cross-compiler needed.
if (-not (Test-Path (Join-Path $repoRoot "opt\lib\libssl.a"))) {
    $gitBash = "${env:ProgramFiles}\Git\usr\bin\bash.exe"
    if (-not (Test-Path $gitBash)) {
        $gitBash = "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
    }
    if (Test-Path $gitBash) {
        log-info "Building OpenSSL 3.6.2 via Git Bash (MSVC target)..."
        $openssl_script = Join-Path $repoRoot 'contrib/setup/install-openssl.sh'
        $opt_path = Join-Path $repoRoot 'opt'
        $openssl_posix = & cygpath -u $openssl_script
        $opt_posix = & cygpath -u $opt_path
        & $gitBash -lc "FD_WINDOWS_ARCH=x86_64 bash $openssl_posix --prefix $opt_posix" 2>&1
    } else {
        log-error "Git Bash not found — OpenSSL 3.6.2 cannot be built"
        log-error "Install Git for Windows and rerun setup"
        exit 1
    }
} else {
    log-info "OpenSSL 3.6.2 already installed in ./opt/"
}

# ── 7. LLM tooling (optional) ────────────────────────────────────────────────
if (-not $NoLLM) {
    log-info "Installing LLM tooling (llama.cpp build deps: MinGW-w64)..."
    Install-Package "winlibs"
    log-info "LLM tooling installed"
} else {
    log-info "Skipping LLM tooling (-NoLLM)"
}

# ── 8. Summary ───────────────────────────────────────────────────────────────
log-info "Windows x86_64 setup complete"
log-info "Tools:"
foreach ($tool in @("clang", "zig", "just", "cl")) {
    $ver = (Get-Command $tool -ErrorAction SilentlyContinue).Version
    if ($ver) { log-info "  ${tool}: $ver" }
}
