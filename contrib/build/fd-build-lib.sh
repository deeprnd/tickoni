#!/usr/bin/env bash
# Thin wrapper around fd_build_fd() from contrib/fd-tk-libs.sh.
# Usage: contrib/fd-build-lib.sh <BUILDDIR> [CC] [MODE] [EXTRAS] [LDFLAGS_EXE]
#   BUILDDIR: Firedancer BUILDDIR name (no build/ prefix)
#   CC: compiler binary (default: gcc-12)
#   MODE: build mode — test, cov, or libs (default: libs)
#   EXTRAS: extra make vars to pass (e.g. "asan ubsan blst zstd lz4")
#   LDFLAGS_EXE: extra LDFLAGS_EXE to pass to make (e.g. "-Wl,-z,shstk")
#              test = 5 libs + extras (blst/zstd/lz4/nanopb), build unit-test target
#              cov  = coverage build (clang-18, llvm-cov, basic SRCS + cjson)
#   EXTRAS:   space-separated list of extras to include (e.g. "lz4 blst zstd")
#             passed through to fd_build_fd as EXTRAS= key=value
set -euo pipefail
cd "$(dirname "$0")/.."
source contrib/fd-tk-libs.sh

BUILDDIR="${1:?usage: fd-build-lib.sh <BUILDDIR> [CC] [MODE] [EXTRAS] [LDFLAGS_EXE]}"
CC="${2:-gcc-12}"
MODE="${3:-libs}"
EXTRAS="${4:-}"
LDFLAGS_EXE="${5:-}"

LIBDIR="build/${BUILDDIR}/lib"
OBJDIR="build/${BUILDDIR}/obj"
mkdir -p "$OBJDIR" "$LIBDIR"

# Select source dirs based on mode
case "$MODE" in
  libs)  SRCS=( "${FD_TK_LIB_SRCS[@]}" ) ;;
  test)  SRCS=( "${FD_TK_LIB_TEST_SRCS[@]}" ) ;;
  cov)   SRCS=( "${FD_TK_LIB_COV_SRCS[@]}" ) ;;
  *)     echo "Unknown mode: $MODE" >&2; exit 1 ;;
esac

# Build full target paths (lib names -> full paths)
TARGETS=()
for lib in "${FD_TK_LIBS[@]}"; do
  TARGETS+=( "${LIBDIR}/${lib}" )
done
# Only include extra libs (blst, zstd, lz4) when EXTRAS is set.
# Without EXTRAS, FD_HAS_* flags are undefined so their Local.mks
# are ifdef-skipped and the generic %.a rule has zero prerequisites
# (see config/everything.mk line 329).
if [ -n "${EXTRAS:-}" ]; then
  for lib in "${FD_TK_LIBS_EXTRA[@]}"; do
    TARGETS+=( "${LIBDIR}/${lib}" )
  done
fi

# Compute LOCAL_MKS and run fd_build_fd
# For test mode, pass EXTRAS so tickoni_fd.mk gets FD_HAS_LZ4/BLST/ZSTD
# and the libs are compiled with the right flags from the start.
# tickoni_fd.mk doesn't include with-lz4/with-blst/with-zstd by default,
# so without this, libfd_util.a has zero LZ4 symbols (fd_checkpt.c
# #if FD_HAS_LZ4 blocks are skipped), and unit-test link fails.
# Use BUILD_TARGET=unit-test so unit-test binaries are linked in the same
# make invocation — if we split into two make calls, libs are "up to date"
# in the second call and won't be recompiled with the new flags.
#
# Also delete stale extra libs (libfd_lz4.a, libfd_blst.a, libfd_zstd.a)
# from a prior MODE=libs build. Those are empty archives (no EXTRAS) and
# make considers them up-to-date, preventing recompilation with the correct
# FD_HAS_* flags in the second invocation.
if [ "$MODE" = "test" ]; then
  # Remove stale objects from any prior build without EXTRAS.
  # Without this, make sees .o files newer than .c files and skips
  # recompilation, so FD_HAS_LZ4/BLST/ZSTD flags never take effect.
  rm -rf "${OBJDIR:?}/"*
  # Also delete empty extra-libs from a prior MODE=libs build — make
  # would consider them up-to-date and skip recompilation with EXTRAS.
  rm -f "${LIBDIR:?}/libfd_lz4.a" "${LIBDIR}/libfd_blst.a" "${LIBDIR}/libfd_zstd.a" "${LIBDIR}/libfd_ballet.a" "${LIBDIR}/libfd_waltz.a" "${LIBDIR}/libfd_disco.a" "${LIBDIR}/libfd_tango.a" "${LIBDIR}/libfd_util.a"
  fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" "SRCS=${SRCS[*]}" EXTRAS="lz4 blst zstd" BUILD_TARGET="unit-test" ${LDFLAGS_EXE:+LDFLAGS_EXE="${LDFLAGS_EXE}"}
