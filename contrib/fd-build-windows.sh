#!/usr/bin/env bash
# Build Firedancer libs for Tickoni on native Windows runners.
# Usage:
#   bash contrib/fd-build-windows.sh [arch] [compiler]
#   arch: x86_64|arm64 (default: host arch)
#   compiler: clang by default (matches checked-in Windows CI lanes)
set -euo pipefail
cd "$(dirname "$0")/.."

raw_arch="${1:-$(bash contrib/detect-windows-arch.sh)}"
cc="${2:-${TK_WINDOWS_CC:-clang}}"

clang_header_for() {
  local compiler="$1"
  local target="${2:-x86_64-pc-windows-msvc}"
  local header
  header="$("$compiler" --target="$target" -print-file-name=include/x86intrin.h 2>/dev/null || true)"
  if [[ -n "$header" && -f "$header" ]]; then
    printf '%s\n' "$header"
    return 0
  fi
  return 1
}

prefer_llvm_clang() {
  local requested="$1"
  local current=""
  if command -v "$requested" >/dev/null 2>&1; then
    current="$(command -v "$requested")"
    if clang_header_for "$current" >/dev/null 2>&1; then
      printf '%s\n' "$current"
      return 0
    fi
  fi

  local llvm_paths=("/c/Program Files/LLVM/bin")
  if [[ -n "${LOCALAPPDATA:-}" ]] && command -v cygpath >/dev/null 2>&1; then
    local local_appdata_unix
    local_appdata_unix="$(cygpath -u "$LOCALAPPDATA")"
    for root in "$local_appdata_unix"/Microsoft/WinGet/Packages/LLVM.LLVM_*; do
      [[ -d "$root" ]] || continue
      llvm_paths+=("$root" "$root/bin")
    done
  fi

  local llvm_path candidate
  for llvm_path in "${llvm_paths[@]}"; do
    [[ -d "$llvm_path" ]] || continue
    candidate="$llvm_path/$requested"
    if [[ -x "$candidate" ]] && clang_header_for "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [[ -n "$current" ]]; then
    printf '%s\n' "$current"
    return 0
  fi
  return 1
}

if [[ "$cc" == clang* ]]; then
  current_clang="$(command -v "$cc" 2>/dev/null || true)"
  if preferred_clang="$(prefer_llvm_clang "$cc")"; then
    if [[ -n "$current_clang" && "$preferred_clang" != "$current_clang" ]]; then
      echo "[+] preferring LLVM clang with x86intrin.h: $preferred_clang"
    fi
    cc="$preferred_clang"
  fi
fi

# Firedancer Makefile passes CC through /usr/bin/sh on MSYS2.
# Paths with spaces (e.g. /c/Program Files/LLVM/bin/clang) get split.
# Detect this and create a no-space alias for the whole LLVM tree so clang's
# relative ../lib/clang resource-dir lookup (e.g. x86intrin.h) still works.
if command -v "$cc" >/dev/null 2>&1; then
  cc_abs="$(command -v "$cc")"
  if [[ "$cc_abs" == *" "* ]]; then
    llvm_bin_dir="$(dirname "$cc_abs")"
    llvm_root_dir="$(cd "$llvm_bin_dir/.." && pwd -P)"
    symlink_root="/tmp/.tickoni-llvm"
    symlink_bin="${symlink_root}/bin"
    if [[ ! -e "$symlink_root" ]]; then
      ln -s "$llvm_root_dir" "$symlink_root"
    fi
    export PATH="$symlink_bin:$PATH"
    cc="clang"
    export CC="$cc"
    echo "[+] clang path has spaces, using LLVM tree alias: $cc_abs -> ${symlink_bin}/clang"
  fi
fi

if ! command -v "$cc" >/dev/null 2>&1; then
  llvm_paths=("/c/Program Files/LLVM/bin")
  if [[ -n "${LOCALAPPDATA:-}" ]] && command -v cygpath >/dev/null 2>&1; then
    local_appdata_unix="$(cygpath -u "$LOCALAPPDATA")"
    for root in "$local_appdata_unix"/Microsoft/WinGet/Packages/LLVM.LLVM_*; do
      [[ -d "$root" ]] || continue
      llvm_paths+=("$root" "$root/bin")
    done
  fi

  for llvm_path in "${llvm_paths[@]}"; do
    [[ -d "$llvm_path" ]] || continue
    PATH="$llvm_path:$PATH"
    if command -v "$cc" >/dev/null 2>&1; then
      break
    fi
  done
fi

if ! command -v "$cc" >/dev/null 2>&1; then
  echo "Windows compiler '$cc' not found on PATH; install LLVM or set TK_WINDOWS_CC to an explicit compiler path" >&2
  exit 127
fi

case "$raw_arch" in
  x86_64|amd64)
    fd_windows_arch="x86_64"
    ;;
  aarch64|arm64)
    fd_windows_arch="arm64"
    ;;
  *)
    echo "unsupported Windows arch for fd build: $raw_arch" >&2
    exit 1
    ;;
esac

echo "[+] Windows FD build arch=${fd_windows_arch} cc=${cc}"
env FD_WINDOWS_ARCH="$fd_windows_arch" bash contrib/fd-build-lib.sh fd-tickoni-fd "$cc"

# Post-build: compile libuuid_stub.c into a proper libuuid.a archive.
# The prebuilt Windows FD libs reference libuuid.a as a library
# dependency. Zig's C source-file inclusion (addCSourceFiles) only
# adds the .obj to the link — it does NOT satisfy the linker's
# library lookup for libuuid.a. We need an actual static archive.
libdir="build/fd-tickoni-fd/lib"
libdir_native="build/native/gcc/lib"
archive_tool="${AR:-}"
if [[ -z "$archive_tool" ]]; then
  candidates=()
  case "${cc:-gcc}" in
    clang*|clang++*|clang-cl*) candidates=(llvm-ar gcc-ar ar) ;;
    *) candidates=(gcc-ar ar llvm-ar) ;;
  esac
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      archive_tool="$candidate"
      break
    fi
  done
fi

if [[ -z "$archive_tool" ]]; then
  echo "No archive tool found for Windows FD build; set AR or install one of: gcc-ar, llvm-ar, ar" >&2
  exit 127
fi

for dir in "$libdir" "$libdir_native"; do
  if [ -d "$dir" ]; then
    echo "[+] Building libuuid.a from stub in ${dir}"
    # --target is a Clang-only flag. MinGW-w64 gcc is already cross-compiled
    # for Windows and rejects --target. Detect compiler and pass flags
    # accordingly.
    target_flags=""
    case "${cc:-gcc}" in
      clang*|clang++*|clang-cl*)
        target_flags="--target=${fd_windows_arch}-windows-msvc"
        ;;
    esac
    ${cc:-gcc} -c -o "${dir}/libuuid_stub.obj" \
      ${target_flags} \
      -I src \
      -DFD_HAS_HOSTED=1 \
      -DFD_USING_MSVC=1 \
      src/tickoni/c_abi/shim/libuuid_stub.c
    "${archive_tool}" rcs "${dir}/libuuid.a" "${dir}/libuuid_stub.obj"
    rm -f "${dir}/libuuid_stub.obj"
  fi
done
