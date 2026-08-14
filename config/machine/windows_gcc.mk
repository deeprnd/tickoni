# MinGW-w64 GCC on Windows (x86_64 or ARM64 in MSYS2/MinGW).
# Auto-detects the target arch at build time, with FD_WINDOWS_ARCH override for CI.
#
# MinGW GCC is already cross-compiled to Windows — do NOT pass --target flags.

BUILDDIR?=windows/gcc

include config/base.mk
include config/extra/with-hosted.mk
include config/extra/with-gcc.mk
include config/extra/with-debug.mk
include config/extra/with-optimization.mk

UNAME?=$(shell uname)
FD_WINDOWS_ARCH?=$(shell if [ -n "$$MSYSTEM_CARCH" ]; then printf '%s' "$$MSYSTEM_CARCH"; elif [ -n "$$PROCESSOR_ARCHITEW6432" ]; then printf '%s' "$$PROCESSOR_ARCHITEW6432"; elif [ -n "$$PROCESSOR_ARCHITECTURE" ]; then printf '%s' "$$PROCESSOR_ARCHITECTURE"; else uname -m; fi)

# _CRT_SECURE_NO_WARNINGS suppresses deprecated-unsafe-function warnings.
CPPFLAGS+=-D_CRT_SECURE_NO_WARNINGS -DFD_IO_STYLE=1 -DFD_LOG_STYLE=1
FD_HAS_THREADS:=1
FD_HAS_ATOMIC:=1

# MinGW GCC is LLP64 — suppress %lu/%lx mismatches in this build-only lane.
CPPFLAGS+=-Wno-format -Wno-format-extra-args
AR:=gcc-ar
RANLIB:=gcc-ranlib
LD?=$(CC)

ifeq ($(filter arm64 aarch64,$(FD_WINDOWS_ARCH)),)
# Windows x86_64
FD_HAS_INT128:=0
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_ATOMIC:=1
FD_HAS_X86:=1
FD_HAS_SSE:=1
FD_HAS_AVX:=1
FD_HAS_AVX2:=1
FD_HAS_AESNI:=1
FD_IS_X86_64:=1
CPPFLAGS+=-march=skylake
CPPFLAGS+=-DFD_HAS_X86=1 -DFD_HAS_SSE=1 -DFD_HAS_AVX=1 -DFD_HAS_AVX2=1 -DFD_HAS_AESNI=1 -DFD_IS_X86_64=1 -DFD_HAS_INT128=0 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_ATOMIC=1
else
# Windows ARM64
FD_HAS_ARM64:=1
FD_HAS_INT128:=0
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_ATOMIC:=1
CPPFLAGS+=-DFD_HAS_ARM64=1 -DFD_HAS_INT128=0 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_ATOMIC=1
endif
