# windows-x86.ps1 — Setup Windows x86_64
# Usage:
#   .\windows-x86.ps1              # default: install all deps + LLM tooling
#   .\windows-x86.ps1 -NoLLM       # skip LLM tooling (llama.cpp build)
# Package manager: winget (preferred) → choco → auto-install winget

param([switch]$NoLLM)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows x86_64 setup starting..."

# ── 0. Package manager (winget or choco) ─────────────────────────────────────
function Get-PackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return "winget" }
    if (Test-Path (Join-Path $env:ProgramData "chocolatey\bin\choco.exe")) { return "choco" }
    if (Get-Command choco -ErrorAction SilentlyContinue) { return "choco" }

    # Install winget via Microsoft installer
    log-info "No package manager — installing winget..."
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
        return "winget"
    }
    log-error "Cannot install winget"
    exit 1
}

$pm = Get-PackageManager
log-info "Using package manager: $pm"

function Install-Dep {
    param([string]$Choco, [string]$WingetId)
    if ($pm -eq "choco") {
        choco install $Choco -y --no-progress
    } else {
        winget install --id $WingetId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
}

# ── 1. Core packages ─────────────────────────────────────────────────────────
log-info "Installing core packages..."
Install-Dep -Choco "git" -WingetId "Git.Git"
Install-Dep -Choco "cmake" -WingetId "CMake.CMake"
Install-Dep -Choco "ninja" -WingetId "Ninja-build.Ninja"
Install-Dep -Choco "zstd" -WingetId "Facebook.zstd"
Install-Dep -Choco "python3" -WingetId "Python.Python.3.12"
Install-Dep -Choco "gitleaks" -WingetId "ZioZio.gitleaks"
Install-Dep -Choco "shellcheck" -WingetId "Koalaman.shellcheck"
Install-Dep -Choco "pre-commit" -WingetId "PreCommit.PreCommit"
Install-Dep -Choco "buf" -WingetId "bufbuild.buf"

# ── 2. just ──────────────────────────────────────────────────────────────────
if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
    log-info "Installing just..."
    curl -sSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
}

# ── 3. LLVM (Clang compiler) ─────────────────────────────────────────────────
$platform_key = get-windows-platform-key
$clang_version = read-compiler-version "clang" $platform_key
log-info "Installing LLVM/Clang ${clang_version}..."
Install-Dep -Choco "llvm" -WingetId "LLVM.LLVM.$clang_version"

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
$msvc_version = read-compiler-version "msvc" $platform_key
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    log-info "Installing Visual Studio Build Tools (MSVC ${msvc_version})..."
    if (Test-Path "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat") {
        log-info "Visual Studio Build Tools found"
    } elseif ($pm -eq "choco") {
        choco install visualstudio2022buildtools -y --version "${msvc_version}.*" --params "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
    } else {
        winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --version "*${msvc_version}*" -e
    }
}

# ── 6. Firedancer deps ───────────────────────────────────────────────────────
$env:CC = "clang"
$env:CXX = "clang++"
log-info "Installing Firedancer dependencies (CC=clang, CXX=clang++)..."
if (Test-Path (Join-Path $repoRoot "deps.sh")) {
    & bash (Join-Path $repoRoot "deps.sh") check
    & bash (Join-Path $repoRoot "deps.sh") fetch install
} else {
    log-warn "deps.sh not found — skipping Firedancer deps"
}

# ── 7. LLM tooling (optional) ────────────────────────────────────────────────
if (-not $NoLLM) {
    log-info "Installing LLM tooling (llama.cpp build deps: MinGW-w64)..."
    Install-Dep -Choco "mingw" -WingetId "BrechtSanders.WinLibs.POSIX.UCRT"
    log-info "LLM tooling installed"
} else {
    log-info "Skipping LLM tooling (-NoLLM)"
}

# ── 8. Summary ───────────────────────────────────────────────────────────────
log-info "Windows x86_64 setup complete"
log-info "Tools:"
foreach ($tool in @("clang", "zig", "just", "cl")) {
    $ver = (Get-Command $tool -ErrorAction SilentlyContinue).Version
    if ($ver) { log-info "  $tool: $ver" }
}
