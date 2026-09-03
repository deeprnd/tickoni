#!/usr/bin/env bash
# install-openssl.sh — Build OpenSSL 3.6.4 from source
# This is the openssl-3.6.4 build from deps.sh, extracted as a standalone
# helper so our setup scripts don't need deps.sh at all.
#
# Usage: bash contrib/setup/helpers/install-openssl.sh [--prefix PATH]
# Defaults to PREFIX=./build/opt (matching Firedancer's default OPT=build/opt)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../../.." && pwd)"

# ── Platform detection ────────────────────────────────────────────────────────
# Single source of truth for OS/arch — used by callers that need it.
source "${SCRIPT_DIR}/../../platform.sh"

PREFIX="$(cd -- "${REPO_ROOT}" && pwd)/build/opt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -pv "${PREFIX}"

# ── Common config flags (from deps.sh install_openssl) ────────────────────────
# Minimal config: TLS 1.3 only, static libs, no shared libs, no ASM
CONFIG_OPTS=(
  -fPIC
  --prefix="${PREFIX}"
  --libdir=lib
  threads
  no-engine
  no-static-engine
  no-weak-ssl-ciphers
  no-autoload-config
  no-tls1
  no-tls1-method
  no-tls1_1
  no-tls1_1-method
  no-tls1_2
  no-tls1_2-method
  enable-tls1_3
  no-shared
  no-legacy
  no-tests
  no-ui-console
  no-sctp
  no-ssl3
  no-aria
  no-argon2
  no-bf
  no-blake2
  no-camellia
  no-cast
  no-cmac
  no-cmp
  no-cms
  no-comp
  no-ct
  no-des
  no-dsa
  no-dtls
  no-dtls1-method
  no-dtls1_2-method
  no-fips
  no-gost
  no-idea
  no-ktls
  no-md4
  no-nextprotoneg
  no-ocb
  no-ocsp
  no-rc2
  no-rc4
  no-rc5
  no-rmd160
  no-scrypt
  no-seed
  no-siphash
  no-siv
  no-sm3
  no-sm4
  no-srp
  no-srtp
  no-ts
  no-whirlpool
)

# ── Linux ────────────────────────────────────────────────────────────────────
build_linux() {
  echo "[openssl] Building OpenSSL 3.6.4 for Linux ($(uname -m))"
  local src_dir="${PREFIX}/git/openssl"

  cd "${src_dir}"

  # Apply config patches for Linux (deps.sh lines 543-544)
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "$(uname -m)" in
    x86_64|i686) cf_opts+=" -fcf-protection=return" ;;
  esac
  CFLAGS="${cf_opts}" \
    CXXFLAGS="${cf_opts}" \
    ./config "${CONFIG_OPTS[@]}"

  make -j build_libs
  make -j install_dev

  echo "[openssl] Installed to ${PREFIX}"
}

