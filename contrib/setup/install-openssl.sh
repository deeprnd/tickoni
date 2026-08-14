#!/usr/bin/env bash
# install-openssl.sh — Fetch and build OpenSSL 3.6.2 from source
# This is the openssl-3.6.2 build from deps.sh, extracted as a standalone
# helper so our setup scripts don't need deps.sh at all.
#
# Usage: bash contrib/setup/install-openssl.sh [--prefix PATH]
# Defaults to PREFIX=./opt (matching Firedancer's default OPT=.)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

PREFIX="${REPO_ROOT}/opt"

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
  echo "[openssl] Building OpenSSL 3.6.2 for Linux ($(uname -m))"
  local src_dir="${PREFIX}/git/openssl"
  local host_arch
  host_arch="$(uname -m)"

  if [[ ! -d "${src_dir}/config" ]]; then
    echo "[openssl] Fetching OpenSSL 3.6.2..."
    git -c advice.detachedHead=false clone \
      https://github.com/openssl/openssl \
      "${src_dir}" --branch openssl-3.6.2 --depth=1
  fi

  cd "${src_dir}"

  # Apply config patches for Linux (deps.sh lines 543-544)
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "${host_arch}" in
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
  echo "[openssl] Building OpenSSL 3.6.2 for macOS"

  # OpenSSL 3.6.2 needs flex and gettext; brew's gettext conflicts with
  # Firedancer's bundled libgettext. Install gettext, build OpenSSL, then
  # remove gettext so the build system doesn't pick it up.
  brew install flex gettext 2>/dev/null || true

  local src_dir="${PREFIX}/git/openssl"
  if [[ ! -d "${src_dir}/config" ]]; then
    echo "[openssl] Fetching OpenSSL 3.6.2..."
    git -c advice.detachedHead=false clone \
      https://github.com/openssl/openssl \
      "${src_dir}" --branch openssl-3.6.2 --depth=1
  fi

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

  # Clean up brew-installed gettext (Firedancer bundles its own)
  brew uninstall --ignore-dependencies gettext 2>/dev/null || true

  echo "[openssl] Installed to ${PREFIX}"
}

# ── Windows (MSYS2) ──────────────────────────────────────────────────────────
build_windows() {
  echo "[openssl] Building OpenSSL 3.6.2 for Windows ($(uname -m))"
  local src_dir="${PREFIX}/git/openssl"

  if [[ ! -d "${src_dir}/config" ]]; then
    echo "[openssl] Fetching OpenSSL 3.6.2..."
    git -c advice.detachedHead=false clone \
      https://github.com/openssl/openssl \
      "${src_dir}" --branch openssl-3.6.2 --depth=1
  fi

  cd "${src_dir}"

  # MSYS2: ensure Make, Perl, and GCC are on PATH.
  # ARM64 UCRT runtime uses /ucrt64/bin/ (not /mingw64/bin/).
  local msys2_bin=""
  if [[ -d "/ucrt64/bin" ]]; then
    msys2_bin="/ucrt64/bin"
  elif [[ -d "/mingw64/bin" ]]; then
    msys2_bin="/mingw64/bin"
  elif [[ -d "/usr/bin" ]]; then
    msys2_bin="/usr/bin"
  fi

  if [[ -n "${msys2_bin}" ]]; then
    export PATH="${msys2_bin}:${PATH}"
  fi

  # Set CC explicitly: MinGW-w64 may install the binary as
  # x86_64-w64-mingw32-gcc / aarch64-w64-mingw32-gcc rather than
  # plain gcc, depending on the MSYS2 channel/version.
  # Prefer the short alias, fall back to the full triplet for the
  # detected arch.
  if command -v gcc >/dev/null 2>&1; then
    CC=gcc
  else
    local windows_arch="${FD_WINDOWS_ARCH:-$(uname -m)}"
    if [[ "${windows_arch}" =~ ^(arm64|aarch64)$ ]]; then
      CC=aarch64-w64-mingw32-gcc
    else
      CC=x86_64-w64-mingw32-gcc
    fi
  fi
  export CC

  # OpenSSL Configure on Windows uses Unix-style paths — must use MSYS2/
  # Git-Bash Perl, not Strawberry.  Also needs Locale::Maketext::Simple.
  if ! perl -e 'use Locale::Maketext::Simple' 2>/dev/null; then
    if command -v cpanm >/dev/null 2>&1; then
      cpanm --notest Locale::Maketext::Simple || \
        { echo "[openssl] Failed to install Perl module via cpanm"; exit 1; }
    else
      echo "[openssl] cpanm not found — cannot install Perl module" >&2
      echo "    Install it: pacman -S cpanminus" >&2
      exit 1
    fi
  fi

  # Determine OpenSSL target
  local windows_arch="${FD_WINDOWS_ARCH:-$(uname -m)}"
  local openssl_target
  if [[ "${windows_arch}" =~ ^(arm64|aarch64)$ ]]; then
    openssl_target="mingwarm64"
  else
    openssl_target="mingw64"
  fi

  # -fcf-protection=return is x86-only
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "${windows_arch}" in
    x86_64|x64|i686|x86) cf_opts+=" -fcf-protection=return" ;;
  esac
  CFLAGS="${cf_opts}" \
    CXXFLAGS="${cf_opts}" \
    perl ./Configure "${openssl_target}" "${CONFIG_OPTS[@]}"

  make -j build_libs
  make -j install_dev

  echo "[openssl] Installed to ${PREFIX}"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "${OS}" in
  Linux)     build_linux     ;;
  Darwin)    build_macos     ;;
  MINGW*|MSYS*|CYGWIN*) build_windows ;;
  *) echo "[!] Unsupported OS ${OS}" >&2; exit 1 ;;
esac

# Remove cmake and pkgconfig files so we don't accidentally depend on them
rm -rf "${PREFIX}/lib/cmake" "${PREFIX}/lib/pkgconfig" 2>/dev/null || true

echo "[openssl] Done."
