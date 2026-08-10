#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: contrib/test/ensure_hf_model.sh [--check-only]

Ensures the real-LLM smoke-test GGUF exists locally. If it is missing,
downloads it with `hf download`.

Environment overrides:
  TK_HF_REPO_ID       Hugging Face repo id
  TK_HF_MODEL_FILE    GGUF filename inside the repo
  TK_HF_MODEL_DIR     local directory for the model file

Defaults:
  TK_HF_REPO_ID=unsloth/gemma-4-E2B-it-qat-GGUF
  TK_HF_MODEL_FILE=gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf
  TK_HF_MODEL_DIR=$HOME/work/models/gemma/gemma-4-E2B-it-qat-GGUF
USAGE
}

ensure_hf_cli() {
  local scripts_dir user_scripts_dir scripts_dir_unix user_scripts_dir_unix

  if command -v hf >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v python >/dev/null 2>&1; then
    return 1
  fi

  scripts_dir="$(python - <<'PY'
import sysconfig
print(sysconfig.get_path('scripts') or '')
PY
)"

  user_scripts_dir="$(python - <<'PY'
import sysconfig
paths = []
for scheme in ('nt_user', 'posix_user'):
    if scheme in sysconfig.get_scheme_names():
        path = sysconfig.get_path('scripts', scheme=scheme)
        if path:
            paths.append(path)
print(paths[0] if paths else '')
PY
)"

  if [[ -n "$scripts_dir" ]]; then
    scripts_dir_unix="$scripts_dir"
    if command -v cygpath >/dev/null 2>&1; then
      scripts_dir_unix="$(cygpath -u "$scripts_dir")"
    fi
    export PATH="$scripts_dir_unix:$PATH"
  fi

  if [[ -n "$user_scripts_dir" ]]; then
    user_scripts_dir_unix="$user_scripts_dir"
    if command -v cygpath >/dev/null 2>&1; then
      user_scripts_dir_unix="$(cygpath -u "$user_scripts_dir")"
    fi
    export PATH="$user_scripts_dir_unix:$PATH"
  fi

  if command -v hf >/dev/null 2>&1; then
    return 0
  fi

  echo "hf not found; installing huggingface_hub CLI with python -m pip --user" >&2
  python -m pip install --user "huggingface_hub[cli]"

  if [[ -n "${scripts_dir_unix:-}" ]]; then export PATH="$scripts_dir_unix:$PATH"; fi
  if [[ -n "${user_scripts_dir_unix:-}" ]]; then export PATH="$user_scripts_dir_unix:$PATH"; fi

  command -v hf >/dev/null 2>&1
}

check_only=0
if [[ "${1:-}" == "--check-only" ]]; then
  check_only=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

repo_id="${TK_HF_REPO_ID:-unsloth/gemma-4-E2B-it-qat-GGUF}"
model_file="${TK_HF_MODEL_FILE:-gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf}"
default_model_dir="$HOME/work/models/gemma"
default_model_dir="${default_model_dir}/gemma-4-E2B-it-qat-GGUF"
model_dir="${TK_HF_MODEL_DIR:-$default_model_dir}"

case "$model_dir" in
  "~")
    model_dir="$HOME"
    ;;
  "~/"*)
    model_dir="$HOME/${model_dir:2}"
    ;;
esac

model_path="${model_dir}/${model_file}"

if [[ -s "$model_path" ]]; then
  echo "model present: ${model_path}"
  exit 0
fi

if (( check_only )); then
  echo "model missing: ${model_path}" >&2
  exit 1
fi

if ! ensure_hf_cli; then
  echo "hf is required to download ${repo_id}/${model_file}" >&2
  echo "Install the Hugging Face CLI so the `hf` command is available, then rerun this command." >&2
  exit 127
fi

mkdir -p "$model_dir"

echo "model missing: ${model_path}"
echo "downloading ${repo_id}/${model_file} with hf"
hf download "$repo_id" "$model_file" --local-dir "$model_dir"

if [[ ! -s "$model_path" ]]; then
  echo "download finished but model file is still missing: ${model_path}" >&2
  exit 1
fi

echo "model present: ${model_path}"
