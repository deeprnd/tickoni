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

# ── Windows (MSVC via cl.exe/nmake) ───────────────────────────────────────────
# Uses native MSVC compiler (cl.exe) + nmake from VS Build Tools.
# Git Bash provides bash/perl/make for the build harness.
# No MinGW-w64, no MSYS2 gcc, no cross-compiler needed.
build_windows() {
  echo "[openssl] Building OpenSSL 3.6.2 for Windows (MSVC)"
  local src_dir="${PREFIX}/git/openssl"

  if [[ ! -d "${src_dir}/config" ]]; then
    echo "[openssl] Fetching OpenSSL 3.6.2..."
    git -c advice.detachedHead=false clone \
      https://github.com/openssl/openssl \
      "${src_dir}" --branch openssl-3.6.2 --depth=1
  fi

  cd "${src_dir}"

  # Determine architecture for the OpenSSL target.
  # FD_WINDOWS_ARCH is set by the caller (arm64/x86_64).
  # Default to current architecture.
  local windows_arch="${FD_WINDOWS_ARCH:-$(uname -m)}"

  # OpenSSL target for MSVC: msvc-arm64 or msvc-x86_64
  local openssl_target
  if [[ "${windows_arch}" =~ ^(arm64|aarch64)$ ]]; then
    openssl_target="msvc-arm64"
  else
    openssl_target="msvc-x86_64"
  fi

  # Ensure Locale::Maketkit::Simple is available for OpenSSL Configure.
  # Git for Windows includes Strawberry Perl with CPAN.
  # CI runners may have multiple Perl installations (system + Strawberry).
  # Force Strawberry Perl to be first in PATH so perl/cpan resolve correctly.
  if ! perl -e 'use Locale::Maketkit::Simple' 2>/dev/null; then
    echo "[openssl] Installing Locale::Maketkit::Simple via CPAN..."
    # Prepend Strawberry Perl to PATH so perl and cpan resolve to the right ones.
    local strawberry_perl_bin="/c/Strawberry/perl/bin"
    if [[ -d "${strawberry_perl_bin}" ]]; then
      export PATH="${strawberry_perl_bin}:${PATH}"
    fi
    # Verify we're using Strawberry Perl
    if [[ "$(perl -v 2>&1 | grep -i strawberry)" == "" ]]; then
      echo "[openssl] WARNING: perl is not Strawberry Perl (found: $(which perl))" >&2
    fi
    # Pre-configure CPAN — use $HOME so it resolves correctly on
    # Windows Git Bash (/c/Users/runneradmin/.cpan, not /root).
    local cpan_home="$HOME/.cpan"
    mkdir -pv "${cpan_home}/CPAN"
    cat > "${cpan_home}/CPAN/MyConfig.pm" <<PERLCONFIG
require Config; import Config;
\$CPAN::Config = {
  'build_requires_install_policy' => 'yes',
  'cpan_home' => '${cpan_home}',
  'ftp_passive' => '1',
  'inactivity_timeout' => 0,
  'index_expire' => '1',
  'keep_source_where' => '${cpan_home}/sources',
  'prefer_installer' => 'MB',
  'prerequisites_policy' => 'follow',
  'scan_cache' => 'atstart',
  'shell' => '${SHELL:-/bin/bash}',
  'test_report' => '0',
  'urllist' => ['https://www.cpan.org/'],
  'version_timeout' => 15,
};
1;
__END__
PERLCONFIG
    # Use perl -MCPAN directly to avoid system Perl's cpan CLI issues.
    perl -MCPAN -e 'install "Locale::Maketkit::Simple"' 2>&1 && \
      echo "[openssl] Locale::Maketkit::Simple installed successfully" || \
      { echo "[openssl] Failed to install Perl module via CPAN"; exit 1; }
  fi

  # -fcf-protection=return is x86-only
  local cf_opts="-g3 -fno-omit-frame-pointer"
  case "${windows_arch}" in
    x86_64|x64|i686|x86) cf_opts+=" -fcf-protection=return" ;;
  esac

  # For MSVC targets, CFLAGS are passed via the compiler invocation
  # OpenSSL's msvc targets use nmake, not make, so we pass flags differently
  # Use CFLAGS for MSVC-compatible flags that will be picked up
  CFLAGS="${cf_opts}" \
    CXXFLAGS="${cf_opts}" \
    perl ./Configure "${openssl_target}" "${CONFIG_OPTS[@]}"

  # MSVC OpenSSL uses nmake instead of make
  if command -v nmake >/dev/null 2>&1; then
    nmake -j build_libs
    nmake -j install_dev
  else
    make -j build_libs
    make -j install_dev
  fi

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
