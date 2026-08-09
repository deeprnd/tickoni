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
  sdk_version="$(find "$sdk_root/Include" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 | xargs -I{} basename "{}")"
  if [[ -z "$sdk_version" ]]; then
    echo "Windows SDK include tree not found under $sdk_root" >&2
    return 1
  fi

  include_root="$sdk_root/Include/$sdk_version"
  lib_root="$sdk_root/Lib/$sdk_version"
  sdk_bin="$sdk_root/bin/$sdk_version/$target"
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

if [[ ! -d "$llama_dir" ]]; then
  echo "cloning llama.cpp into ${llama_dir}"
  git clone https://github.com/ggml-org/llama.cpp "$llama_dir"
else
  echo "directory exists, skipping clone: ${llama_dir}"
fi

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
