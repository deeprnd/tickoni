#!/usr/bin/env bash

# tk_expand_home expands a leading tilde in a path.
tk_expand_home() {
  local path="$1"
  local expanded

  case "$path" in
    "~")   expanded="$HOME" ;;
    "~/"*) expanded="$HOME/${path:2}" ;;
    *)      expanded="$path" ;;
  esac

  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$expanded"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$expanded"
}

# tk_resolve_llama_cpp_dir resolves the llama.cpp checkout directory.
#
# Resolution order:
# 1. TK_LLAMA_CPP_DIR, when set
# 2. First existing directory from the built-in candidates below
# 3. Platform-specific fallback default path for fresh clones
#
# The function prints the resolved directory to stdout.
tk_resolve_llama_cpp_dir() {
  if [[ -n "${TK_LLAMA_CPP_DIR:-}" ]]; then
    tk_expand_home "$TK_LLAMA_CPP_DIR"
    return 0
  fi

  local default_clone_dir="$(tk_expand_home '~/work/models/llama.cpp')"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) default_clone_dir="$(tk_expand_home '~/work/git/llama.cpp')" ;;
  esac

  local candidate
  for candidate in \
    "$(tk_expand_home '~/work/models/llama.cpp')" \
    "$(tk_expand_home '~/work/git/llama.cpp')"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "$default_clone_dir"
}
