#!/usr/bin/env bash
set -euo pipefail

normalize_arch() {
  case "${1:-}" in
    arm64|ARM64|Arm64|aarch64|AARCH64)
      echo arm64
      return 0
      ;;
    x86_64|X86_64|amd64|AMD64|x64|X64)
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
    powershell -NoProfile -Command "[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()" 2>/dev/null || true
    return 0
  fi

  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()" 2>/dev/null || true
    return 0
  fi

  if command -v cmd >/dev/null 2>&1; then
    cmd //c "echo %PROCESSOR_ARCHITECTURE% %PROCESSOR_IDENTIFIER%" 2>/dev/null || true
    return 0
  fi

  return 0
}

for candidate in \
  "${TK_WINDOWS_HOST_ARCH:-}" \
  "${MSYSTEM_CARCH:-}" \
  "$(detect_windows_os_arch)" \
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