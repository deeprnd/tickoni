param(
    [string]$AptPackages = '',
    [switch]$InstallGnuMake,
    [switch]$InstallGitleaks,
    [string]$GitleaksVersion = '8.30.1',
    [switch]$InstallKcov
)

$ErrorActionPreference = 'Stop'

function Add-ToProcessPath {
    param([string]$Value)
    if (-not $Value) {
        return
    }
    $current = ($env:PATH -split ';') | Where-Object { $_ }
    if ($current -contains $Value) {
        return
    }
    $env:PATH = "$Value;$env:PATH"
}

function Add-ToGitHubPath {
    param([string]$Value)
    if (-not $env:GITHUB_PATH) {
        return
    }
    Add-Content -Path $env:GITHUB_PATH -Value $Value
}

function Add-ToGitHubEnv {
    param(
        [string]$Name,
        [string]$Value
    )
    if (-not $env:GITHUB_ENV) {
        return
    }
    Add-Content -Path $env:GITHUB_ENV -Value "${Name}=${Value}"
}

Add-ToGitHubEnv -Name 'TK_WINDOWS_HOST_ARCH' -Value $env:PROCESSOR_ARCHITECTURE

function Add-PathEntry {
    param([string]$Value)
    if (-not (Test-Path $Value)) {
        return
    }
    Add-ToProcessPath -Value $Value
    Add-ToGitHubPath -Value $Value
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-ChocoPackage {
    param([string]$Name)
    choco install $Name -y --no-progress
}

function Install-WinGetPackage {
    param([string]$Id)
    winget install --id $Id --exact --accept-package-agreements --accept-source-agreements --disable-interactivity
}

function Install-Package {
    param(
        [string]$ChocoName,
        [string]$WingetId
    )

    if (Test-CommandExists -Name 'choco') {
        Install-ChocoPackage -Name $ChocoName
        return
    }
    if (Test-CommandExists -Name 'winget') {
        Install-WinGetPackage -Id $WingetId
        return
    }
    throw "setup-public-gh-runner: neither choco nor winget is available to install $ChocoName / $WingetId"
}

function Get-GitleaksAssetName {
    param([string]$Version)

    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        return "gitleaks_${Version}_windows_arm64.zip"
    }
    return "gitleaks_${Version}_windows_x64.zip"
}

if ($AptPackages) {
    throw "setup-public-gh-runner: apt-packages is Linux-only. Windows jobs must use explicit native bootstrap steps instead of apt package names: '$AptPackages'"
}

if ($InstallKcov) {
    throw 'setup-public-gh-runner: kcov is not supported on Windows runners'
}

if ($InstallGnuMake) {
    Install-Package -ChocoName 'make' -WingetId 'ezwinports.make'
}

Install-Package -ChocoName 'strawberryperl' -WingetId 'StrawberryPerl.StrawberryPerl'

# Install LLVM/Clang explicitly instead of assuming the runner image already
# exposes clang on PATH. The Windows build/test recipes invoke `clang`
# directly, so setup must provision it deterministically.
Install-Package -ChocoName 'llvm' -WingetId 'LLVM.LLVM'

# Install MinGW-w64 cross-compiler toolchain for aarch64-pc-windows-gnu target.
# GitHub Actions `windows-11-vs2026-arm` runners need the MinGW-w64 ARM64 SDK
# headers/sysroot in addition to clang, so --target aarch64-pc-windows-gnu can
# compile C sources successfully.
Install-Package -ChocoName 'mingw' -WingetId 'BrechtSanders.WinLibs.POSIX.UCRT'

$bootstrapPaths = @(
    'C:\ProgramData\chocolatey\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\usr\bin',
    'C:\Program Files\CMake\bin',
    'C:\Program Files\LLVM\bin',
    'C:\Strawberry\perl\bin',
    'C:\Strawberry\c\bin',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
)
foreach ($pathEntry in $bootstrapPaths) {
    Add-PathEntry -Value $pathEntry
}

$wingetRoots = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\LLVM.LLVM_*'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\StrawberryPerl.StrawberryPerl_*'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\ezwinports.make_*'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_*')
)
foreach ($pattern in $wingetRoots) {
    foreach ($root in Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue) {
        Add-PathEntry -Value $root.FullName
        Add-PathEntry -Value (Join-Path $root.FullName 'bin')
        Add-PathEntry -Value (Join-Path $root.FullName 'mingw64\bin')
        Add-PathEntry -Value (Join-Path $root.FullName 'ucrt64\bin')
    }
}

if ($InstallGitleaks) {
    $asset = Get-GitleaksAssetName -Version $GitleaksVersion
    $root = Join-Path $env:RUNNER_TEMP 'gitleaks'
    $zipPath = Join-Path $root 'gitleaks.zip'

    New-Item -ItemType Directory -Force -Path $root | Out-Null
    Invoke-WebRequest -Uri "https://github.com/gitleaks/gitleaks/releases/download/v${GitleaksVersion}/${asset}" -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $root -Force
    Add-ToGitHubPath -Value $root
}
