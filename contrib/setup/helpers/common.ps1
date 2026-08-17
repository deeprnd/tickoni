# common.ps1 - shared Windows PowerShell functions for contrib/setup/ lane scripts.
# Source this from your lane script (windows-x86.ps1, windows-arm.ps1)
#
# Version source of truth: contrib/setup/tool-versions.json
#
#   versions.*  - explicit version pins for tools whose version matters for
#                 install behavior (download URLs, package names, build scripts).
#                 Read with read-tool-version (universal) or read-compiler-version
#                 (platform-specific).
#
#   packages.*  - package manager identifiers for tools where "latest" from
#                 the manager is fine (winget IDs, apt/brew package names, etc.).
#                 Read with read-package.

$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:REPO_ROOT = (Get-Item (Join-Path $script:SCRIPT_DIR "..\..\..")).FullName
$script:TOOL_VERSIONS = Join-Path $script:REPO_ROOT "contrib\setup\tool-versions.json"

function log-info { Write-Host "[setup] $args" }
function log-warn { Write-Host "[setup] WARN: $args" -ForegroundColor Yellow }
function log-error { Write-Host "[setup] ERROR: $args" -ForegroundColor Red }

function tool-exists {
    param([string]$Name)
    return Get-Command $Name -ErrorAction SilentlyContinue
}

# -- Read version from versions section ----------------------------------------
#
# Universal tools (single version everywhere):
#   read-tool-version "just"      -> "1.58.0"
#   read-tool-version "gitleaks"  -> "8.30.1"
#   read-tool-version "zig"       -> "0.17.0-dev.1770+5d7cf3f34"
#   read-tool-version "openssl"   -> "3.6.2"
#
# Usage: read-tool-version "just"
function get-tool-versions-data {
    if (-not (Test-Path $script:TOOL_VERSIONS)) {
        log-error "Tool versions file missing: $script:TOOL_VERSIONS"
        exit 1
    }

    if (-not (Get-Variable -Scope Script -Name TOOL_VERSIONS_DATA -ErrorAction SilentlyContinue)) {
        $script:TOOL_VERSIONS_DATA = $null
    }

    if ($null -eq $script:TOOL_VERSIONS_DATA) {
        try {
            $script:TOOL_VERSIONS_DATA = Get-Content -Path $script:TOOL_VERSIONS -Raw | ConvertFrom-Json
        } catch {
            log-error "Failed to parse tool versions file: $script:TOOL_VERSIONS"
            exit 1
        }
    }

    return $script:TOOL_VERSIONS_DATA
}

function get-object-member {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) {
        return $prop.Value
    }

    return $null
}

function read-tool-version {
    param([string]$Tool)

    $data = get-tool-versions-data
    $versions = get-object-member $data 'versions'
    $value = get-object-member $versions $Tool

    if ($null -eq $value) {
        log-error "Version not defined for '${Tool}' in $script:TOOL_VERSIONS"
        exit 1
    }

    if ($value -is [string]) {
        Write-Output $value.Trim()
        return
    }

    $nestedVersion = get-object-member $value 'version'
    if (-not $nestedVersion) {
        log-error "Version not defined for '${Tool}' in $script:TOOL_VERSIONS"
        exit 1
    }

    Write-Output ([string]$nestedVersion).Trim()
}

# Read platform-specific version (gcc, clang, llvm, msvc).
# Usage: read-compiler-version "clang" "windows-x86"
function read-compiler-version {
    param([string]$Tool, [string]$PlatformKey)

    $data = get-tool-versions-data
    $versions = get-object-member $data 'versions'
    $toolVersions = get-object-member $versions $Tool
    $value = get-object-member $toolVersions $PlatformKey

    if (-not $value) {
        log-error "Version not defined for ${Tool} on ${PlatformKey}"
        exit 1
    }

    Write-Output ([string]$value).Trim()
}

