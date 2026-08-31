#!/usr/bin/env bash
# Ensure llama.cpp and model exist, start the local server, run the live
# investment system/demo proof, then stop the server.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=contrib/test/llama_cpp_env.sh
source "${SCRIPT_DIR}/llama_cpp_env.sh"

# Detect compute backend: GPU only if nvidia-smi reports devices AND the
# llama.cpp binary was compiled with CUDA support.
llama_dir="$(tk_resolve_llama_cpp_dir)"

server_name="llama-server"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) server_name="llama-server.exe" ;;
esac

backend=cpu
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l || echo 0)"
  if (( gpu_count > 0 )); then
    if ldd "${llama_dir}/${server_name}" 2>/dev/null | grep -qi 'cuda\|cublas'; then
      backend=gpu
    else
      echo "note: GPU detected but llama.cpp binary has no CUDA support; using cpu"
    fi
  fi
fi
echo "compute backend: ${backend}"

# Ensure llama.cpp is built for the detected backend.
if [[ "$backend" == "gpu" ]]; then
  bash "${SCRIPT_DIR}/ensure_llama_cpp.sh" --gpu
else
  bash "${SCRIPT_DIR}/ensure_llama_cpp.sh"
fi

# Ensure model is present.
bash "${SCRIPT_DIR}/ensure_hf_model.sh"

# Start server and tests as separate background channels.
# Either channel dying kills the other.
server_pid=
log_file="/tmp/llama_server_$$.log"
cleanup() {
  [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n "$server_pid" ]] && wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

echo "starting llama-server (${backend}) — log: ${log_file}"
bash "${SCRIPT_DIR}/run_llm_server.sh" "$backend" >"$log_file" 2>&1 &
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
# Pipe through sed to strip Zig's cosmetic "failed command:" lines (caused by
# --listen=- protocol noise when stdin is closed).
ZIG_GLOBAL_CACHE_DIR=.zig-global-cache bash contrib/build/zigw.sh build -Dtest=true -Dfd-lib-dir=build/fd-tickoni-fd/lib system-test --summary all </dev/null | sed '/^failed command:/d'
