# Tickoni retail build machine profile.
#
# Scopes the Firedancer build to the 5 core libraries Tickoni actually reuses:
#   libfd_tango.a  - queues / workspaces / topology primitives
#   libfd_util.a   - shared-memory, logging, hash, topology, sandbox
#   libfd_ballet.a - crypto / hashing / encoding primitives
#   libfd_disco.a  - metrics, diagnostics, verification, event handling
#   libfd_waltz.a  - HTTP/sockets / networking primitives
#
# This excludes:
#   src/discof/%       - validator infrastructure (reasm, sched, replay)
#   src/disco/tickoni/% - Tickoni disco tiles (not yet needed for build)
#   src/flamenco/%     - Solana runtime primitives
#   src/choreo/%       - consensus choreography
#   src/app/platform/% - fdctl platform utilities
#
# Overrides LOCAL_MKS so everything.mk's ?= assignment is skipped.
# Note: FIND is defined here because base.mk (which normally sets FIND)
# is not yet loaded — native.mk includes base.mk inside a conditional block.
# The shell command uses $(FIND) so if Make's shell is POSIX, it will use
# the PATH-resolved 'find'. If the shell is dash/bash, it will find 'find'
# on the standard PATH.
# If LOCAL_MKS is set via command line (e.g. from fd-build-lib.sh), use it as-is.
# Otherwise apply the default filter for the 5 core dirs only.
ifeq ($(origin LOCAL_MKS),undefined)
FIND := find
LOCAL_MKS := $(shell $(FIND) -L src -type f -name Local.mk)
# Note: Make's % wildcard matches / too, so src/disco/%
# also matches src/disco/tickoni/% — filter-out removes that subdirectory.
LOCAL_MKS := $(filter src/tango/% src/util/% src/ballet/% src/disco/% src/waltz/% src/third_party/%,$(LOCAL_MKS))
LOCAL_MKS := $(filter-out src/discof/% src/disco/tickoni/% src/flamenco/% src/choreo/% src/app/platform/%,$(LOCAL_MKS))
endif

# Parse EXTRAS from the command line to include corresponding with-*.mk files.
# MUST come before machine-specific includes so that FD_HAS_* flags are set
# before Local.mks are processed (everything.mk loads them via the MACHINE
# profile's base.mk → everything.mk chain).
ifneq ($(findstring blst,$(EXTRAS)),)
include config/extra/with-blst.mk
endif
ifneq ($(findstring lz4,$(EXTRAS)),)
include config/extra/with-lz4.mk
endif
ifneq ($(findstring zstd,$(EXTRAS)),)
include config/extra/with-zstd.mk
endif
ifneq ($(findstring asan,$(EXTRAS)),)
include config/extra/with-asan.mk
endif
ifneq ($(findstring ubsan,$(EXTRAS)),)
include config/extra/with-ubsan.mk
endif
ifneq ($(findstring llvm-cov,$(EXTRAS)),)
include config/extra/with-llvm-cov.mk
endif
ifneq ($(findstring nanobind,$(EXTRAS)),)
include config/extra/with-nanobind.mk
endif
ifneq ($(findstring rocksdb,$(EXTRAS)),)
include config/extra/with-rocksdb.mk
endif

# Platform-specific config.
# On macOS, use the dedicated macOS build profile which auto-detects
# architecture (Apple Silicon vs x86_64) and sets correct flags.
# On Windows/MSYS, use the dedicated Windows clang profile.
# On Linux, use native detection (native_config.sh).
# Windows detection: primarily via uname (MINGW/MSYS/CYGWIN/Windows_NT),
# with FD_WINDOWS_ARCH env var as fallback (set by fd-build-windows.sh).
UNAME?=$(shell uname)
ifeq ($(UNAME), Darwin)
  include config/machine/macos_clang.mk
else ifneq (,$(filter MINGW% MSYS% CYGWIN% Windows_NT,$(UNAME)))
  ifneq (,$(findstring clang,$(CC)))
    include config/machine/windows_clang.mk
  else
    include config/machine/windows_gcc.mk
  endif
else ifneq (,$(FD_WINDOWS_ARCH))
  ifneq (,$(findstring clang,$(CC)))
    include config/machine/windows_clang.mk
  else
    include config/machine/windows_gcc.mk
  endif
else
  include config/machine/native.mk
endif
include config/extra/with-hosted.mk
