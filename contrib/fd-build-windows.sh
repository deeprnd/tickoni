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

# Firedancer Makefile passes CC through /usr/bin/sh on MSYS2.
# Paths with spaces (e.g. /c/Program Files/LLVM/bin/clang) get split.
# Detect this and create a no-space symlink, then update CC to use it.
if command -v "$cc" >/dev/null 2>&1; then
  cc_abs="$(command -v "$cc")"
  if [[ "$cc_abs" == *" "* ]]; then
    symlink_dir="/tmp/.tickoni-clang"
    symlink_bin="${symlink_dir}/clang"
    if [[ ! -f "$symlink_bin" ]]; then
      mkdir -p "$symlink_dir"
      ln -sf "$(dirname "$cc_abs")/clang" "$symlink_bin"
    fi
    export PATH="$symlink_dir:$PATH"
    cc="clang"
    export CC="$cc"
    echo "[+] clang path has spaces, using symlink: $cc_abs -> $cc"
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
