# windows-arm.ps1 — Setup Windows ARM64
# Usage:
#   .\windows-arm.ps1              # default: install all deps + LLM tooling
#   .\windows-arm.ps1 -NoLLM       # skip LLM tooling (llama.cpp build)
#   .\windows-arm.ps1 -Security -NoLLM  # install gitleaks, skip LLM
# Package manager: winget ONLY. If winget is missing, auto-install it.
# Note: Zig uses native aarch64-windows prebuilt binary

param([switch]$Security, [switch]$NoLLM)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows ARM64 setup starting..."

function Install-WinGet {
    # Primary: MSIX installer (works on Win11 ARM64 without PackageManagement)
    $msixUrl = "https://aka.ms/getwinget"
    $msixPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    log-info "Downloading winget MSIX installer..."
    try {
        Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $msixPath
        Remove-Item $msixPath -ErrorAction SilentlyContinue
        $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$wingetDir*") {
            $env:PATH = "$wingetDir;$env:PATH"
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            log-info "winget installed via MSIX"
            return
        }
    } catch {
        log-info "MSIX install failed, falling back..."
    }

    # Fallback: try the built-in Install-WinGetPackage cmdlet (Win10 1709+)
    try {
        if (Get-Command Install-WinGetPackage -ErrorAction SilentlyContinue) {
            Install-WinGetPackage -Destination Latest -ErrorAction Stop
            $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
            if ($env:PATH -notlike "*$wingetDir*") {
                $env:PATH = "$wingetDir;$env:PATH"
            }
            if (Get-Command winget -ErrorAction SilentlyContinue) {
                log-info "winget installed via Install-WinGetPackage"
                return
            }
        }
    } catch {
        log-info "Install-WinGetPackage failed, trying NuGet/PSGallery fallback..."
    }

    # Last resort: PSGallery + PackageManagement (may fail on minimal images)
    try {
        $ProgressPreference = 'SilentlyContinue'
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force | Out-Null
        }
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction SilentlyContinue
        $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$wingetDir*") {
            $env:PATH = "$wingetDir;$env:PATH"
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            log-info "winget installed via PSGallery"
            return
        }
    } catch {
        log-info "PSGallery fallback failed, trying direct MSIX URL..."
    }

    # Absolute last resort: direct MSIX bundle download
    try {
        $ProgressPreference = 'SilentlyContinue'
        $msixUrl2 = "https://github.com/microsoft/winget-cli/releases/download/v1.9.3202/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        $msixPath2 = Join-Path $env:TEMP "winget.msixbundle"
        Invoke-WebRequest -Uri $msixUrl2 -OutFile $msixPath2 -UseBasicParsing
        Add-AppxPackage -Path $msixPath2
        Remove-Item $msixPath2 -ErrorAction SilentlyContinue
        $wingetDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$wingetDir*") {
            $env:PATH = "$wingetDir;$env:PATH"
        }
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            log-info "winget installed via direct MSIX"
            return
        }
    } catch {
        log-info "All winget install methods failed"
    }
    log-error "Failed to install winget"
    exit 1
}

# ── 0. Winget (only package manager — auto-install if missing) ────────────────
if (Get-Command winget -ErrorAction SilentlyContinue) {
    log-info "winget already installed"
} else {
    log-info "winget not found — installing..."
    Install-WinGet
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
# detect-windows-arch.sh checks PROCESSOR_ARCHITEW6432 (WOW64) before
# PROCESSOR_ARCHITECTURE. On native ARM64, WOW64 env = AMD64 → returns
# x86_64. Hardcode platform-key for this lane instead.
$platform_key = "windows-arm"
$clang_version = read-compiler-version "clang" $platform_key
log-info "Installing LLVM/Clang ${clang_version}..."
# ARM64 LLVM: winget unversioned ID is the only option (ARM64 support).
# Falls back to direct download if winget fails.
if (Get-Command clang -ErrorAction SilentlyContinue) {
    log-info "Clang already available"
} else {
    # Try unversioned winget ID (ARM64 support)
    $llvmInstalled = $false
    try {
        $wingetId = read-package "winget" "llvm"
        winget install --id $wingetId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
        $llvmPath = (Get-Command clang -ErrorAction SilentlyContinue).Source | Split-Path
        if ($llvmPath) {
            $env:PATH = "$llvmPath;$env:PATH"
            $llvmInstalled = $true
            log-info "LLVM installed via winget"
        }
    } catch {
        log-info "LLVM winget install failed, trying direct download..."
    }

    # Fallback: direct download to C:\Program Files\LLVM
    if (-not $llvmInstalled) {
        log-info "Downloading LLVM ${clang_version} ARM64..."
        $llvmUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-${clang_version}.0.0/LLVM-${clang_version}.0.0-windows-arm64.exe"
        $llvmInstaller = Join-Path $env:TEMP "llvm-installer.exe"
        try {
            Invoke-WebRequest -Uri $llvmUrl -OutFile $llvmInstaller -UseBasicParsing
            Start-Process -FilePath $llvmInstaller -ArgumentList "/S", "/D=C:\Program Files\LLVM" -Wait
            Remove-Item $llvmInstaller -ErrorAction SilentlyContinue
            $llvmPath = "C:\Program Files\LLVM\bin"
            if (Test-Path (Join-Path $llvmPath "clang.exe")) {
                $env:PATH = "$llvmPath;$env:PATH"
                log-info "LLVM installed via direct download: $llvmPath"
            }
        } catch {
            log-error "Failed to install LLVM via direct download"
            log-error "Build may fail without a C compiler"
        }
    }
}

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
ensure-zig "aarch64-windows"
log-info "Zig installed (aarch64-windows native)"

# ── 5. cpanm (for MSYS2 Perl module installs) ───────────────────────────────
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
    log-info "cpanm not found — installing via MSYS2 pacman..."
    $msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
    if (Test-Path $msysBash) {
        & $msysBash -lc "pacman -S --noconfirm cpanminus" 2>&1 | Out-Null
    }
} elseif (-not (Test-CpanmWorks)) {
    log-info "cpanm found but missing ExtUtils::Manifest (Strawberry Perl fat-pack) — installing MSYS2 cpanminus..."
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
log-info "cpanm ready for Perl module installs"

# ── 6. MSVC build tools ──────────────────────────────────────────────────────
log-info "Installing Visual Studio Build Tools..."
Install-Package "vs-build-tools"

# ── 6b. MSYS2 (required for OpenSSL build on Windows) ──────────────────────
$msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
if (-not (Test-Path $msysBash)) {
    log-info "Installing MSYS2..."
    Install-Package "msys2"

    # Wait for MSYS2 to be available
    $msysReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $msysBash) {
            $msysReady = $true
            break
        }
    }
    if (-not $msysReady) {
        log-error "MSYS2 install timed out — bash not found at $msysBash"
        exit 1
    }
    log-info "MSYS2 installed"
} else {
    log-info "MSYS2 already installed"
}

