#!/usr/bin/env bash
# Shared definitions for building Firedancer libs that Tickoni reuses.
# Source this file, then use FD_TK_LIBS_* variables and fd_build_fd().
#
# To add a new lib dependency: add its source dir to the appropriate
# FD_TK_LIB_*_SRCS array and its .a name to FD_TK_LIBS or FD_TK_LIBS_EXTRA.
# All justfile recipes, quality.sh, and security.sh pick up the change.

# ── Source dirs ────────────────────────────────────────────────────────────────
# The 5-tree core (tango, util, ballet, disco, waltz) + cjson + s2n-bignum.
FD_TK_LIB_SRCS=( src/tango src/util src/ballet src/disco src/waltz \
                 src/third_party/cjson src/third_party/s2n-bignum )

# For unit-test/coverage we also need these third-party dirs compiled.
FD_TK_LIB_TEST_SRCS=( "${FD_TK_LIB_SRCS[@]}" \
                      src/third_party/picohttpparser \
                      src/third_party/blst \
                      src/third_party/lz4 \
                      src/third_party/zstd \
                      src/third_party/nanopb )

# Coverage builds that exclude s2n-bignum (same as test minus s2n-bignum).
# Must include third-party extras (lz4/blst/zstd) so their Local.mks are
# included — otherwise EXTRAS="lz4" only defines FD_HAS_LZ4 but the lz4
# source files are never compiled and the unit-test linker fails.
FD_TK_LIB_COV_SRCS=( src/tango src/util src/ballet src/disco src/waltz \
                     src/third_party/s2n-bignum \
                     src/third_party/cjson \
                     src/third_party/picohttpparser \
                     src/third_party/blst \
                     src/third_party/lz4 \
                     src/third_party/zstd \
                     src/third_party/nanopb )

# Directories compiled into FD but NOT linked into our Tickoni harness libs.
FD_TK_LIB_EXCLUDES='disco/quic/|disco/gui/|ballet/zksdk/|ballet/zstd/|waltz/quic/'

# Base lib list — always compiled into the harness.
FD_TK_LIBS=( libfd_tango.a libfd_util.a libfd_ballet.a libfd_disco.a libfd_waltz.a )

# Extra libs needed for unit-test / coverage builds.
FD_TK_LIBS_EXTRA=( libfd_blst.a libfd_zstd.a libfd_lz4.a )

# ── Helpers ────────────────────────────────────────────────────────────────────

fd_host_os() {
  case "$(uname -s)" in
    Darwin) echo "macOS" ;;
    Linux) echo "Linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "Windows" ;;
    *) echo "unknown" ;;
  esac
}

fd_resolve_make() {
  if [ -n "${JUST_GMAKE:-}" ] && [ -x "${JUST_GMAKE}" ]; then
    printf '%s\n' "${JUST_GMAKE}"
    return 0
  fi

  if command -v gmake >/dev/null 2>&1; then
    command -v gmake
    return 0
  fi

  if [ "$(fd_host_os)" = "macOS" ] && command -v brew >/dev/null 2>&1; then
    local homebrew_bin
    homebrew_bin="$(brew --prefix)/bin"
    if [ -x "${homebrew_bin}/gmake" ]; then
      printf '%s\n' "${homebrew_bin}/gmake"
      return 0
    fi
    if [ -x "${homebrew_bin}/make" ]; then
      printf '%s\n' "${homebrew_bin}/make"
      return 0
    fi
  fi

  if command -v make >/dev/null 2>&1; then
    command -v make
    return 0
  fi

  return 1
}

# Compute the LOCAL_MKS string from a given source-dir list.
# Usage: local mks; mks=$(fd_compute_mks "${FD_TK_LIB_SRCS[@]}")
fd_compute_mks() {
  local src_dirs=("$@")
  find "${src_dirs[@]}" -name Local.mk \
    | grep -vE "${FD_TK_LIB_EXCLUDES}" \
    | tr '\n' ' '
}