# Read package manager identifier (winget ID) from packages.winget section.
# Usage: read-package "winget" "python" -> "Python.Python.3.12"
# Usage: read-package "winget" "cmake"  -> "CMake.CMake"
function read-package {
    param([string]$Manager, [string]$Tool)

    $data = get-tool-versions-data
    $packages = get-object-member $data 'packages'
    $managerPackages = get-object-member $packages $Manager
    $value = get-object-member $managerPackages $Tool

    if (-not $value) {
        log-error "Package mapping not defined for ${Manager}.${Tool} in $script:TOOL_VERSIONS"
        exit 1
    }

    Write-Output ([string]$value).Trim()
}

# Read zig version (alias for tool-versions.json).
# Usage: read-zig-version
function read-zig-version {
    read-tool-version "zig"
}

# -- Platform detection --------------------------------------------------------
# Returns: windows-x86 or windows-arm

function get-windows-platform-key {
    $scriptPath = Join-Path $script:SCRIPT_DIR "detect-windows-arch.sh"
    if (Test-Path $scriptPath) {
        $arch = bash $scriptPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $arch) {
            if ($arch -eq "aarch64" -or $arch -eq "arm64") {
                return "windows-arm"
            }
            return "windows-x86"
        }
    }
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        return "windows-arm"
    }
    return "windows-x86"
}

function get-windows-arch {
    $arch = bash (Join-Path $script:SCRIPT_DIR "detect-windows-arch.sh") 2>$null
    if ($LASTEXITCODE -eq 0) { return $arch }
    return "x86_64"
}

function resolve-python-command {
    foreach ($candidate in @('python', 'py', 'python3')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) {
            continue
        }

        $args = if ($candidate -eq 'py') { @('-3') } else { @() }

        try {
            & $cmd.Source @args '--version' *> $null
            if ($LASTEXITCODE -eq 0) {
                return [PSCustomObject]@{
                    Path = $cmd.Source
                    Args = $args
                }
            }
        } catch {
            continue
        }
    }

    return $null
}

# -- Tool installers -----------------------------------------------------------

# Install Zig via install-zig.py (uses versions.zig from tool-versions.json).
# Keep the install root aligned with install-zig.py's Windows default and with
# contrib/zigw.sh's Windows ARM x86_64-Zig discovery path.
function ensure-zig {
    param([string]$Target)

    $zigVersion = read-zig-version

    $installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Zig'
    $zigInstallDir = $null
    if ($Target) {
        $zigInstallDir = Join-Path $installRoot ("zig-{0}-{1}" -f $Target, $zigVersion)
    }

    # Remove any previously installed zig version before installing the new one
    if ($zigInstallDir -and (Test-Path $zigInstallDir)) {
        Remove-Item -Recurse -Force $zigInstallDir
    }

    $zigBin = $null
    $legacyCandidate = Join-Path $env:LOCALAPPDATA 'Programs\Zig\zig.exe'
    if (Test-Path $legacyCandidate) {
        Remove-Item -Recurse -Force (Split-Path $legacyCandidate)
    }

    log-info "Installing Zig $zigVersion..."
    $zigArgs = @("--version", $zigVersion, "--install-root", $installRoot, "--cache-root", (Join-Path $env:LOCALAPPDATA "zig"), "--user-path")
    if ($Target) {
        $zigArgs += @("--target", $Target)
    }
    $python = resolve-python-command
    if (-not $python) {
        log-error "Python not found - cannot install Zig"
        exit 1
    }
    & $python.Path @($python.Args + @((Join-Path $script:SCRIPT_DIR "install-zig.py")) + $zigArgs)

    if ($LASTEXITCODE -ne 0) {
        log-error "Zig installer failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    if (-not $zigInstallDir -or -not (Test-Path (Join-Path $zigInstallDir 'zig.exe'))) {
        $zigInstallDir = Get-ChildItem $installRoot -Directory -Filter 'zig-*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -ExpandProperty FullName -First 1
    }

    if (-not $zigInstallDir -or -not (Test-Path (Join-Path $zigInstallDir 'zig.exe'))) {
        log-error "Zig install completed without a usable zig.exe"
        exit 1
    }

    $env:PATH = $zigInstallDir + ';' + $env:PATH
    log-info "Zig installed"
}

