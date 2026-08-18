#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=contrib/test/llama_cpp_env.sh
source "${SCRIPT_DIR}/llama_cpp_env.sh"

usage() {
  cat <<'USAGE'
Usage: contrib/test/run_llm_server.sh <cpu|gpu>

Runs llama-server with settings tuned for the selected compute backend.

Environment overrides:
  TK_LLAMA_CPP_DIR    local directory for the llama.cpp checkout
  TK_HF_MODEL_DIR     local directory for the model file
  TK_HF_MODEL_FILE    GGUF filename inside TK_HF_MODEL_DIR

Defaults:
  TK_LLAMA_CPP_DIR unset: auto-detects `~/work/models/llama.cpp`
  first, then `~/work/git/llama.cpp`; fresh clones default to
  `~/work/models/llama.cpp` on POSIX and `~/work/git/llama.cpp` on Windows
  TK_HF_MODEL_DIR=$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF
  TK_HF_MODEL_FILE=gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
USAGE
}

if [[ $# -ne 1 || ( "$1" != "cpu" && "$1" != "gpu" ) ]]; then
  usage >&2
  exit 2
fi
backend="$1"

llama_dir="$(tk_resolve_llama_cpp_dir)"
model_dir="${TK_HF_MODEL_DIR:-$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF}"
model_file="${TK_HF_MODEL_FILE:-gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf}"

server_name="llama-server"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) server_name="llama-server.exe" ;;
esac

case "$model_dir" in
  "~")    model_dir="$HOME" ;;
  "~/"*)  model_dir="$HOME/${model_dir:2}" ;;
esac

server_bin="${llama_dir}/${server_name}"
model_path="${model_dir}/${model_file}"

if [[ ! -x "$server_bin" ]]; then
  echo "llama-server not found: ${server_bin}" >&2
  echo "Run: just infra-ensure-llamacpp" >&2
  exit 1
fi

if [[ ! -f "$model_path" ]]; then
  echo "model not found: ${model_path}" >&2
  echo "Run: just infra-ensure-model" >&2
  exit 1
fi

cpu_cmd=(
  "$server_bin"
  -m "$model_path"
  --no-mmproj
  --reasoning-format none
  --ctx-size 4096
  --cache-type-k q4_0
  --cache-type-v q4_0
  --threads 4
  --batch-size 64
  --ubatch-size 32
  --metrics
  --slots
)

if [[ "$backend" == "cpu" ]]; then
  echo "running: ${cpu_cmd[*]}"
  exec "${cpu_cmd[@]}"
fi

# GPU: check if GPU 0 has enough free VRAM for the model before committing.
model_mb=$(( $(stat -c%s "$model_path") / 1024 / 1024 ))
gpu_free_mb=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i 0 2>/dev/null \
  | tr -d ' ' | head -1 || echo 0)
echo "GPU 0 free: ${gpu_free_mb} MiB  model: ${model_mb} MiB"

if (( gpu_free_mb < model_mb )); then
  echo "GPU 0 does not have enough free VRAM; falling back to cpu" >&2
  echo "running: ${cpu_cmd[*]}"
  exec "${cpu_cmd[@]}"
fi

export CUDA_VISIBLE_DEVICES=0
gpu_cmd=(
  "$server_bin"
  -m "$model_path"
  --no-mmproj
  --reasoning-format none
  --device cuda0
  --split-mode none
  --main-gpu 0
  -ngl all
  --ctx-size 8192
  --cache-type-k q4_0
  --cache-type-v q4_0
  --threads 8
  --threads-batch 8
  --batch-size 64
  --ubatch-size 32
  -np 1
  -fit off
  --metrics
  --slots
  --verbose
)
echo "running: CUDA_VISIBLE_DEVICES=0 ${gpu_cmd[*]}"
exec "${gpu_cmd[@]}"
