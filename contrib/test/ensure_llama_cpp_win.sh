#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/llama_cpp_env.sh"

find_msvc_root() {
  local base root latest
  local -a candidates=()

  shopt -s nullglob
  for base in \
    "/c/Program Files (x86)/Microsoft Visual Studio" \
    "/c/Program Files/Microsoft Visual Studio"; do
    [[ -d "$base" ]] || continue
    for root in "$base"/*/{BuildTools,Community,Professional,Enterprise}/VC/Tools/MSVC; do
      [[ -d "$root" ]] || continue
      latest="$(find "$root" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
      [[ -n "$latest" ]] && candidates+=("$latest")
    done
  done
  shopt -u nullglob

  if (( ${#candidates[@]} == 0 )); then
    return 1
  fi

  printf '%s\n' "${candidates[@]}" | sort | tail -n 1
}

resolve_windows_sdk_bin_dir() {
  local sdk_root="$1"
  local sdk_version="$2"
  local target="$3"
  local host_arch="${TK_WINDOWS_HOST_ARCH:-${PROCESSOR_ARCHITECTURE:-}}"
  local -a candidates=()
  local candidate arch

  case "${host_arch,,}" in
    arm64|aarch64) candidates+=(arm64) ;;
    amd64|x86_64)  candidates+=(x64) ;;
    x86)           candidates+=(x86) ;;
  esac

  case "$target" in
    x64|arm64|x86) candidates+=("$target") ;;
  esac

  candidates+=(x64 arm64 x86)

  for arch in "${candidates[@]}"; do
    candidate="$sdk_root/bin/$sdk_version/$arch"
    if [[ -f "$candidate/rc.exe" && -f "$candidate/mt.exe" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_windows_sdk_version() {
  local sdk_root="$1"
  local include_root="$sdk_root/Include"
  local version

  if [[ ! -d "$include_root" ]]; then
    return 1
  fi

  version="$(find "$include_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V | tail -n 1 || true)"
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
    return 0
  fi

  return 1
}

setup_msvc_env() {
  local msvc_root="$1"
  local target="$2"
  local host_bin sdk_root sdk_version include_root lib_root sdk_bin path_prefix

  if [[ -d "$msvc_root/bin/Hostarm64/$target" ]]; then
    host_bin="$msvc_root/bin/Hostarm64/$target"
  elif [[ -d "$msvc_root/bin/Hostx64/$target" ]]; then
    host_bin="$msvc_root/bin/Hostx64/$target"
  else
    echo "MSVC toolchain missing bin directory for target $target under $msvc_root" >&2
    return 1
  fi

  sdk_root="/c/Program Files (x86)/Windows Kits/10"
  sdk_version="$(resolve_windows_sdk_version "$sdk_root" || true)"
  if [[ -z "$sdk_version" ]]; then
    echo "Windows SDK include version dirs not found under $sdk_root/Include" >&2
    find "$sdk_root/Include" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort >&2 || true
    return 1
  fi

  include_root="$sdk_root/Include/$sdk_version"
  lib_root="$sdk_root/Lib/$sdk_version"
  sdk_bin="$(resolve_windows_sdk_bin_dir "$sdk_root" "$sdk_version" "$target" || true)"
  if [[ -z "$sdk_bin" ]]; then
    echo "Windows SDK rc.exe/mt.exe not found under $sdk_root/bin/$sdk_version for target=$target host_arch=${TK_WINDOWS_HOST_ARCH:-${PROCESSOR_ARCHITECTURE:-unknown}}" >&2
    find "$sdk_root/bin/$sdk_version" -maxdepth 2 -type f \( -iname 'rc.exe' -o -iname 'mt.exe' \) 2>/dev/null | sort >&2 || true
    return 1
  fi
  WINDOWS_SDK_RC_EXE="$sdk_bin/rc.exe"
  WINDOWS_SDK_MT_EXE="$sdk_bin/mt.exe"

  export INCLUDE="$(cygpath -w "$msvc_root/include");$(cygpath -w "$include_root/ucrt");$(cygpath -w "$include_root/um");$(cygpath -w "$include_root/shared");$(cygpath -w "$include_root/winrt");$(cygpath -w "$include_root/cppwinrt")"
  export LIB="$(cygpath -w "$msvc_root/lib/$target");$(cygpath -w "$lib_root/ucrt/$target");$(cygpath -w "$lib_root/um/$target")"
  export LIBPATH="$LIB"

  path_prefix="$host_bin"
  [[ -d "$sdk_bin" ]] && path_prefix="$path_prefix:$sdk_bin"
  export PATH="$path_prefix:$PATH"
  export VCINSTALLDIR="$(cygpath -w "$(dirname "$msvc_root")")\\"
  export VCToolsInstallDir="$(cygpath -w "$msvc_root")\\"
  export WindowsSdkDir="$(cygpath -w "$sdk_root")\\"
  export VisualStudioVersion=17.0
  export UCRTVersion="$sdk_version"
}

prepare_windows_sdk_tool_aliases() {
  local build_dir="$1"
  local sdk_bin_dir alias_dir alias_native target_native

  if [[ -z "${WINDOWS_SDK_RC_EXE:-}" || ! -f "${WINDOWS_SDK_RC_EXE}" ]]; then
    echo "Windows SDK rc.exe not found; expected WINDOWS_SDK_RC_EXE to point to an existing file" >&2
    return 1
  fi
  if [[ -z "${WINDOWS_SDK_MT_EXE:-}" || ! -f "${WINDOWS_SDK_MT_EXE}" ]]; then
    echo "Windows SDK mt.exe not found; expected WINDOWS_SDK_MT_EXE to point to an existing file" >&2
    return 1
  fi

  sdk_bin_dir="$(dirname "$WINDOWS_SDK_RC_EXE")"
  mkdir -p "$build_dir"
  alias_dir="$build_dir/windows-sdk-bin"
  alias_native="$(cygpath -w "$alias_dir")"
  target_native="$(cygpath -w "$sdk_bin_dir")"

  python -c 'import shutil, subprocess, sys; link, target = sys.argv[1:3]; shutil.rmtree(link, ignore_errors=True); subprocess.run(["cmd.exe", "/c", "mklink", "/J", link, target], check=True)' "$alias_native" "$target_native"

  windows_sdk_rc_native="$(cygpath -m "$alias_dir/rc.exe")"
  windows_sdk_mt_native="$(cygpath -m "$alias_dir/mt.exe")"

  if [[ ! -f "$alias_dir/rc.exe" || ! -f "$alias_dir/mt.exe" ]]; then
    echo "failed to materialize Windows SDK tool alias dir: $alias_dir" >&2
    return 1
  fi

  echo "using Windows SDK tool alias dir: ${alias_dir}"
  echo "resolved Windows SDK rc path: ${windows_sdk_rc_native}"
  echo "resolved Windows SDK mt path: ${windows_sdk_mt_native}"
}

patch_llama_ui_embed_cpp() {
  local llama_dir="$1"
  local embed_cpp="$llama_dir/tools/ui/embed.cpp"

  if [[ ! -f "$embed_cpp" ]]; then
    return 0
  fi

  if grep -q '^#define __STDC_FORMAT_MACROS$' "$embed_cpp"; then
    return 0
  fi

  awk '
    BEGIN { inserted = 0 }
    $0 == "#include <inttypes.h>" && !inserted {
      print "#define __STDC_FORMAT_MACROS"
      inserted = 1
    }
    { print }
  ' "$embed_cpp" > "$embed_cpp.tmp"
  mv "$embed_cpp.tmp" "$embed_cpp"
  if ! grep -q '^#define __STDC_FORMAT_MACROS$' "$embed_cpp"; then
    echo "failed to patch ${embed_cpp} for PRIx64 C++ macro compatibility" >&2
    return 1
  fi

  echo "patched llama UI embed helper for PRIx64 C++ macro compatibility: ${embed_cpp}"
}

patch_llama_ui_cmake_for_old_windows_gxx() {
  local llama_dir="$1"
  local ui_cmake="$llama_dir/tools/ui/CMakeLists.txt"

  if [[ ! -f "$ui_cmake" ]]; then
    return 0
  fi

  if grep -q 'LLAMA_UI_HOST_CXX_EXTRA_LIBS' "$ui_cmake"; then
    return 0
  fi

  python - "$ui_cmake" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')

needle1 = '    message(STATUS "UI: building llama-ui-embed with host compiler ${HOST_CXX_COMPILER}")\n\n'
insert1 = (
    '    set(LLAMA_UI_HOST_CXX_EXTRA_LIBS "")\n'
    '    if(CMAKE_HOST_WIN32 AND HOST_CXX_COMPILER MATCHES "(^|[/\\\\])g\\\\+\\\\+(\\\\.exe)?$")\n'
    '        execute_process(COMMAND "${HOST_CXX_COMPILER}" -dumpfullversion -dumpversion\n'
    '            OUTPUT_VARIABLE LLAMA_UI_HOST_CXX_VERSION\n'
    '            OUTPUT_STRIP_TRAILING_WHITESPACE\n'
    '            ERROR_QUIET)\n'
    '        if(LLAMA_UI_HOST_CXX_VERSION VERSION_LESS 9)\n'
    '            list(APPEND LLAMA_UI_HOST_CXX_EXTRA_LIBS -lstdc++fs)\n'
    '        endif()\n'
    '    endif()\n\n'
)

needle2 = '        COMMAND "${HOST_CXX_COMPILER}" -O2 -std=c++17\n                -o "${LLAMA_UI_EMBED_EXE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed.cpp"\n'
insert2 = '        COMMAND "${HOST_CXX_COMPILER}" -O2 -std=c++17\n                -o "${LLAMA_UI_EMBED_EXE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed.cpp" ${LLAMA_UI_HOST_CXX_EXTRA_LIBS}\n'

if needle1 not in text or needle2 not in text:
    raise SystemExit(f'failed to find expected UI host compiler snippets in {path}')

text = text.replace(needle1, needle1 + insert1, 1)
text = text.replace(needle2, insert2, 1)
path.write_text(text, encoding='utf-8')
PY

  echo "patched llama UI CMake host compiler link flags for old Windows g++: ${ui_cmake}"
}

prepare_windows_host_cxx_compiler() {
  local build_dir="$1"
  local host_cxx host_cxx_version host_cxx_major wrapper_path host_cxx_native

  host_cxx="$(command -v g++ || command -v clang++ || true)"
  if [[ -z "$host_cxx" ]]; then
    return 0
  fi

  host_cxx_native="$(cygpath -w "$host_cxx")"
  host_cxx_version="$($host_cxx -dumpfullversion -dumpversion 2>/dev/null | head -n 1 || true)"
  host_cxx_major="${host_cxx_version%%.*}"

  if [[ "${TK_WINDOWS_HOST_CXX_FORCE_STDCXXFS:-0}" == "1" ]] || [[ "$(basename "$host_cxx")" == "g++.exe" && "$host_cxx_major" =~ ^[0-9]+$ && "$host_cxx_major" -lt 9 ]]; then
    wrapper_path="$build_dir/host-cxx.cmd"
    cat > "$wrapper_path" <<EOF
@echo off
"${host_cxx_native}" %* -lstdc++fs
EOF
    echo "using Windows host C++ wrapper for filesystem link compatibility: ${wrapper_path} -> ${host_cxx} (${host_cxx_version:-unknown})" >&2
    cygpath -w "$wrapper_path"
    return 0
  fi

  printf '%s\n' "$host_cxx_native"
}

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

host_windows_arch=""
if host_windows_arch="$(bash "${SCRIPT_DIR}/../detect-windows-arch.sh" 2>/dev/null)"; then
  :
else
  host_windows_arch=""
fi
host_windows_arm=0
if [[ "$host_windows_arch" == "arm64" ]]; then
  host_windows_arm=1
fi
echo "Windows llama.cpp host detection: windows_arch=${host_windows_arch:-unknown} uname_m=$(uname -m 2>/dev/null || echo unknown)"

llama_dir="$(tk_resolve_llama_cpp_dir)"
server_bin="${llama_dir}/llama-server.exe"
llama_dir_native="$(cygpath -m "$llama_dir")"
llama_build_dir="${llama_dir}/build"
llama_build_dir_native="$(cygpath -m "$llama_build_dir")"

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

# Prefer MSVC on Windows when available; it brings the CRT import libs that
# upstream llama.cpp needs for a real Windows link. On Windows ARM developer
# machines we only require llama-server.exe itself, so an x64 MSVC lane is fine
# when only x64 CRT libs are installed.
cc="${TK_WINDOWS_CC:-}"
msvc_target=""
force_x64_toolchain=0
if [[ -z "$cc" ]]; then
  if [[ "$host_windows_arm" -eq 0 ]] && command -v cl >/dev/null 2>&1; then
    cc="cl"
    echo "using MSVC toolchain (cl from PATH)"
  else
    vc_root="$(find_msvc_root || true)"
    if [[ -n "$vc_root" ]]; then
      msvc_target=x64
      if [[ "$host_windows_arm" -eq 0 && -f "$vc_root/lib/arm64/oldnames.lib" ]]; then
        msvc_target=arm64
      fi
      echo "resolved MSVC root: ${vc_root}"
      echo "loading MSVC environment from ${vc_root} (${msvc_target})"
      setup_msvc_env "$vc_root" "$msvc_target"
      if [[ "$host_windows_arm" -eq 0 ]] && command -v cl >/dev/null 2>&1; then
        cc="cl"
        echo "using MSVC toolchain (cl via discovered MSVC root)"
      elif [[ "$host_windows_arm" -eq 1 ]] && command -v cl >/dev/null 2>&1; then
        cc="cl"
        force_x64_toolchain=1
        echo "Windows ARM host detected (${host_windows_arch:-unknown}); forcing x64 MSVC toolchain for llama.cpp to avoid ARM backend mixing on CI/local MSYS shells"
      fi
    fi
  fi
fi

cc="${cc:-clang}"

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

echo "selected Windows llama.cpp compiler: $cc"

windows_sdk_rc_native=""
windows_sdk_mt_native=""
host_cxx_compiler_native=""

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

patch_llama_ui_embed_cpp "$llama_dir"
patch_llama_ui_cmake_for_old_windows_gxx "$llama_dir"
mkdir -p "${llama_build_dir}"
host_cxx_compiler_native="$(prepare_windows_host_cxx_compiler "${llama_build_dir}")"

# Build args
cmake_args=(
  -B "${llama_build_dir_native}"
  -S "$llama_dir_native"
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_NATIVE=OFF
)

if [[ "$force_x64_toolchain" -eq 1 ]]; then
  rm -rf "${llama_build_dir}"
  mkdir -p "${llama_build_dir}"
  prepare_windows_sdk_tool_aliases "${llama_build_dir}"
  toolchain_file="$(cd "${llama_build_dir}" && pwd)/tickoni-windows-arm-x64-toolchain.cmake"
  ninja_bin="$(command -v ninja)"
  toolchain_file_native="$(cygpath -w "$toolchain_file")"
  ninja_bin_native="$(cygpath -w "$ninja_bin")"
  cat > "$toolchain_file" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)
set(CMAKE_C_COMPILER cl)
set(CMAKE_CXX_COMPILER cl)
set(CMAKE_RC_COMPILER "${windows_sdk_rc_native}")
set(CMAKE_MT "${windows_sdk_mt_native}")
EOF
  cmake_args=(
    -G Ninja
    -DCMAKE_TOOLCHAIN_FILE=$toolchain_file_native
    -DCMAKE_MAKE_PROGRAM=$ninja_bin_native
    -DCMAKE_C_COMPILER=cl
    -DCMAKE_CXX_COMPILER=cl
    "-DCMAKE_RC_COMPILER=${windows_sdk_rc_native}"
    "-DCMAKE_MT=${windows_sdk_mt_native}"
    "-DHOST_CXX_COMPILER=${host_cxx_compiler_native}"
    "${cmake_args[@]}"
  )
  echo "generated forced-x64 toolchain file: ${toolchain_file}"
elif [[ "$cc" == "cl" ]]; then
  mkdir -p "${llama_build_dir}"
  prepare_windows_sdk_tool_aliases "${llama_build_dir}"
  cmake_args=(
    -G Ninja
    -DCMAKE_C_COMPILER=cl
    -DCMAKE_CXX_COMPILER=cl
    "-DCMAKE_RC_COMPILER=${windows_sdk_rc_native}"
    "-DCMAKE_MT=${windows_sdk_mt_native}"
    "-DHOST_CXX_COMPILER=${host_cxx_compiler_native}"
    "${cmake_args[@]}"
  )
else
  case "$cc" in
    *clang) cxx="${cc%clang}clang++" ;;
    *gcc)   cxx="${cc%gcc}g++" ;;
    *)      cxx="${CXX:-${cc}++}" ;;
  esac
  cmake_args=(
    -G Ninja
    -DCMAKE_C_COMPILER="$cc"
    -DCMAKE_CXX_COMPILER="$cxx"
    "-DHOST_CXX_COMPILER=${host_cxx_compiler_native}"
    "${cmake_args[@]}"
  )
fi

if (( gpu_build )); then
  echo "building llama.cpp (CUDA) in ${llama_build_dir}"
  cmake "${cmake_args[@]}" \
    -DGGML_CUDA=ON
else
  echo "building llama.cpp (CPU) in ${llama_build_dir}"
  # CPU-only: no OpenBLAS (avoids dynamic DLL dependency on CI runners).
  # Also keep GGML native-tuning disabled on Windows: upstream probes can emit
  # -mcpu=native for clang's default x86_64 Windows target on ARM runners,
  # which fails before compilation starts.
  cmake "${cmake_args[@]}" \
    -DGGML_BLAS=OFF
fi
cmake --build "${llama_build_dir_native}" --config Release -j 4

echo "copying llama-server.exe to ${llama_dir}"
cp "${llama_dir}/build/bin/llama-server.exe" "${llama_dir}/"

echo "copying llama-server runtime DLLs to ${llama_dir}"
find "${llama_dir}/build/bin" -maxdepth 1 -type f -name '*.dll' -exec cp {} "${llama_dir}/" \;

if [[ -n "${vc_root:-}" ]]; then
  redist_root="$(cd "$vc_root/../../../Redist/MSVC" 2>/dev/null && pwd || true)"
  if [[ -n "$redist_root" ]]; then
    redist_dir="$(find "$redist_root" -path '*/x64/Microsoft.VC143.CRT' | sort | tail -n 1)"
    if [[ -n "$redist_dir" ]]; then
      for dll in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
        [[ -f "$redist_dir/$dll" ]] && cp "$redist_dir/$dll" "${llama_dir}/"
      done
    fi
  fi
fi

if [[ ! -x "$server_bin" ]]; then
  echo "build finished but llama-server.exe is missing: ${server_bin}" >&2
  exit 1
fi

# Sanity check: make sure it's a real PE binary, not an ELF artifact
if file "$server_bin" 2>/dev/null | grep -qi 'ELF'; then
  echo "warning: llama-server.exe is an ELF binary — wrong toolchain?" >&2
fi

echo "llama.cpp present: ${llama_dir}"
