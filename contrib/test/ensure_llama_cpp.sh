#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=contrib/test/llama_cpp_env.sh
source "${SCRIPT_DIR}/llama_cpp_env.sh"

usage() {
  cat <<'USAGE'
Usage: contrib/test/ensure_llama_cpp.sh [--gpu] [--check-only]

Ensures llama.cpp is cloned and built locally. If the directory is missing,
clones from https://github.com/ggml-org/llama.cpp and builds.

Flags:
  --gpu           build with CUDA support (default: CPU + OpenBLAS)
  --check-only    exit 0 if present, exit 1 if missing (no build)

Environment overrides:
  TK_LLAMA_CPP_DIR    local directory for the llama.cpp checkout

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
    --check-only) check_only=1 ;;
    --gpu)        gpu_build=1 ;;
    --help|-h)    usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

llama_dir="$(tk_resolve_llama_cpp_dir)"

server_bin="${llama_dir}/llama-server"

if [[ -x "$server_bin" ]]; then
  # Rebuild if the binary's backend doesn't match the requested one.
  has_cuda=$(ldd "$server_bin" 2>/dev/null | grep -ci 'cuda\|cublas' || echo 0)
  if (( gpu_build == 1 && has_cuda == 0 )); then
    echo "binary exists but lacks CUDA; rebuilding with CUDA"
    # fall through to rebuild
  elif (( gpu_build == 0 && has_cuda > 0 )); then
    echo "binary has CUDA but CPU build requested; rebuilding CPU-only"
    rm -rf "${llama_dir}/build"
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

# Ensure OpenBLAS is available for CPU + OpenBLAS builds
if ! command -v cmake >/dev/null 2>&1; then
    : # cmake not available, can't check/fix deps
elif (( gpu_build == 0 )); then
    if ! pkg-config --exists openblas 2>/dev/null && \
       ! ldconfig -p 2>/dev/null | grep -q libopenblas && \
       ! ldconfig -p 2>/dev/null | grep -q libblas && \
       ! find /usr/include /usr/local/include /opt -maxdepth 3 -name "cblas.h" -print -quit 2>/dev/null | grep -q .; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "Installing OpenBLAS development package for llama.cpp CPU build..."
            sudo apt-get update -qq
            sudo apt-get install -y --no-install-recommends libopenblas-dev
        fi
    fi
fi

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

if (( gpu_build )); then
  echo "building llama.cpp (CUDA) in ${llama_dir}/build"
  cmake -B "${llama_dir}/build" -S "$llama_dir" -DGGML_CUDA=ON
else
  echo "building llama.cpp (CPU + OpenBLAS) in ${llama_dir}/build"
  cmake -B "${llama_dir}/build" -S "$llama_dir" \
    -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
fi
cmake --build "${llama_dir}/build" --config Release -j 4

echo "copying llama-* binaries to ${llama_dir}"
cp "${llama_dir}/build/bin/llama-"* "${llama_dir}/"

if [[ ! -x "$server_bin" ]]; then
  echo "build finished but llama-server binary is missing: ${server_bin}" >&2
  exit 1
fi

echo "llama.cpp present: ${llama_dir}"
