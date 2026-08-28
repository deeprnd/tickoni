# windows-x86.ps1 - Setup Windows x86_64
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

function Add-PathEntry {
    param([string]$PathEntry)

    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }

    $entries = $env:PATH -split ';'
    if ($entries -notcontains $PathEntry) {
        $env:PATH = "$PathEntry;$env:PATH"
    }

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $PathEntry) {
        [Environment]::SetEnvironmentVariable('Path', "$PathEntry;$userPath", 'User')
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

# -- 0. Winget (only package manager - auto-install if missing) ----------------
if (Get-Command winget -ErrorAction SilentlyContinue) {
    log-info "winget already installed"
} else {
    log-info "winget not found - installing..."
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
Add-PathEntry (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')

# -- 1c. pkg-config (required by Zig Windows cross-compilation) ---------------
# Git for Windows provides pkg-config.BAT in its bin directories. Add them early.
$gitBinDir = if (Test-Path 'C:\Program Files\Git\usr\bin') {
    'C:\Program Files\Git\usr\bin'
} elseif (Test-Path 'C:\Program Files (x86)\Git\usr\bin') {
    'C:\Program Files (x86)\Git\usr\bin'
} else {
    $null
}
if ($gitBinDir) {
    Add-PathEntry $gitBinDir
    log-info "Git bin added to PATH for pkg-config.BAT"
} elseif (-not (Get-Command pkg-config -ErrorAction SilentlyContinue)) {
    log-error "Git for Windows not found and pkg-config not available"
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
$platform_key = get-windows-platform-key
$clang_version = read-compiler-version "clang" $platform_key
log-info "Installing LLVM/Clang ${clang_version}..."
Install-Package "llvm"

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

# -- 4. Zig -------------------------------------------------------------------
Install-Package "minisign"
ensure-zig

# -- 5. MSVC build tools ------------------------------------------------------
log-info "Installing Visual Studio Build Tools..."
Install-Package "vs-build-tools"

# -- 6. OpenSSL 3.6.2 - build from source via Git Bash (native MSVC target)
# Git for Windows includes: bash, perl (Strawberry), make.
# VS Build Tools provides: cl.exe, nmake.
# OpenSSL 3.x supports msvc-x86_64 target natively - no MinGW-w64.
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
        $opensslProc = Start-Process -FilePath $gitBash -ArgumentList @('-lc', "cd '$($repoRoot -replace '\\','/')' && FD_WINDOWS_ARCH=x86_64 bash '$openssl_posix'") -Wait -NoNewWindow -PassThru
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
log-info "Windows x86_64 setup complete"
log-info "Tools:"
foreach ($tool in @("clang", "zig", "just", "cl")) {
    $ver = (Get-Command $tool -ErrorAction SilentlyContinue).Version
    if ($ver) { log-info "  ${tool}: $ver" }
}
