#!/usr/bin/env bash
# Ensure llama.cpp is cloned and built locally.
# Uses simple cmake with OpenBLAS (CPU only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/llama_cpp_env.sh"

usage() {
  cat <<'USAGE'
Usage: contrib/setup/ensure_llama_cpp.sh [--check-only]

Ensures llama.cpp is cloned and built locally.
Clones from https://github.com/ggml-org/llama.cpp and builds CPU with OpenBLAS.

Flags:
  --check-only    exit 0 if present, exit 1 if missing (no build)

Environment overrides:
  TK_LLAMA_CPP_DIR    local directory for the llama.cpp checkout

Defaults:
  TK_LLAMA_CPP_DIR unset: auto-detects ~/work/models/llama.cpp
  first, then ~/work/git/llama.cpp
USAGE
}

check_only=0
for arg in "$@"; do
  case "$arg" in
    --check-only) check_only=1 ;;
    --help|-h)    usage; exit 0 ;;
    *)            usage >&2; exit 2 ;;
  esac
done

llama_dir="$(tk_resolve_llama_cpp_dir)"

server_name="llama-server"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) server_name="llama-server.exe" ;;
esac
server_bin="${llama_dir}/${server_name}"
build_dir="${llama_dir}/build"

# Check if binary exists
if [[ -x "$server_bin" ]]; then
  echo "llama.cpp present: ${llama_dir}"
  exit 0
else
  echo "llama.cpp missing: ${llama_dir}"
fi

if (( check_only )); then
  echo "llama.cpp missing: ${llama_dir}" >&2
  exit 1
fi

for cmd in git cmake; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "${cmd} is required to build llama.cpp but was not found in PATH" >&2
    exit 127
  fi
done

# Ensure OpenBLAS is available for CPU builds
if command -v apt-get >/dev/null 2>&1; then
  if ! pkg-config --exists openblas 2>/dev/null; then
    echo "Installing OpenBLAS development package for llama.cpp CPU build..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends libopenblas-dev
  fi
fi

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

# Build with OpenBLAS (no CUDA, no ARM complexity)
echo "building llama.cpp (CPU + OpenBLAS) in ${build_dir}"
cmake -B "${build_dir}" -S "$llama_dir" \
  -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_EXAMPLES=OFF
cmake --build "${build_dir}" --config Release -j "$(nproc)"

# Copy binaries
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    cp "${llama_dir}/build/bin/Release/llama-"* "${llama_dir}/"
    cp "${llama_dir}/build/bin/Release/"*.dll "${llama_dir}/" 2>/dev/null || true
    ;;
  *)
    cp "${llama_dir}/build/bin/llama-"* "${llama_dir}/"
    ;;
esac

if [[ ! -x "$server_bin" ]]; then
  echo "build finished but llama-server binary is missing: ${server_bin}" >&2
  exit 1
fi

echo "llama.cpp present: ${llama_dir}"