# Install gitleaks (pinned version from tool-versions.json)
function ensure-gitleaks {
    $gitleaksVersion = read-tool-version "gitleaks"

    if (tool-exists "gitleaks") {
        log-info "gitleaks ${gitleaksVersion} already installed"
        return
    }

    log-info "Installing gitleaks ${gitleaksVersion}..."

    $arch = (Get-CimInstance Win32_ComputerSystem).SystemType
    $asset = switch ($arch) {
        "X64-based PC"  { "gitleaks_${gitleaksVersion}_windows_x64.zip" }
        "ARM64-based PC" { "gitleaks_${gitleaksVersion}_windows_arm64.zip" }
        default {
            log-error "Unsupported system type: $arch"
            exit 1
        }
    }

    $tmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $tmpDir
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    Invoke-WebRequest `\
        -Uri "https://github.com/gitleaks/gitleaks/releases/download/v${gitleaksVersion}/${asset}" `\
        -OutFile (Join-Path $tmpDir "gitleaks.zip") -UseBasicParsing

    Expand-Archive -Path (Join-Path $tmpDir "gitleaks.zip") -DestinationPath $tmpDir -Force
    $gitleaksBin = Join-Path $tmpDir "gitleaks.exe"
    if (-not (Test-Path $gitleaksBin)) {
        $gitleaksBin = (Get-ChildItem -Path $tmpDir -Recurse -Filter "gitleaks.exe" | Select-Object -First 1).FullName
    }
    if ($gitleaksBin) {
        Copy-Item $gitleaksBin "$env:SYSTEMROOT\System32\gitleaks.exe"
        log-info "gitleaks ${gitleaksVersion} installed"
    } else {
        log-error "gitleaks binary not found in archive"
        exit 1
    }

    Remove-Item -Recurse -Force $tmpDir
}

# Install just (uses versions.just from tool-versions.json)
function ensure-just {
    if (tool-exists "just") {
        log-info "just already installed"
        return
    }

    $justVersion = read-tool-version "just"

    log-info "Installing just ${justVersion}..."

    $justInstalled = $false
    $justIds = @("just.systems.just", "jklab_hk.just", "jklabhk.just")
    foreach ($id in $justIds) {
        try {
            $result = winget install --id $id --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
            if ($LASTEXITCODE -eq 0 -and (tool-exists "just")) {
                $justInstalled = $true
                log-info "just installed via winget ($id)"
                break
            }
        } catch {
            # winget install may throw; try next ID
        }
    }

    if ($justInstalled) {
        log-info "just ready"
        return
    }

    log-warn "winget install failed - downloading directly"

    $arch = (Get-CimInstance Win32_ComputerSystem).SystemType
    $asset = switch ($arch) {
        "X64-based PC"  { "just-${justVersion}-x86_64-pc-windows-msvc.zip" }
        "ARM64-based PC" { "just-${justVersion}-aarch64-pc-windows-msvc.zip" }
        default { "just-${justVersion}-x86_64-pc-windows-msvc.zip" }
    }

    $url = "https://github.com/casey/just/releases/download/${justVersion}/${asset}"
    $zip = Join-Path $env:TEMP "just.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

    Expand-Archive -Path $zip -DestinationPath $env:TEMP\just-extract -Force
    $justExe = Get-ChildItem -Path $env:TEMP\just-extract -Filter "just.exe" -Recurse | Select-Object -First 1

    if ($justExe) {
        Copy-Item $justExe.FullName (Join-Path $env:SYSTEMROOT "System32\just.exe")
        log-info "just installed via direct download (${justVersion})"
    } else {
        log-error "just binary not found in archive"
        exit 1
    }

    Remove-Item -Recurse -Force $env:TEMP\just-extract -ErrorAction SilentlyContinue
    Remove-Item $zip -ErrorAction SilentlyContinue
}
