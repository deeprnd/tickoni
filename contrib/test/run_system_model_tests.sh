#!/usr/bin/env bash
# Run the live investment system/demo proof with llama.cpp.
# Orchestrator ensures llama.cpp and model are present.
# Then starts server, waits for health, runs Zig system-test, kills server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve paths
llama_dir="${TK_LLAMA_CPP_DIR:-$HOME/work/models/llama.cpp}"
model_dir="${TK_HF_MODEL_DIR:-$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF}"
model_file="${TK_HF_MODEL_FILE:-gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf}"
model_path="${model_dir}/${model_file}"
server_bin="${llama_dir}/llama-server"

if [[ ! -x "$server_bin" ]]; then
  echo "llama-server not found at ${server_bin}; run 'python3 contrib/setup/orchestrator.py llm-server' first" >&2
  exit 1
fi

if [[ ! -s "$model_path" ]]; then
  echo "model not found at ${model_path}; run 'python3 contrib/setup/orchestrator.py llm-server' first" >&2
  exit 1
fi

# Start server in background.
server_pid=""
log_file="/tmp/llama_server_$$.log"
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

echo "starting llama-server — log: ${log_file}"
"$server_bin" \
  -m "$model_path" \
  --port 9931 \
  --no-mmproj \
  --reasoning-format none \
  --ctx-size 4096 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --threads 4 \
  --batch-size 64 \
  --ubatch-size 32 \
  --metrics \
  --slots \
  >"$log_file" 2>&1 &
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
    echo "llama-server exited prematurely; log: ${log_file}" >&2
    head -3 "$log_file" >&2
    echo "..." >&2
    tail -20 "$log_file" >&2
    exit 1
  fi
  sleep 2
done
if (( !ready )); then
  echo "llama-server did not become ready within 120s; log: ${log_file}" >&2
  head -3 "$log_file" >&2
  echo "..." >&2
  tail -20 "$log_file" >&2
  exit 1
fi
echo "llama-server ready"
echo "running live investment system/demo proof"

# Run the live system test in foreground. The EXIT trap kills the server.
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache zig build -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib system-test --summary all </dev/null | sed '/^failed command:/d'
