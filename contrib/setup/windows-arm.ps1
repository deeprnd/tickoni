# windows-arm.ps1 - Setup Windows ARM64
# Usage:
#   .\windows-arm.ps1              # default: install all deps + LLM tooling
#   .\windows-arm.ps1 -NoLLM       # skip LLM tooling (llama.cpp build)
#   .\windows-arm.ps1 -Security -NoLLM  # install gitleaks, skip LLM
# Package manager: winget ONLY. If winget is missing, auto-install it.
# Note: Tickoni Windows ARM CI now uses the native aarch64-windows Zig 0.17
# toolchain. The old x86_64-on-ARM workaround was only for Zig 0.16 instability
# and should not be reintroduced silently.
# Note: OpenSSL uses native MSVC target (msvc-arm64), no MinGW-w64/MSYS2 needed.

param([switch]$Security, [switch]$NoLLM)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Get-Item (Join-Path $scriptDir "..\..")).FullName

. (Join-Path $scriptDir "helpers\common.ps1")

log-info "Windows ARM64 setup starting..."

function Add-PathEntry {
    param([string]$PathEntry)

    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }

    $entries = $env:PATH -split ';'
    if ($entries -notcontains $PathEntry) {
        $env:PATH = "$PathEntry;$env:PATH"
    }

    if ($env:GITHUB_PATH) {
        if (-not (Test-Path $env:GITHUB_PATH) -or -not (Select-String -Path $env:GITHUB_PATH -SimpleMatch -Quiet -Pattern $PathEntry)) {
            Add-Content -Path $env:GITHUB_PATH -Value $PathEntry
        }
    }
}

function Add-WindowsSetupPaths {
    Add-PathEntry (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
    Add-PathEntry 'C:\Program Files\LLVM\bin'

    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            Add-PathEntry $_.FullName
            Add-PathEntry (Join-Path $_.FullName 'Scripts')
        }
}

function Install-PreCommit {
    Add-WindowsSetupPaths

    $pythonExe = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Filter python.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\Lib\\venv\\' } |
        Select-Object -ExpandProperty FullName -First 1

    if (-not $pythonExe) {
        $python = resolve-python-command
        if ($python) {
            $pythonExe = $python.Path
        }
    }

    if (-not $pythonExe) {
        log-error 'Python not found - cannot install pre-commit'
        exit 1
    }

    log-info 'Installing pre-commit via pip...'
    & $pythonExe -m pip install --disable-pip-version-check --upgrade pre-commit
    if ($LASTEXITCODE -ne 0) {
        log-error 'Failed to install pre-commit via pip'
        exit 1
    }

    Add-WindowsSetupPaths
}

Add-WindowsSetupPaths

if ($env:GITHUB_ENV -and $env:PROCESSOR_ARCHITECTURE) {
    Add-Content -Path $env:GITHUB_ENV -Value "TK_WINDOWS_HOST_ARCH=$($env:PROCESSOR_ARCHITECTURE)"
}

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

# -- 0. Winget (only package manager - auto-install if missing) ----------------
if (Get-Command winget -ErrorAction SilentlyContinue) {
    log-info "winget already installed"
} else {
    log-info "winget not found - installing..."
    Install-WinGet
}

# Install winget package by name from tool-versions.json
function Install-Package {
    param([string]$Name)

    if ($Name -eq 'pre-commit') {
        Install-PreCommit
        return
    }

    $wingetId = read-package "winget" $Name
    log-info "Installing ${Name} (${wingetId})..."
    winget install --id $wingetId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
}

# -- 1. Core packages ---------------------------------------------------------
log-info "Installing core packages..."
Install-Package "git"
Install-Package "cmake"
Install-Package "ninja"
Install-Package "zstd"
Install-Package "python"
Install-Package "shellcheck"
Install-Package "pre-commit"
Install-Package "buf"

