# common.ps1 — shared Windows PowerShell functions for contrib/setup/ lane scripts.
# Source this from your lane script (windows-x86.ps1, windows-arm.ps1)

$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:REPO_ROOT = (Get-Item (Join-Path $script:SCRIPT_DIR "..\..\..")).FullName

function log-info { Write-Host "[setup] $args" }
function log-warn { Write-Host "[setup] WARN: $args" -ForegroundColor Yellow }
function log-error { Write-Host "[setup] ERROR: $args" -ForegroundColor Red }

function tool-exists {
    param([string]$Name)
    return Get-Command $Name -ErrorAction SilentlyContinue
}

# Install gitleaks (pinned version — matches CI gitleaks on main)
$script:GITLEAKS_VERSION = "8.30.1"

function ensure-gitleaks {
    if (tool-exists "gitleaks") {
        log-info "gitleaks ${script:GITLEAKS_VERSION} already installed"
        return
    }

    log-info "Installing gitleaks ${script:GITLEAKS_VERSION}..."

    $arch = (Get-CimInstance Win32_ComputerSystem).SystemType
    $asset = switch ($arch) {
        "X64-based PC"  { "gitleaks_${script:GITLEAKS_VERSION}_windows_x64.zip" }
        "ARM64-based PC" { "gitleaks_${script:GITLEAKS_VERSION}_windows_arm64.zip" }
        default {
            log-error "Unsupported system type: $arch"
            exit 1
        }
    }

    $tmpDir = [System.IO.Path]::GetTempFileName()
    Remove-Item $tmpDir
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

    Invoke-WebRequest `
        -Uri "https://github.com/zricethezav/gitleaks/releases/download/v${script:GITLEAKS_VERSION}/${asset}" `
        -OutFile (Join-Path $tmpDir "gitleaks.zip") -UseBasicParsing

    Expand-Archive -Path (Join-Path $tmpDir "gitleaks.zip") -DestinationPath $tmpDir -Force
    $gitleaksBin = Join-Path $tmpDir "gitleaks.exe"
    if (-not (Test-Path $gitleaksBin)) {
        # Fallback: binary may not be zip (tar.gz with .exe inside)
        $gitleaksBin = (Get-ChildItem -Path $tmpDir -Recurse -Filter "gitleaks.exe" | Select-Object -First 1).FullName
    }
    if ($gitleaksBin) {
        Copy-Item $gitleaksBin "$env:SYSTEMROOT\System32\gitleaks.exe"
        log-info "gitleaks ${script:GITLEAKS_VERSION} installed"
    } else {
        log-error "gitleaks binary not found in archive"
        exit 1
    }

    Remove-Item -Recurse -Force $tmpDir
}

# Install Zig via install-zig.py
function ensure-zig {
    param([string]$Target)

    $zigVersion = if (Test-Path (Join-Path $script:REPO_ROOT "contrib\setup\zig-version")) {
        Get-Content (Join-Path $script:REPO_ROOT "contrib\setup\zig-version") -ErrorAction SilentlyContinue
    } else { "0.16.0" }
    $zigVersion = $zigVersion.Trim()

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
    python3 (Join-Path $script:SCRIPT_DIR "install-zig.py") @zigArgs
    log-info "Zig installed"
}

# Get platform key for compiler version lookup (windows-x86 or windows-arm)
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
    # Fallback: check $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        return "windows-arm"
    }
    return "windows-x86"
}

# Read compiler version from compiler-versions.json — abort if missing or null
# Usage: read-compiler-version "clang" "windows-x86"
function read-compiler-version {
    param([string]$Tool, [string]$PlatformKey)

    $jsonPath = Join-Path $script:REPO_ROOT "contrib/setup/compiler-versions.json"
    if (-not (Test-Path $jsonPath)) {
        log-error "Compiler versions file missing: $jsonPath"
        exit 1
    }

    $tmpFile = Join-Path $env:TEMP "py_compiler_version_$([Guid]::NewGuid().ToString('N')).txt"
    $pythonPath = Join-Path $script:SCRIPT_DIR "py_read_compiler_version.py"

    # Write the helper script so it accepts output file as argv[1] and
    # writes directly — avoids python3.exe (Microsoft Store shim) stdout
    # redirect issues on Windows PowerShell.
    $escapedJson = $jsonPath.Replace('\', '/')
    $pythonScript = @"
import json, sys
try:
    data = json.load(open('$escapedJson'))
    v = data.get(r'$Tool', {}).get(r'$PlatformKey')
    if v is None:
        sys.exit(1)
    with open(sys.argv[1], 'w') as f:
        f.write(str(v))
except Exception:
    sys.exit(1)
"@
    Set-Content -Path $pythonPath -Value $pythonScript -Encoding UTF8

    try {
        # python3.exe on Windows is the Microsoft Store shim — PowerShell
        # blocks it entirely. Use the Python launcher (py.exe) which is
        # installed alongside Python and bypasses the shim.
        py -3 "$pythonPath" > "$tmpFile" 2>&1

        $result = Get-Content $tmpFile -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0 -or -not $result -or $result.Count -eq 0) {
            log-error "Compiler version not defined for ${Tool} on ${PlatformKey}"
            log-error "Add '${Tool}-${PlatformKey}' to ${jsonPath}"
            exit 1
        }

        Write-Output $result.Trim()
    } finally {
        Remove-Item $pythonPath -ErrorAction SilentlyContinue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }
}

# Detect Windows architecture using detect-windows-arch.sh
function get-windows-arch {
    $arch = bash (Join-Path $script:SCRIPT_DIR "detect-windows-arch.sh") 2>$null
    if ($LASTEXITCODE -eq 0) { return $arch }
    return "x86_64"
}
