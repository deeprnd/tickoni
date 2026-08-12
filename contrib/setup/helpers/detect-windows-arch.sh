#!/usr/bin/env bash
set -euo pipefail

normalize_arch() {
  case "${1:-}" in
    arm64|ARM64|aarch64|AARCH64)
      echo arm64
      return 0
      ;;
    x86_64|X86_64|amd64|AMD64)
      echo x86_64
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

for candidate in \
  "${TK_WINDOWS_HOST_ARCH:-}" \
  "${MSYSTEM_CARCH:-}" \
  "${PROCESSOR_ARCHITEW6432:-}" \
  "${PROCESSOR_ARCHITECTURE:-}" \
  "$(uname -m 2>/dev/null || true)" \
; do
  if normalized="$(normalize_arch "$candidate")"; then
    printf '%s\n' "$normalized"
    exit 0
  fi
done

echo "unable to detect Windows architecture" >&2
exit 1