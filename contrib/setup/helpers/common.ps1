# common.ps1 — shared Windows PowerShell functions for contrib/setup/ lane scripts.
# Source this from your lane script (windows-x86.ps1, windows-arm.ps1)

$script:SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:REPO_ROOT = (Get-Item (Join-Path $script:SCRIPT_DIR "..\..")).FullName

function log-info { Write-Host "[setup] $args" }
function log-warn { Write-Host "[setup] WARN: $args" -ForegroundColor Yellow }
function log-error { Write-Host "[setup] ERROR: $args" -ForegroundColor Red }

function tool-exists {
    param([string]$Name)
    return Get-Command $Name -ErrorAction SilentlyContinue
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

# Detect Windows architecture using detect-windows-arch.sh
function get-windows-arch {
    $arch = bash (Join-Path $script:SCRIPT_DIR "detect-windows-arch.sh") 2>$null
    if ($LASTEXITCODE -eq 0) { return $arch }
    return "x86_64"
}