# -- 1c. pkg-config (required by Zig Windows cross-compilation) ---------------
# Windows ARM runners may resolve pkg-config through either Git for Windows or a
# standalone Strawberry Perl install. Add both explicit roots so later bash/Zig
# steps see the same command via GITHUB_PATH that this setup step sees.
Add-WindowsSetupPaths
$gitRoot = if (Test-Path 'C:\Program Files\Git') {
    'C:\Program Files\Git'
} elseif (Test-Path 'C:\Program Files (x86)\Git') {
    'C:\Program Files (x86)\Git'
} else {
    $null
}
if ($gitRoot) {
    # Top-level bin dirs (x86_64 Git layout)
    foreach ($sub in @('usr\bin', 'bin')) {
        $dir = Join-Path $gitRoot $sub
        if (Test-Path $dir) { Add-PathEntry $dir }
    }
    # ARM64 Git layout: MSYS2 UCRT mingw64 tree
    foreach ($sub in @('mingw64\usr\bin', 'mingw64\bin', 'mingw64\perl\bin')) {
        $dir = Join-Path $gitRoot $sub
        if (Test-Path $dir) { Add-PathEntry $dir }
    }
    log-info "Git bin dirs added to PATH for pkg-config.BAT"
} else {
    log-warn "Git for Windows not found while configuring pkg-config PATH"
}

$strawberryPerlBin = if (Test-Path 'C:\Strawberry\perl\bin') {
    'C:\Strawberry\perl\bin'
} else {
    $null
}
if ($strawberryPerlBin) {
    Add-PathEntry $strawberryPerlBin
    log-info "Strawberry Perl bin added to PATH for pkg-config.BAT"
}

$pkgConfigCmd = Get-Command pkg-config -ErrorAction SilentlyContinue
if ($pkgConfigCmd) {
    log-info "pkg-config resolved to: $($pkgConfigCmd.Source)"
} else {
    log-error "pkg-config.BAT not found after PATH setup"
    log-error "Zig Windows builds will fail without pkg-config"
}

# -- 1b. Security tools (opt-in via -Security flag) --------------------------
if ($Security) {
    ensure-gitleaks
} else {
    log-info "Skipping security tools (pass -Security to install)"
}

# -- 2. just ------------------------------------------------------------------
if (-not (Get-Command just -ErrorAction SilentlyContinue)) {
    log-info "Installing just..."
    ensure-just
}

# -- 3. LLVM (Clang compiler) -------------------------------------------------
# platform.sh (used via common.ps1) checks PROCESSOR_ARCHITEW6432 (WOW64)
# before PROCESSOR_ARCHITECTURE. On native ARM64, WOW64 env = AMD64 → returns
# x86_64. Hardcode platform-key for this lane instead.
$platform_key = "windows-arm"
$clang_version = read-compiler-version "clang" $platform_key
log-info "Installing LLVM/Clang ${clang_version}..."
# ARM64 LLVM: winget unversioned ID is the only option (ARM64 support).
# Falls back to direct download if winget fails.
if (Get-Command clang -ErrorAction SilentlyContinue) {
    log-info "Clang already available"
} else {
    Add-WindowsSetupPaths
    if (Get-Command clang -ErrorAction SilentlyContinue) {
        log-info "Clang became available after PATH refresh"
    } elseif (Test-Path 'C:\Program Files\LLVM\bin\clang.exe') {
        Add-PathEntry 'C:\Program Files\LLVM\bin'
        log-info "Clang found in standard LLVM install path"
    } else {
    # Try unversioned winget ID (ARM64 support)
    $llvmInstalled = $false
    try {
        $wingetId = read-package "winget" "llvm"
        winget install --id $wingetId --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
        Add-WindowsSetupPaths
        $clangCmd = Get-Command clang -ErrorAction SilentlyContinue
        if (-not $clangCmd -and (Test-Path 'C:\Program Files\LLVM\bin\clang.exe')) {
            Add-PathEntry 'C:\Program Files\LLVM\bin'
            $clangCmd = Get-Command clang -ErrorAction SilentlyContinue
        }
        if ($clangCmd) {
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
                Add-PathEntry $llvmPath
                log-info "LLVM installed via direct download: $llvmPath"
            }
        } catch {
            log-error "Failed to install LLVM via direct download"
            log-error "Build may fail without a C compiler"
        }
    }
    }
}

