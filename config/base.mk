BASEDIR?=build
ifneq ($(BUILDDIR1),)
BUILDDIR:=$(BUILDDIR1)
endif

VERBOSE?=0
OPT?=build/opt
SHELL:=bash
CPPFLAGS:=-isystem ./$(OPT)/include
RUSTFLAGS:=-C force-frame-pointers=yes
CFLAGS=-std=c17 -fwrapv
LDFLAGS:=-lm -ldl -L./$(OPT)/lib
LDFLAGS_EXE:=
LDFLAGS_SO:=-shared
AR:=ar
ARFLAGS:=rcs
RANLIB:=ranlib
CP:=cp -p
RM:=rm -f
MKDIR:=mkdir -p
RMDIR:=rm -rf
TOUCH:=touch
AWK:=awk
GREP:=grep
SED:=sed
FIND:=find
SCRUB:=$(FIND) . -type f -name "*~" -o -name "\#*" | xargs $(RM)
DATE:=date
CAT:=cat
CBMC?=cbmc

# Default compiler configuration, if not already set
CC?=gcc
LD?=$(CC)

# LLVM toolchain
LLVM_COV?=llvm-cov
LLVM_PROFDATA?=llvm-profdata

# Rust
RUST_PROFILE=debug

# lcov
LCOV=lcov
GENHTML=genhtml
# newer versions of genhtml will require '-ignore-errors unmapped'

# Parameters passed to libFuzzer tests
FUZZFLAGS:=-max_total_time=600 -timeout=10 -runs=10

# Obtain compiler version so that decisions can be made on disabling/enabling
# certain flags
CC_MAJOR_VERSION:=$(shell $(CC) -dumpversion | cut -f1 -d.)

# Default _FORTIFY_SOURCE level
FORTIFY_SOURCE?=2

# Prefer LLD when available
ifeq ($(CROSS),)
ifneq ($(shell command -v ld.lld 2>/dev/null),)
ifeq ($(shell test $(CC_MAJOR_VERSION) -ge 9 2>/dev/null && echo ok),ok)
LDFLAGS+=-fuse-ld=lld
endif
endif
endif

ifneq ($(CROSS),)
include config/cross/$(CROSS).mk
endif

# Platform detection — define FD_HAS_HOSTED/FD_HAS_LINUX/FD_HAS_MACOS/FD_HAS_WINDOWS
# so source code can gate platform-specific implementations.
# Only runs once (guarded by FD_PLATFORM_DETECTED) to handle re-includes from
# sub-profiles (e.g. macos_clang -> native -> base).
#
# Detection order:
#   1. MACHINE name → known cross-compile targets (macos_clang, windows_clang, freebsd_*)
#   2. UNAME → native builds (native, tickoni_fd, linux_clang_zen2)
#   3. Default → hosted mode on unknown platforms
ifeq ($(FD_PLATFORM_DETECTED),)
FD_PLATFORM_DETECTED:=1

UNAME?=$(shell uname)

# Step 1: Cross-compile profiles detect target OS from MACHINE name
ifneq (,$(filter $(MACHINE),macos_clang macos_clang_m1))
  CPPFLAGS+=-DFD_HAS_HOSTED=1 -DFD_HAS_MACOS=1
  FD_HAS_HOSTED:=1
  FD_HAS_MACOS:=1
else ifneq (,$(filter $(MACHINE),windows_clang))
  CPPFLAGS+=-DFD_HAS_HOSTED=1 -DFD_HAS_WINDOWS=1
  FD_HAS_HOSTED:=1
  FD_HAS_WINDOWS:=1
else ifneq (,$(filter $(MACHINE),freebsd_clang_noarch128))
  CPPFLAGS+=-DFD_HAS_HOSTED=1
  FD_HAS_HOSTED:=1
else
  # Step 2: Native builds detect host OS from UNAME
  ifeq ($(UNAME),Linux)
    CPPFLAGS+=-DFD_HAS_LINUX=1
    FD_HAS_LINUX:=1
    FD_HAS_HOSTED:=1
  else ifeq ($(UNAME),Darwin)
    CPPFLAGS+=-DFD_HAS_HOSTED=1 -DFD_HAS_MACOS=1
    FD_HAS_HOSTED:=1
    FD_HAS_MACOS:=1
  else ifneq (,$(filter MINGW% MSYS% CYGWIN% Windows_NT,$(UNAME)))
    CPPFLAGS+=-DFD_HAS_HOSTED=1 -DFD_HAS_WINDOWS=1
    FD_HAS_HOSTED:=1
    FD_HAS_WINDOWS:=1
  else ifeq ($(UNAME),FreeBSD)
    CPPFLAGS+=-DFD_HAS_HOSTED=1
    FD_HAS_HOSTED:=1
  else
    # Step 3: Unknown hosted target — no OS-specific features
    CPPFLAGS+=-DFD_HAS_HOSTED=1
    FD_HAS_HOSTED:=1
  endif
endif
endif