# Ensure MSYS2 bin (cygpath, bash, etc.) is in PATH
$msysPath = "$env:SystemDrive\msys64\usr\bin"
if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $msysPath })) {
    $env:PATH = $msysPath + ";" + $env:PATH
}

# ── 6c. Ensure git, make, and perl are installed in MSYS2 (required for OpenSSL build) ────────
# MSYS2 pacman doesn't include these by default. We need them inside MSYS2 because
# install-openssl.sh runs via MSYS2 bash and calls 'git clone' and 'make'.
$msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
if (Test-Path $msysBash) {
    if (-not (& $msysBash -lc "git --version" 2>$null)) {
        log-info "Installing git via MSYS2 pacman..."
        & $msysBash -lc "pacman -S --noconfirm --needed git" 2>&1 | Out-Null
    } else {
        log-info "git already available in MSYS2"
    }
    if (-not (& $msysBash -lc "make --version" 2>$null)) {
        log-info "Installing make via MSYS2 pacman..."
        & $msysBash -lc "pacman -S --noconfirm --needed make" 2>&1 | Out-Null
    } else {
        log-info "make already available in MSYS2"
    }
    if (-not (& $msysBash -lc "perl --version" 2>$null)) {
        log-info "Installing perl via MSYS2 pacman..."
        & $msysBash -lc "pacman -S --noconfirm --needed perl" 2>&1 | Out-Null
    } else {
        log-info "perl already available in MSYS2"
    }
    # OpenSSL's build process invokes gcc inside MSYS2 bash (make + shell).
    # On ARM64 the MSYS2 package is ucrt-aarch64-gcc (ucrtarm repo, UCRT runtime).
    # The 'ucrt-aarch64-' prefix is used by ucrtarm on ARM64 (not mingw-w64-*).
    if (-not (& $msysBash -lc "gcc --version" 2>$null)) {
        log-info "Installing gcc (ucrt-aarch64-gcc) via MSYS2 pacman..."
        $gcc_install = & $msysBash -lc "pacman -S --noconfirm --needed ucrt-aarch64-gcc" 2>&1
        if ($LASTEXITCODE -ne 0) {
            log-warn "ucrt-aarch64-gcc not found, trying mingw-w64-aarch64-gcc as fallback..."
            $gcc_install2 = & $msysBash -lc "pacman -S --noconfirm --needed mingw-w64-aarch64-gcc" 2>&1
            if ($LASTEXITCODE -ne 0) {
                log-error "Failed to install gcc (tried ucrt-aarch64-gcc and mingw-w64-aarch64-gcc): $gcc_install2"
                exit 1
            }
        }
    } else {
        log-info "gcc already available in MSYS2"
    }
    log-info "git, make, perl, gcc available in MSYS2"
}

# ── 7. OpenSSL 3.6.2 — build from source (deps.sh logic) via MSYS2 bash
# so Firedancer gets the right API level.
# FD_WINDOWS_ARCH=arm64 overrides uname -m (returns x86_64 inside the
# x86_64 MSYS2 package running under Windows emulation on ARM64).
if (-not (Test-Path (Join-Path $repoRoot "opt\lib\libssl.a"))) {
    $msysBash = "$env:SystemDrive\msys64\usr\bin\bash.exe"
    if (Test-Path $msysBash) {
        log-info "Building OpenSSL 3.6.2 via MSYS2 bash..."
        $openssl_script = Join-Path $repoRoot 'contrib/setup/install-openssl.sh'
        $opt_path = Join-Path $repoRoot 'opt'
        $openssl_posix = & cygpath -u $openssl_script
        $opt_posix = & cygpath -u $opt_path
        & $msysBash -lc "FD_WINDOWS_ARCH=arm64 bash $openssl_posix --prefix $opt_posix" 2>&1
    } else {
        log-error "MSYS2 bash not found — OpenSSL 3.6.2 cannot be built"
        exit 1
    }
} else {
    log-info "OpenSSL 3.6.2 already installed in ./opt/"
}

# ── 8. LLM tooling (optional) ────────────────────────────────────────────────
if (-not $NoLLM) {
    log-info "Installing LLM tooling (llama.cpp build deps: MinGW-w64)..."
    Install-Package "winlibs"
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
