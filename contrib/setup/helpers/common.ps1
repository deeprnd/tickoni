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
    $zigVersion = if (Test-Path (Join-Path $script:REPO_ROOT ".zig-version")) {
        Get-Content (Join-Path $script:REPO_ROOT ".zig-version")
    } else { "0.16.0" }

    $zigBin = Join-Path $env:LOCALAPPDATA "Programs\Zig\zig"

    if (Test-Path $zigBin) {
        log-info "Zig $zigVersion already installed"
        $env:PATH = Join-Path $env:LOCALAPPDATA "Programs\Zig" + ";" + $env:PATH
        return
    }

    log-info "Installing Zig $zigVersion..."
    python3 (Join-Path $script:SCRIPT_DIR "install-zig.py") `
        --version $zigVersion `
        --install-root (Join-Path $env:LOCALAPPDATA "Programs") `
        --cache-root (Join-Path $env:LOCALAPPDATA "zig") `
        --user-path
    log-info "Zig installed"
}

# Install Zig bootstrap build
function ensure-zig-bootstrap {
    $zigRef = if (Test-Path (Join-Path $script:REPO_ROOT ".zig-bootstrap-ref")) {
        Get-Content (Join-Path $script:REPO_ROOT ".zig-bootstrap-ref")
    } else { "master" }

    $installRoot = Join-Path $env:LOCALAPPDATA "Programs\zig-bootstrap"

    if (Test-Path (Join-Path $installRoot "zig")) {
        log-info "Zig-bootstrap $zigRef already installed"
        $env:PATH = $installRoot + ";" + $env:PATH
        return
    }

    log-info "Installing Zig-bootstrap (ref=$zigRef)..."
    python3 (Join-Path $script:SCRIPT_DIR "install-zig-bootstrap.py") `
        --bootstrap-ref $zigRef `
        --install-root $installRoot `
        --cache-root (Join-Path $env:LOCALAPPDATA "zig-bootstrap")
    log-info "Zig-bootstrap installed"
}

# Detect Windows architecture using detect-windows-arch.sh
function get-windows-arch {
    $arch = bash (Join-Path $script:SCRIPT_DIR "detect-windows-arch.sh") 2>$null
    if ($LASTEXITCODE -eq 0) { return $arch }
    return "x86_64"
}
