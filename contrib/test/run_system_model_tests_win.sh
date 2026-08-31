#!/usr/bin/env bash
# Ensure llama.cpp and model exist, start the local server, run the live
# investment system/demo proof, then stop the server.
# Windows version — mirrors run_system_model_tests.sh but uses llama-server.exe.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=contrib/test/llama_cpp_env.sh
source "${SCRIPT_DIR}/llama_cpp_env.sh"

# Windows CI uses CPU only (no CUDA available).
# Use backend=gpu when running locally on Windows with a CUDA build.
backend="${1:-cpu}"
ensure_args=()
case "$backend" in
  cpu) ;;
  gpu) ensure_args+=(--gpu) ;;
  *)
    echo "usage: $0 [cpu|gpu]" >&2
    exit 2
    ;;
esac

host_windows_arch="$(bash "${SCRIPT_DIR}/../platform.sh" arch 2>/dev/null || echo unknown)"
llama_dir="$(tk_resolve_llama_cpp_dir)"
server_bin="${llama_dir}/llama-server.exe"
model_dir="${TK_HF_MODEL_DIR:-$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF}"
model_file="${TK_HF_MODEL_FILE:-gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf}"
endpoint="${TK_LLM_ENDPOINT:-http://127.0.0.1:9931/v1}"

echo "Windows live system-test config: host_windows_arch=${host_windows_arch} backend=${backend}"
echo "Windows live system-test llama_dir: ${llama_dir}"
echo "Windows live system-test model: ${model_dir}/${model_file}"
echo "Windows live system-test endpoint: ${endpoint}"

# Ensure llama.cpp is built.
bash "${SCRIPT_DIR}/ensure_llama_cpp_win.sh" "${ensure_args[@]}"

# Ensure model is present.
bash "${SCRIPT_DIR}/ensure_hf_model.sh"

# Start server in background.
server_pid=""
log_file="/tmp/llama_server_win_$$.log"
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

echo "starting llama-server.exe (${backend}) — log: ${log_file}"
bash "${SCRIPT_DIR}/run_llm_server_win.sh" "$backend" >"$log_file" 2>&1 &
server_pid=$!

# Wait for the server health endpoint (max 120 s, 2 s poll).
endpoint="${TK_LLM_ENDPOINT:-http://127.0.0.1:9931/v1}"
health_url="${endpoint%/v1}/health"
echo "waiting for llama-server at ${health_url}"
ready=0
for i in $(seq 1 60); do
  if curl -sf "$health_url" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "llama-server.exe exited prematurely; log: ${log_file}" >&2
    head -3 "$log_file" >&2
    echo "..." >&2
    tail -20 "$log_file" >&2
    exit 1
  fi
  sleep 2
done
if (( !ready )); then
  echo "llama-server.exe did not become ready within 120s; log: ${log_file}" >&2
  head -3 "$log_file" >&2
  echo "..." >&2
  tail -20 "$log_file" >&2
  exit 1
fi
echo "llama-server.exe ready"
echo "running live investment system/demo proof (Windows)"

# Run the live system test in foreground. The EXIT trap kills the server.
# Pipe through sed to strip Zig's cosmetic "failed command:" lines (caused by
# --listen=- protocol noise when stdin is closed).
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build \
  -Dtest=true \
  -Dfd-lib-dir=build/fd-tickoni-fd/lib \
  system-test --summary all </dev/null | sed '/^failed command:/d'