# ── macOS ────────────────────────────────────────────────────────────────────
build_macos() {
  echo "[openssl] Building OpenSSL 3.6.4 for macOS"

  # OpenSSL 3.6.4 needs flex and gettext; brew's gettext conflicts with
  # Firedancer's bundled libgettext, so it's hidden from PATH during the
  # build below (not uninstalled — `brew uninstall` would tear out
  # libintl.dylib from under every other installed formula linked against
  # it, e.g. Homebrew's own git).
  brew install flex gettext 2>/dev/null || true

  local src_dir="${PREFIX}/git/openssl"
  cd "${src_dir}"

  # On macOS we can't have 'gettext' in PATH during configure because
  # Firedancer bundles its own libgettext.  Work around by temporarily
  # renaming it and restoring afterward.
  GETTEXT_BIN="/usr/local/opt/gettext/bin"
  if [[ ! -d "${GETTEXT_BIN}" ]]; then
    GETTEXT_BIN="/opt/homebrew/opt/gettext/bin"
  fi
  if [[ -d "${GETTEXT_BIN}" ]]; then
    echo "[openssl] Temporarily hiding gettext from PATH..."
    for bin in "${GETTEXT_BIN}"/*; do
      if [[ -x "$bin" && ! -L "$bin" ]]; then
        mv "$bin" "${bin}.__FD_SKIP__"
      fi
    done
  fi

  # -fcf-protection=return is x86-only
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "$(uname -m)" in
    x86_64) cf_opts+=" -fcf-protection=return" ;;
  esac
  # Clear host CPPFLAGS/HOSTCFLAGS — CI runners may have -fcf-protection=return
  # (x86 CET flag) which clang on arm64 rejects.  OpenSSL ./config inherits
  # env vars; we must wipe host toolchain flags to avoid leaking non-portable
  # options into the generated Makefile.
  CFLAGS="${cf_opts}" \
    CXXFLAGS="${cf_opts}" \
    CPPFLAGS="" \
    HOSTCFLAGS="" \
    ./config "${CONFIG_OPTS[@]}"

  make -j build_libs
  make -j install_dev

  # Restore gettext
  if [[ -d "${GETTEXT_BIN}" ]]; then
    for bin in "${GETTEXT_BIN}"/*.__FD_SKIP__; do
      if [[ -e "$bin" ]]; then
        mv "$bin" "${bin%%.__FD_SKIP__}"
      fi
    done
  fi

  echo "[openssl] Installed to ${PREFIX}"
}

# ── Windows (MSVC via cl.exe/nmake) ───────────────────────────────────────────
# Uses native MSVC compiler (cl.exe) + nmake from VS Build Tools.
# Git Bash provides bash/perl/make for the build harness.
# No MinGW-w64, no MSYS2 gcc, no cross-compiler needed.
# IMPORTANT: Must activate MSVC env via vcvarsall.bat before running nmake.
build_windows() {
  echo "[openssl] Building OpenSSL 3.6.2 for Windows (MSVC)"
  local src_dir="${PREFIX}/git/openssl"
  cd "${src_dir}"

  # Determine architecture for the OpenSSL target.
  # FD_WINDOWS_ARCH is set by the caller (arm64/x86_64).
  # Default to current architecture.
  local windows_arch="${FD_WINDOWS_ARCH:-$(uname -m)}"

  # OpenSSL target for Windows.
  # ARM64: VC-WIN64-ARM (uses MSVC cl.exe + nmake)
  # x86_64: VC-WIN64A (uses MSVC cl.exe + nmake)
  local openssl_target
  if [[ "${windows_arch}" =~ ^(arm64|aarch64)$ ]]; then
    openssl_target="VC-WIN64-ARM"
  else
    openssl_target="VC-WIN64A"
  fi

  # Ensure Text::Template >= 1.46 is available for OpenSSL Configure.
  # Git for Windows includes Strawberry Perl which bundles Text::Template.
  # CPAN will auto-fetch it if missing (prerequisites_policy=follow).
  if ! perl -e 'use Text::Template 1.46' 2>/dev/null; then
    echo "[openssl] Installing Text::Template via CPAN..."
    # Prepend Strawberry Perl to PATH so perl resolves correctly.
    local strawberry_perl_bin="/c/Strawberry/perl/bin"
    if [[ -d "${strawberry_perl_bin}" ]]; then
      export PATH="${strawberry_perl_bin}:${PATH}"
    fi
    perl -MCPAN -e 'CPAN::install("Text::Template")' 2>&1 && \
      echo "[openssl] Text::Template installed successfully" || \
      { echo "[openssl] Failed to install Text::Template"; exit 1; }
  fi

  # -fcf-protection=return is x86-only
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "${windows_arch}" in
    x86_64|x64|i686|x86) cf_opts+=" -fcf-protection=return" ;;
  esac

  local prefix_win
  prefix_win="$(cygpath -aw "${PREFIX}")"
  local config_opts=("${CONFIG_OPTS[@]}")
  config_opts[1]="--prefix=${prefix_win}"

  # For MSVC targets, CFLAGS are passed via the compiler invocation
  # OpenSSL's msvc targets use nmake, not make, so we pass flags differently
  # Use CFLAGS for MSVC-compatible flags that will be picked up
  CFLAGS="${cf_opts}" \
    CXXFLAGS="${cf_opts}" \
    perl ./Configure "${openssl_target}" "${config_opts[@]}"

  # Activate MSVC environment (VS Build Tools / Developer Command Prompt).
  # Without this, nmake is not in PATH inside Git Bash and GNU make cannot
  # read the MSVC-style Makefile generated by OpenSSL Configure.
  if [[ "${windows_arch}" =~ ^(arm64|aarch64)$ ]]; then
    local vc_target="arm64"
  else
    local vc_target="x64"
  fi

  # Try VS 2026 first, then VS 2022, then VS 2019.
  local vcvars_path=""
  for candidate in \
    "/c/Program Files/Microsoft Visual Studio/2026/BuildTools/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2026/Community/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2026/Professional/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2026/Enterprise/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files (x86)/Microsoft Visual Studio/2022/Community/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2022/Professional/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvarsall.bat" \
    "/c/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvarsall.bat"; do
    if [[ -f "${candidate}" ]]; then
      vcvars_path="${candidate}"
      break
    fi
  done

  if [[ -z "${vcvars_path}" ]]; then
    echo "[openssl] ERROR: vcvarsall.bat not found — MSVC Build Tools must be installed" >&2
    exit 1
  fi

  local vcvars_win
  vcvars_win="$(cygpath -aw "${vcvars_path}")"
  local nmake_path=""
  for candidate in \
    "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostarm64/arm64/nmake.exe \
    "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostarm64/x64/nmake.exe \
    "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64/nmake.exe \
    "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostarm64/arm64/nmake.exe \
    "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostarm64/x64/nmake.exe \
    "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64/nmake.exe; do
    if [[ -f "${candidate}" ]]; then
      nmake_path="${candidate}"
      break
    fi
  done

  if [[ -z "${nmake_path}" ]]; then
    echo "[openssl] ERROR: nmake.exe not found under Visual Studio Build Tools" >&2
    exit 1
  fi

  local nmake_dir_win
  nmake_dir_win="$(cygpath -aw "$(dirname "${nmake_path}")")"
  local runner_cmd
  runner_cmd="${src_dir}/fd-openssl-build.cmd"
  cat >"${runner_cmd}" <<EOF
@echo off
call "${vcvars_win}" ${vc_target}
if errorlevel 1 exit /b %errorlevel%
set "PATH=${nmake_dir_win};%PATH%"
nmake /NOLOGO build_libs
if errorlevel 1 exit /b %errorlevel%
nmake /NOLOGO install_dev
EOF

  echo "[openssl] Activating MSVC environment (${vc_target}) via ${vcvars_path##*/}..."
  # Run nmake inside a cmd session with vcvarsall activated;
  # capture stdout/stderr so failures show in CI logs.
  cmd.exe /c "$(cygpath -aw "${runner_cmd}")" 2>&1 || { echo "[openssl] OpenSSL build failed" >&2; rm -f "${runner_cmd}"; exit 1; }
  rm -f "${runner_cmd}"

  echo "[openssl] Installed to ${PREFIX}"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "$(tk_os)" in
  linux)     build_linux     ;;
  macos)     build_macos     ;;
  windows)   build_windows   ;;
  *) echo "[!] Unsupported OS $(tk_os)" >&2; exit 1 ;;
esac

# Remove cmake and pkgconfig files so we don't accidentally depend on them
rm -rf "${PREFIX}/lib/cmake" "${PREFIX}/lib/pkgconfig" 2>/dev/null || true

echo "[openssl] Done."
