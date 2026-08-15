# common.ps1 — shared Windows PowerShell functions for contrib/setup/ lane scripts.
# Source this from your lane script (windows-x86.ps1, windows-arm.ps1)
#
# Version source of truth: contrib/setup/tool-versions.json
#
#   versions.*  — explicit version pins for tools whose version matters for
#                 install behavior (download URLs, package names, build scripts).
#                 Read with read-tool-version (universal) or read-compiler-version
#                 (platform-specific).
#
#   packages.*  — package manager identifiers for tools where "latest" from
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

# ── Read version from versions section ────────────────────────────────────────
#
# Universal tools (single version everywhere):
#   read-tool-version "just"      → "1.58.0"
#   read-tool-version "gitleaks"  → "8.30.1"
#   read-tool-version "zig"       → "0.16.0"
#   read-tool-version "openssl"   → "3.6.2"
#
# Usage: read-tool-version "just"
function read-tool-version {
    param([string]$Tool)

    if (-not (Test-Path $script:TOOL_VERSIONS)) {
        log-error "Tool versions file missing: $script:TOOL_VERSIONS"
        exit 1
    }

    $jsonPath = $script:TOOL_VERSIONS.Replace('\', '/')
    $tmpFile = Join-Path $env:TEMP "py_tool_version_$([Guid]::NewGuid().ToString('N')).txt"

    $pythonScript = @"
import json, sys
try:
    data = json.load(open('$jsonPath'))
    v = data.get('versions', {}).get('$Tool')
    if isinstance(v, dict):
        v = v.get('version', '')
    if not v:
        sys.exit(1)
    with open(sys.argv[1], 'w') as f:
        f.write(str(v))
except Exception:
    sys.exit(1)
"@
    Set-Content -Path (Join-Path $script:SCRIPT_DIR "py_read_tool_version.py") -Value $pythonScript -Encoding UTF8

    try {
        $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $pyCmd) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue }
        if (-not $pyCmd) { $pyCmd = Get-Command py -ErrorAction SilentlyContinue }
        if (-not $pyCmd) {
            log-error "Python not found — cannot read tool versions"
            exit 1
        }
        & $pyCmd.Source (Join-Path $script:SCRIPT_DIR "py_read_tool_version.py") "$tmpFile"

        $result = Get-Content $tmpFile -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0 -or -not $result -or $result.Count -eq 0) {
            log-error "Version not defined for '${Tool}' in $script:TOOL_VERSIONS"
            exit 1
        }

        Write-Output $result.Trim()
    } finally {
        Remove-Item (Join-Path $script:SCRIPT_DIR "py_read_tool_version.py") -ErrorAction SilentlyContinue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# Read platform-specific version (gcc, clang, llvm, msvc).
# Usage: read-compiler-version "clang" "windows-x86"
function read-compiler-version {
    param([string]$Tool, [string]$PlatformKey)

    if (-not (Test-Path $script:TOOL_VERSIONS)) {
        log-error "Tool versions file missing: $script:TOOL_VERSIONS"
        exit 1
    }

    $jsonPath = $script:TOOL_VERSIONS.Replace('\', '/')
    $tmpFile = Join-Path $env:TEMP "py_compiler_version_$([Guid]::NewGuid().ToString('N')).txt"

    $pythonScript = @"
import json, sys
try:
    data = json.load(open('$jsonPath'))
    v = data.get('versions', {}).get('$Tool', {}).get('$PlatformKey')
    if not v:
        sys.exit(1)
    with open(sys.argv[1], 'w') as f:
        f.write(str(v))
except Exception:
    sys.exit(1)
"@
    Set-Content -Path (Join-Path $script:SCRIPT_DIR "py_read_compiler_version.py") -Value $pythonScript -Encoding UTF8

    try {
        $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $pyCmd) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue }
        if (-not $pyCmd) { $pyCmd = Get-Command py -ErrorAction SilentlyContinue }
        if (-not $pyCmd) {
            log-error "Python not found — cannot read tool versions"
            exit 1
        }
        & $pyCmd.Source (Join-Path $script:SCRIPT_DIR "py_read_compiler_version.py") "$tmpFile"

        $result = Get-Content $tmpFile -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0 -or -not $result -or $result.Count -eq 0) {
            log-error "Version not defined for ${Tool} on ${PlatformKey}"
            exit 1
        }

        Write-Output $result.Trim()
    } finally {
        Remove-Item (Join-Path $script:SCRIPT_DIR "py_read_compiler_version.py") -ErrorAction SilentlyContinue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# Read package manager identifier (winget ID) from packages.winget section.
# Usage: read-package "winget" "python" → "Python.Python.3.12"
# Usage: read-package "winget" "cmake"  → "CMake.CMake"
function read-package {
    param([string]$Manager, [string]$Tool)

    if (-not (Test-Path $script:TOOL_VERSIONS)) {
        log-error "Tool versions file missing: $script:TOOL_VERSIONS"
        exit 1
    }

    $jsonPath = $script:TOOL_VERSIONS.Replace('\', '/')
    $tmpFile = Join-Path $env:TEMP "py_package_$([Guid]::NewGuid().ToString('N')).txt"

    $pythonScript = @"
import json, sys
try:
    data = json.load(open('$jsonPath'))
    mgr = data.get('packages', {}).get('$Manager', {})
    if not isinstance(mgr, dict):
        sys.exit(1)
    v = mgr.get('$Tool')
    if not v:
        sys.exit(1)
    with open(sys.argv[1], 'w') as f:
        f.write(str(v))
except Exception:
    sys.exit(1)
"@
    Set-Content -Path (Join-Path $script:SCRIPT_DIR "py_read_package.py") -Value $pythonScript -Encoding UTF8

    try {
        $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $pyCmd) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue }
        if (-not $pyCmd) { $pyCmd = Get-Command py -ErrorAction SilentlyContinue }
        if (-not $pyCmd) {
            log-error "Python not found — cannot read tool versions"
            exit 1
        }
        & $pyCmd.Source (Join-Path $script:SCRIPT_DIR "py_read_package.py") "$tmpFile"

        $result = Get-Content $tmpFile -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0 -or -not $result -or $result.Count -eq 0) {
            log-error "Package mapping not defined for ${Manager}.${Tool} in $script:TOOL_VERSIONS"
            exit 1
        }

        Write-Output $result.Trim()
    } finally {
        Remove-Item (Join-Path $script:SCRIPT_DIR "py_read_package.py") -ErrorAction SilentlyContinue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# Read zig version (alias for tool-versions.json).
# Usage: read-zig-version
function read-zig-version {
    read-tool-version "zig"
}

# ── Platform detection ────────────────────────────────────────────────────────
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

# ── Tool installers ───────────────────────────────────────────────────────────

# Install Zig via install-zig.py (uses versions.zig from tool-versions.json)
function ensure-zig {
    param([string]$Target)

    $zigVersion = read-zig-version

    $zigBin = Join-Path $env:LOCALAPPDATA "Programs\Zig\zig"

    if (Test-Path $zigBin) {
        log-info "Zig $zigVersion already installed"
        $env:PATH = Join-Path $env:LOCALAPPDATA "Programs\Zig" + ";" + $env:PATH
        return
    }

    log-info "Installing Zig $zigVersion..."
    $zigArgs = @("--version", $zigVersion, "--install-root", (Join-Path $env:LOCALAPPDATA "Programs"), "--cache-root", (Join-Path $env:LOCALAPPDATA "zig"), "--user-path")
    if ($Target) {
        $zigArgs += @("--target", $Target)
    }
    $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $pyCmd) { $pyCmd = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $pyCmd) {
        log-error "Python not found — cannot install Zig"
        exit 1
    }
    & $pyCmd.Source (Join-Path $script:SCRIPT_DIR "install-zig.py") @zigArgs
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

    log-warn "winget install failed — downloading directly"

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
