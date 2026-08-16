#!/usr/bin/env bash
set -euo pipefail

normalize_arch() {
  local raw="${1:-}"
  raw="$(printf '%s' "$raw" | tr -d '\r' | tr -d '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "${raw,,}" in
    arm64|aarch64|arm64-bit*|arm\ 64-bit*|*arm64*)
      echo arm64
      return 0
      ;;
    x86_64|amd64|x64|x86-64*|*amd64*|*x64*)
      echo x86_64
      return 0
      ;;
    12)
      echo arm64
      return 0
      ;;
    9)
      echo x86_64
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

detect_windows_os_arch() {
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command "(Get-ComputerInfo).OsArchitecture" 2>/dev/null || true
    powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)" 2>/dev/null || true
    reg query 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment' /v PROCESSOR_ARCHITECTURE 2>/dev/null || true
    return 0
  fi

  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "(Get-ComputerInfo).OsArchitecture" 2>/dev/null || true
    pwsh -NoProfile -Command "(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Architecture)" 2>/dev/null || true
    reg query 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment' /v PROCESSOR_ARCHITECTURE 2>/dev/null || true
    return 0
  fi

  if command -v cmd >/dev/null 2>&1; then
    cmd //c "echo %PROCESSOR_ARCHITECTURE% %PROCESSOR_IDENTIFIER%" 2>/dev/null || true
    reg query 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment' /v PROCESSOR_ARCHITECTURE 2>/dev/null || true
    return 0
  fi

  return 0
}

for candidate in \
  "${TK_WINDOWS_HOST_ARCH:-}" \
  "$(detect_windows_os_arch)" \
  "${MSYSTEM_CARCH:-}" \
  "${PROCESSOR_ARCHITEW6432:-}" \
  "${PROCESSOR_ARCHITECTURE:-}" \
  "${PROCESSOR_IDENTIFIER:-}" \
  "$(uname -m 2>/dev/null || true)" \
; do
  if normalized="$(normalize_arch "$candidate")"; then
    printf '%s\n' "$normalized"
    exit 0
  fi
done

echo "unable to detect Windows architecture" >&2
exit 1