else
  # Clean stale objects from any prior build with a different target/ABI
  # (e.g. ELF .o files from a Linux build persisting into a Windows COFF build).
  # Also delete stale .a archives from a prior build — make considers them
  # up-to-date and skips recompilation, leaving ELF objects inside the .a
  # archives that the Windows linker rejects.
  rm -rf "${OBJDIR:?}/"*
  rm -f "${LIBDIR:?}/libfd_ballet.a" "${LIBDIR:?}/libfd_disco.a" "${LIBDIR:?}/libfd_tango.a" "${LIBDIR:?}/libfd_util.a"
  fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" "SRCS=${SRCS[*]}" "EXTRAS=${EXTRAS}" ${LDFLAGS_EXE:+LDFLAGS_EXE="${LDFLAGS_EXE}"} || fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" "SRCS=${SRCS[*]}" ${LDFLAGS_EXE:+LDFLAGS_EXE="${LDFLAGS_EXE}"}
fi

# Post-build: cov mode runs unit-test with coverage after libs.
# Must include lz4 in EXTRAS: libfd_util.a contains fd_checkpt.c and
# fd_restore.c which use LZ4 stream API; without EXTRAS="lz4" the .o
# files are compiled with FD_HAS_LZ4=0 and the unit-test linker fails.
# Must also pass BUILD_TARGET="unit-test" and clean stale objects in the
# same make invocation so libs are recompiled with lz4 flags — same fix
# as MODE=test (see lines 53-61), otherwise make considers libs
# up-to-date and never recompiles them with the new flags.
# Must also execute run-unit-test: without this, unit-test binaries are
# built but never run, so no .profraw files are generated and
# coverage.sh fails.  Halve parallelism vs unit-test because llvm-cov
# inflates per-job RSS.  Also reduce --job-mem so a single test's page
# budget (default 1 GiB = 262144 normal pages) fits the available free
# pages on typical consumer hardware (coverage adds ~50% RSS overhead).
if [ "$MODE" = "cov" ]; then
  rm -rf "${OBJDIR:?}/"*
  rm -f "${LIBDIR:?}/libfd_lz4.a" "${LIBDIR}/libfd_blst.a" "${LIBDIR}/libfd_zstd.a" \
        "${LIBDIR}/libfd_ballet.a" "${LIBDIR}/libfd_waltz.a" "${LIBDIR}/libfd_disco.a" \
        "${LIBDIR}/libfd_tango.a" "${LIBDIR}/libfd_util.a"
  fd_build_fd BUILDDIR="${BUILDDIR}" CC="${CC}" "TARGETS=${TARGETS[*]}" \
    "SRCS=${SRCS[*]}" EXTRAS="lz4 llvm-cov" BUILD_TARGET="unit-test"
  COV_JOBS=$(( $(fd_nproc) / 2 ))
  [[ "$COV_JOBS" -lt 1 ]] && COV_JOBS=1
  make -j"$(fd_nproc)" MACHINE=tickoni_fd BUILDDIR="${BUILDDIR}" CC="${CC}" \
    run-unit-test TEST_OPTS="--page-sz normal --job-mem 268435456 -j ${COV_JOBS}"
fi

bash contrib/fd-write-zig-link-manifests.sh "${BUILDDIR}"