$clangCmd = Get-Command clang -ErrorAction SilentlyContinue
$llvmPath = $null
if ($clangCmd) {
    $llvmPath = Split-Path $clangCmd.Source
} elseif (Test-Path 'C:\Program Files\LLVM\bin\clang.exe') {
    $llvmPath = 'C:\Program Files\LLVM\bin'
}
if ($llvmPath) {
    Add-PathEntry $llvmPath
    log-info "LLVM added to PATH: $llvmPath"
}

# -- 4. Zig (native aarch64-windows on ARM64) --------------------------------
log-info "Installing Zig (native aarch64-windows on ARM64)..."
ensure-zig "aarch64-windows"
log-info "Zig installed (native aarch64-windows on ARM64)"

# -- 5. MSVC build tools ------------------------------------------------------
log-info "Installing Visual Studio Build Tools..."
Install-Package "vs-build-tools"

# -- 6. OpenSSL 3.6.2 - build from source via Git Bash (native MSVC target)
# Git for Windows includes: bash, perl (Strawberry), make.
# VS Build Tools provides: cl.exe, nmake.
# OpenSSL 3.x supports msvc-arm64/msvc-x86_64 targets natively - no MinGW-w64.
# No MSYS2, no gcc, no cross-compiler needed.
$opensslStaticLib = Join-Path $repoRoot 'opt\lib\libssl.lib'
$opensslArchive = Join-Path $repoRoot 'opt\lib\libssl.a'
if (-not ((Test-Path $opensslStaticLib) -or (Test-Path $opensslArchive))) {
    $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
    $gitBash = $null
    if ($bashCmd) {
        $gitBash = $bashCmd.Source
    }
    if (-not $gitBash) {
        $gitBash = "${env:ProgramFiles}\Git\usr\bin\bash.exe"
    }
    if (-not (Test-Path $gitBash)) {
        $gitBash = "${env:ProgramFiles(x86)}\Git\usr\bin\bash.exe"
    }
    if (Test-Path $gitBash) {
        log-info "Building OpenSSL 3.6.2 via Git Bash (MSVC target)..."
        $openssl_script = Join-Path $repoRoot 'contrib/setup/helpers/install-openssl.sh'
        $openssl_posix = & cygpath -u $openssl_script
        $opensslProc = Start-Process -FilePath $gitBash -ArgumentList @('-lc', "cd '$($repoRoot -replace '\\','/')' && FD_WINDOWS_ARCH=arm64 bash '$openssl_posix'") -Wait -NoNewWindow -PassThru
        if ($opensslProc.ExitCode -ne 0) {
            log-error "OpenSSL build failed with exit code $($opensslProc.ExitCode)"
            exit $opensslProc.ExitCode
        }
    } else {
        log-error "Git Bash not found - OpenSSL 3.6.2 cannot be built"
        log-error "Install Git for Windows and rerun setup"
        exit 1
    }
} else {
    log-info "OpenSSL 3.6.2 already installed in ./opt/"
}

# -- 7. LLM tooling (optional) ------------------------------------------------
if (-not $NoLLM) {
    log-info "Installing LLM tooling (llama.cpp build deps: MinGW-w64)..."
    Install-Package "winlibs"
    log-info "LLM tooling installed"
} else {
    log-info "Skipping LLM tooling (-NoLLM)"
}

# -- 8. Summary ---------------------------------------------------------------
log-info "Windows ARM64 setup complete"
log-info "Tools:"
foreach ($tool in @("clang", "zig", "just", "cl")) {
    $ver = (Get-Command $tool -ErrorAction SilentlyContinue).Version
    if ($ver) { log-info "  ${tool}: $ver" }
}
log-info "NOTE: Zig uses the native aarch64-windows binary on ARM64 so contrib/zigw.sh matches the current CI/local 0.17 path"
