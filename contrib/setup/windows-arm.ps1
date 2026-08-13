# windows-arm.ps1 — Setup Windows ARM64
# Usage:
#   .\windows-arm.ps1              # default: install all deps + LLM tooling
#   .\windows-arm.ps1 -NoLLM       # skip LLM tooling (llama.cpp build)
#   .\windows-arm.ps1 -Security -NoLLM  # install gitleaks, skip LLM
# Package manager: winget (preferred) → choco → auto-install winget
# Note: Zig uses native aarch64-windows prebuilt binary

param([switch]$Security, [switch]$NoLLM)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..\..")).FullName

. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows ARM64 setup starting..."

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
Install-Dep -Choco "shellcheck" -WingetId "Koalaman.shellcheck"
Install-Dep -Choco "pre-commit" -WingetId "PreCommit.PreCommit"
Install-Dep -Choco "buf" -WingetId "bufbuild.buf"

# ── 1b. Security tools (opt-in via -Security flag) ──────────────────────────
if ($Security) {
    ensure-gitleaks
} else {
    log-info "Skipping security tools (pass -Security to install)"
}

# ── 2. just ──────────────────────────────────────────────────────────────────
if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
    log-info "Installing just..."
    winget install --id just.systems.just --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
}

# ── 3. LLVM (Clang compiler) ─────────────────────────────────────────────────
# detect-windows-arch.sh checks PROCESSOR_ARCHITEW6432 (WOW64) before
# PROCESSOR_ARCHITECTURE. On native ARM64, WOW64 env = AMD64 → returns
# x86_64. Hardcode platform-key for this lane instead.
$platform_key = "windows-arm"
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

# ── 4. Zig (native aarch64-windows) ─────────────────────────────────────────
log-info "Installing Zig (aarch64-windows native)..."
python3 (Join-Path $scriptDir "helpers\install-zig.py") `\
    --target "aarch64-windows" `\
    --install-root (Join-Path $env:LOCALAPPDATA "Programs") `\
    --cache-root (Join-Path $env:LOCALAPPDATA "zig") `\
    --user-path
log-info "Zig installed (aarch64-windows native)"

# ── 5. cpanm (for MSYS2 Perl module installs) ───────────────────────────────
# Strawberry Perl ships a cpanm fat-pack (cpanmin.pl) that is missing
# ExtUtils::Manifest. Always use MSYS2's cpanminus instead — verify it
# works by checking for ExtUtils::Manifest, then install via MSYS2 if
# the first-found cpanm doesn't satisfy it.
function Test-CpanmWorks {
    $msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
    if (Test-Path $msysBash) {
        $result = & $msysBash -lc "perl -MExtUtils::Manifest -e1 2>&1"
        return $LASTEXITCODE -eq 0
    }
    return $false
}

$cpanmFound = Get-Command cpanm -ErrorAction SilentlyContinue
if (-not $cpanmFound) {
    log-info "cpanm not found — installing via MSYS2 pacman...";
    $msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
    if (Test-Path $msysBash) {
        & $msysBash -lc "pacman -S --noconfirm cpanminus" 2>&1 | Out-Null
    }
} elseif (-not (Test-CpanmWorks)) {
    log-info "cpanm found but missing ExtUtils::Manifest (Strawberry Perl fat-pack) — installing MSYS2 cpanminus...";
    $msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
    if (Test-Path $msysBash) {
        & $msysBash -lc "pacman -S --noconfirm cpanminus" 2>&1 | Out-Null
    }
}

# MSYS2 bin is at /usr/bin/cpanm — ensure MSYS2 is in PATH
$msysPath = "$env:SystemDrive\msys64\usr\bin"
if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $msysPath })) {
    $env:PATH = $msysPath + ";" + $env:PATH
}
log-info "cpanm ready for Perl module installs";

# ── 6. MSVC build tools ──────────────────────────────────────────────────────
$msvc_version = read-compiler-version "msvc" $platform_key
if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    log-info "Installing Visual Studio Build Tools (MSVC ${msvc_version})..."
    if ($pm -eq "choco") {
        # choco --version requires exact version — no wildcards. Just install latest.
        choco install visualstudio2022buildtools -y --params "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
    } else {
        winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
}

# ── 7. OpenSSL — install from winget (not from source via deps.sh) ──────────
# deps.sh builds OpenSSL from source; the Makefile passes the Clang path
# (e.g. "C:/Program Files/LLVM/bin/clang") to /usr/bin/sh which splits
# on spaces → Error 127.  Install via winget instead and copy into
# ./opt/ so the Firedancer build finds it.
if (-not (Test-Path (Join-Path $repoRoot "opt\lib\libssl.a"))) {
    log-info "Installing OpenSSL via winget..."
    winget install --id ShiningLight.OpenSSL.Light --exact --accept-package-agreements --accept-source-agreements --disable-interactivity --accept-source-agreements
    # Copy headers and static libs into ./opt/ (where Firedancer build expects them)
    $optInclude = Join-Path $repoRoot "opt\include"
    $optLib     = Join-Path $repoRoot "opt\lib"
    New-Item -ItemType Directory -Force -Path $optInclude\openssl | Out-Null
    New-Item -ItemType Directory -Force -Path $optLib         | Out-Null
    # Find the winget-installed OpenSSL
    $opensslDir = Get-ChildItem -Directory "C:\Program Files\OpenSSL" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $opensslDir) {
        $opensslDir = Get-ChildItem -Directory "C:\Program Files (x86)\OpenSSL" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($opensslDir) {
        Copy-Item -Recurse -Force "$($opensslDir.FullName)\include\openssl\*" "$optInclude\openssl\"
        Copy-Item -Force "$($opensslDir.FullName)\lib\libcrypto-*.a"   "$optLib\" -ErrorAction SilentlyContinue
        Copy-Item -Force "$($opensslDir.FullName)\lib\libssl-*.a"      "$optLib\"   -ErrorAction SilentlyContinue
        log-info "OpenSSL headers and static libs copied to ./opt/"
    } else {
        log-warn "OpenSSL winget installed but headers/libs not found — build may need manual setup"
    }
} else {
    log-info "OpenSSL already installed in ./opt/"
}

# ── 8. LLM tooling (optional) ────────────────────────────────────────────────
if (-not $NoLLM) {
    log-info "Installing LLM tooling (llama.cpp build deps: MinGW-w64)..."
    Install-Dep -Choco "mingw" -WingetId "BrechtSanders.WinLibs.POSIX.UCRT"
    log-info "LLM tooling installed"
} else {
    log-info "Skipping LLM tooling (-NoLLM)"
}

# ── 9. Summary ───────────────────────────────────────────────────────────────
log-info "Windows ARM64 setup complete"
log-info "Tools:"
foreach ($tool in @("clang", "zig", "just", "cl")) {
    $ver = (Get-Command $tool -ErrorAction SilentlyContinue).Version
    if ($ver) { log-info "  ${tool}: $ver" }
}
log-info "NOTE: Zig uses native aarch64-windows binary"
