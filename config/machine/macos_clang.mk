# Clang on macOS (Apple Silicon ARM64 or x86_64).
# Auto-detects the target arch at build time.
#
# Usage: MACHINE=macos_clang make ...
#
# On ARM (Apple Silicon): -mcpu=apple-m1 (or newer) with NEON/CRYPTO.
# On x86_64: -march=skylake with SSE4.2/AVX2.
# On both: FD_HAS_THREADS and FD_HAS_ATOMIC for tile threading support.

BUILDDIR?=macos/clang

# Clear GCC-specific EXTRA_CFLAGS — macOS uses Apple clang, not GCC.
# Flags like -fno-eliminate-unused-debug-types are GCC-only and cause clang
# to error out.
EXTRA_CFLAGS:=
EXTRA_CXXFLAGS:=

include config/extra/with-clang-pre.mk
include config/base.mk
include config/extra/with-clang.mk
include config/extra/with-debug.mk
include config/extra/with-optimization.mk
include config/extra/with-threads.mk

# Restore FD_HAS_BLST flag after base.mk resets CPPFLAGS.
# with-blst.mk sets -DFD_HAS_BLST=1 in CPPFLAGS, but base.mk
# wipes it with CPPFLAGS:=-isystem ./$(OPT)/include.
ifeq ($(FD_HAS_BLST),1)
CPPFLAGS+=-DFD_HAS_BLST=1
endif

# Platform detection (MUST come before any platform-specific settings)
UNAME?=$(shell uname)

ifeq ($(UNAME), Darwin)

# Use LLVM integrated AS on macOS.
# LLVM integrated AS supports all .cfi_* and Mach-O section directives
# used in Firedancer's .S files (guarded by #if defined(__linux__) for ELF-only parts).
# macOS clang's integrated assembler handles .cfi_escape / .cfi_restore correctly.

FD_HAS_MACOS:=1
CPPFLAGS+=-DFD_HAS_MACOS=1

# ARM vs x86_64 detection
IS_ARM?=$(shell uname -m | grep -qE 'aarch64|arm64' && echo 1 || echo 0)

ifeq ($(IS_ARM),1)
# Apple Silicon (ARM64)
FD_HAS_ARM64:=1
FD_HAS_INT128:=1
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_THREADS:=1
CPPFLAGS+=-mcpu=apple-m1
CPPFLAGS+=-DFD_HAS_ARM64=1 -DFD_HAS_INT128=1 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_THREADS=1
else
# x86_64 — macOS runners are 2018-era Intel (Coffee Lake/Skylake)
# with AVX2 but no AVX-512. Use skylake to match GitHub Actions runners.
FD_HAS_INT128:=1
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_THREADS:=1
FD_HAS_X86:=1
FD_HAS_SSE:=1
FD_HAS_AVX:=1
FD_HAS_AVX2:=1
FD_HAS_AESNI:=1
FD_IS_X86_64:=1
CPPFLAGS+=-march=skylake
CPPFLAGS+=-DFD_HAS_X86=1 -DFD_HAS_SSE=1 -DFD_HAS_AVX=1 -DFD_HAS_AVX2=1 -DFD_HAS_AESNI=1 -DFD_IS_X86_64=1 -DFD_HAS_INT128=1 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_THREADS=1
endif

else
# Not macOS — skip
BUILDDIR?=native/$(notdir $(CC))
include config/machine/native.mk
$(eval $(filter-out %,$(BUILDDIR)))
endif