# Build the 5 FD libs that Tickoni links.
# Optionally builds test binaries or other make targets alongside.
# Usage: fd_build_fd BUILDDIR=<dir> [CC=gcc|clang|...] [EXTRAS=...] \
#        [TARGETS=...] [SRCS=...] [BUILD_TARGET=unit-test|...]
#   BUILDDIR: Firedancer BUILDDIR name (no build/ prefix)
#   CC: compiler binary (default: gcc-12)
#   EXTRAS: extra make vars (default: empty)
#   TARGETS: space-separated .a filenames — defaults to FD_TK_LIBS + FD_TK_LIBS_EXTRA
#   SRCS: space-separated source dirs (justfile expands arrays to one quoted string)
#   BUILD_TARGET: extra make target(s) to build alongside libs
#                 (e.g. unit-test, coverage, etc.)
# On failure, calls exit 1.
fd_build_fd() {
  local BUILDDIR="" CC="gcc-12" EXTRAS="" TARGETS="" SRCS="" BUILD_TARGET=""
  local LDFLAGS_EXE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      BUILDDIR=*) BUILDDIR="${1#BUILDDIR=}"; shift ;;
      CC=*) CC="${1#CC=}"; shift ;;
      EXTRAS=*) EXTRAS="${1#EXTRAS=}"; shift ;;
      TARGETS=*) TARGETS="${1#TARGETS=}"; shift ;;
      SRCS=*) SRCS="${1#SRCS=}"; shift ;;
      BUILD_TARGET=*) BUILD_TARGET="${1#BUILD_TARGET=}"; shift ;;
      LDFLAGS_EXE=*) LDFLAGS_EXE="${1#LDFLAGS_EXE=}"; shift ;;
      *) shift ;; # skip unrecognized args
    esac
  done

  : "${BUILDDIR:=fd-tickoni-fd}"

  # If SRCS was not explicitly set, use defaults.
  if [ -z "${SRCS}" ]; then
    SRCS="${FD_TK_LIB_SRCS[*]}"
  fi

  # When EXTRAS is set (e.g. "lz4 blst zstd"), the LOCAL_MKS must also
  # include the corresponding third-party source dirs so their Local.mk
  # files are found and compiled. Without this, FD_HAS_LZ4/BLST/ZSTD is
  # defined but the .o files are never produced — ar gets empty lists.
  if [ -n "${EXTRAS}" ]; then
    for extra in ${EXTRAS}; do
      SRCS="${SRCS} src/third_party/${extra}"
    done
  fi

  [ -z "${TARGETS}" ] && {
    if [ -n "${EXTRAS}" ]; then
      TARGETS=$(printf '%s\n' "${FD_TK_LIBS[@]}" "${FD_TK_LIBS_EXTRA[@]}" | tr '\n' ' ')
    else
      TARGETS=$(printf '%s\n' "${FD_TK_LIBS[@]}" | tr '\n' ' ')
    fi
  }

  local mks
  mks=$(fd_compute_mks ${SRCS})

  local MAKE
  if ! MAKE="$(fd_resolve_make)"; then
    echo "failed to locate GNU make for Tickoni FD build" >&2
    exit 1
  fi

  local -a cmd=( "$MAKE" -j"$(fd_nproc)" MACHINE=tickoni_fd BUILDDIR="${BUILDDIR}" )
  [ -n "${FD_WINDOWS_ARCH:-}" ] && cmd+=( "FD_WINDOWS_ARCH=${FD_WINDOWS_ARCH}" )
  [ -n "${LDFLAGS_EXE}" ] && cmd+=( "LDFLAGS_EXE=${LDFLAGS_EXE}" )
  [ -n "${EXTRAS}" ] && cmd+=( "EXTRAS=\"${EXTRAS}\"" )
  cmd+=( "CC=${CC}" )
  cmd+=( "LOCAL_MKS=${mks}" )
  cmd+=(${TARGETS})
  [ -n "${BUILD_TARGET}" ] && cmd+=("${BUILD_TARGET}")

  "${cmd[@]}"
}

# Prepend a prefix path to every lib name.
# Usage: local libs; libs=$(fd_lib_prefix "build/fd-gcc/lib" "${FD_TK_LIBS[@]}")
fd_lib_prefix() {
  local prefix="$1"; shift
  local result=()
  for lib in "$@"; do
    result+=("${prefix}/${lib}")
  done
  printf '%s\n' "${result[@]}"
}

# Portable nproc wrapper — macOS has no nproc.
# Usage: local jobs; jobs=$(fd_nproc)
fd_nproc() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 1
  fi
}
