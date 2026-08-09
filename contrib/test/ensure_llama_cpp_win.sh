#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/llama_cpp_env.sh"

usage() {
  cat <<'USAGE'
Usage: contrib/test/ensure_llama_cpp_win.sh [--gpu] [--check-only]

Ensures llama.cpp is cloned and built locally on Windows.
Clones from https://github.com/ggml-org/llama.cpp and builds.

Flags:
  --gpu           build with CUDA support (default: CPU + OpenBLAS)
  --check-only    exit 0 if present, exit 1 if missing (no build)

Environment overrides:
  TK_LLAMA_CPP_DIR  local directory for the llama.cpp checkout
  TK_WINDOWS_CC     explicit C compiler (default: clang, falls back to cl on CI)

Defaults:
  TK_LLAMA_CPP_DIR unset: auto-detects `~/work/models/llama.cpp`
  first, then `~/work/git/llama.cpp`; fresh clones default to
  `~/work/models/llama.cpp`
USAGE
}

check_only=0
gpu_build=0
for arg in "$@"; do
  case "$arg" in
    --cpu)        ;;
    --check-only) check_only=1 ;;
    --gpu)        gpu_build=1 ;;
    --help|-h)    usage; exit 0 ;;
    *)            usage >&2; exit 2 ;;
  esac
done

llama_dir="$(tk_resolve_llama_cpp_dir)"
server_bin="${llama_dir}/llama-server.exe"

# Check if binary exists and backend matches
if [[ -x "$server_bin" ]]; then
  if (( gpu_build == 1 )); then
    echo "llama.cpp present: ${llama_dir}"
    exit 0
  else
    echo "llama.cpp present: ${llama_dir}"
    exit 0
  fi
else
  echo "llama.cpp missing: ${llama_dir}"
fi

if (( check_only )); then
  echo "llama.cpp missing: ${llama_dir}" >&2
  exit 1
fi

for cmd in git cmake ninja; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "${cmd} is required to build llama.cpp but was not found in PATH" >&2
    exit 127
  fi
done

# Prefer MSVC on Windows CI runners (bundled with Visual Studio Build Tools,
# provides UCRT runtime). Fall back to clang if MSVC not available.
# MSVC avoids clang DLL-dependency issues on GitHub Actions Windows runners.
cc="${TK_WINDOWS_CC:-}"
if [[ -z "$cc" ]] && command -v cl >/dev/null 2>&1; then
  cc="cl"
  echo "using MSVC toolchain (cl)"
else
  cc="${TK_WINDOWS_CC:-clang}"
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
  echo "'$cc' not found in PATH; set TK_WINDOWS_CC to an explicit compiler" >&2
  exit 127
fi

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

# Build args
cmake_args=(
  -B "${llama_dir}/build"
  -S "$llama_dir"
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_NATIVE=OFF
)

if [[ "$cc" != "cl" ]]; then
  case "$cc" in
    *clang) cxx="${cc%clang}clang++" ;;
    *gcc)   cxx="${cc%gcc}g++" ;;
    *)      cxx="${CXX:-${cc}++}" ;;
  esac
  cmake_args=(
    -G Ninja
    -DCMAKE_C_COMPILER="$cc"
    -DCMAKE_CXX_COMPILER="$cxx"
    "${cmake_args[@]}"
  )
fi

if (( gpu_build )); then
  echo "building llama.cpp (CUDA) in ${llama_dir}/build"
  cmake "${cmake_args[@]}" \
    -DGGML_CUDA=ON
else
  echo "building llama.cpp (CPU) in ${llama_dir}/build"
  # CPU-only: no OpenBLAS (avoids dynamic DLL dependency on CI runners).
  # Also keep GGML native-tuning disabled on Windows: upstream probes can emit
  # -mcpu=native for clang's default x86_64 Windows target on ARM runners,
  # which fails before compilation starts.
  cmake "${cmake_args[@]}" \
    -DGGML_BLAS=OFF
fi
cmake --build "${llama_dir}/build" --config Release -j 4

echo "copying llama-server.exe to ${llama_dir}"
cp "${llama_dir}/build/bin/llama-server.exe" "${llama_dir}/"

if [[ ! -x "$server_bin" ]]; then
  echo "build finished but llama-server.exe is missing: ${server_bin}" >&2
  exit 1
fi

# Sanity check: make sure it's a real PE binary, not an ELF artifact
if file "$server_bin" 2>/dev/null | grep -qi 'ELF'; then
  echo "warning: llama-server.exe is an ELF binary — wrong toolchain?" >&2
fi

echo "llama.cpp present: ${llama_dir}"
