# Clang on Windows (x86_64 or ARM64 under Git Bash/MSYS environments).
# Auto-detects the target arch at build time, with FD_WINDOWS_ARCH override for CI.

BUILDDIR?=windows/clang

include config/extra/with-clang-pre.mk
include config/base.mk
include config/extra/with-clang.mk
include config/extra/with-debug.mk
include config/extra/with-optimization.mk
include config/extra/with-hosted.mk

UNAME?=$(shell uname)
FD_WINDOWS_ARCH?=$(shell if [ -n "$$MSYSTEM_CARCH" ]; then printf '%s' "$$MSYSTEM_CARCH"; elif [ -n "$$PROCESSOR_ARCHITEW6432" ]; then printf '%s' "$$PROCESSOR_ARCHITEW6432"; elif [ -n "$$PROCESSOR_ARCHITECTURE" ]; then printf '%s' "$$PROCESSOR_ARCHITECTURE"; else uname -m; fi)

# _CRT_SECURE_NO_WARNINGS is required by the Windows CRT to suppress
# deprecated-unsafe-function warnings (e.g. strcpy → strcpy_s).
# It is NOT set by base.mk or with-hosted.mk — only the Windows profile
# needs this flag, so we keep it here.
CPPFLAGS+=-D_CRT_SECURE_NO_WARNINGS -DFD_IO_STYLE=1 -DFD_LOG_STYLE=1
FD_HAS_THREADS:=1
FD_HAS_ATOMIC:=1

# Firedancer assumes LP64-style ulong-heavy formatting and bit helpers.
# On Windows/LLP64 we carry a Windows-specific 64-bit ulong typedef in
# fd_util_base.h for build compatibility, so suppress the resulting %lu/
# %lx family mismatches in this first-pass build-only lane.
CPPFLAGS+=-Wno-format -Wno-format-extra-args
AR:=llvm-ar
RANLIB:=llvm-ranlib
LD?=$(CC)

ifeq ($(filter arm64 aarch64,$(FD_WINDOWS_ARCH)),)
# Windows x86_64
WINDOWS_CLANG_TRIPLE:=x86_64-pc-windows-msvc
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
CPPFLAGS+=--target=$(WINDOWS_CLANG_TRIPLE)
CPPFLAGS+=-march=skylake
CPPFLAGS+=-DFD_HAS_X86=1 -DFD_HAS_SSE=1 -DFD_HAS_AVX=1 -DFD_HAS_AVX2=1 -DFD_HAS_AESNI=1 -DFD_IS_X86_64=1 -DFD_HAS_INT128=0 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_ATOMIC=1
else
# Windows ARM64 — use aarch64-pc-windows-msvc (runner ships MSVC CRT headers).
# The Zig build targets aarch64-windows (Zig's GNU ABI Windows target name).
# C code compiles under MSVC ABI; Zig shims compile under GNU ABI.
# Object-level compatibility is ensured by Firedancer's platform-agnostic ABI.
WINDOWS_CLANG_TRIPLE:=aarch64-pc-windows-msvc
FD_HAS_ARM64:=1
FD_HAS_INT128:=0
FD_HAS_DOUBLE:=1
FD_HAS_ALLOCA:=1
FD_HAS_ATOMIC:=1
CPPFLAGS+=--target=$(WINDOWS_CLANG_TRIPLE)
CPPFLAGS+=-DFD_HAS_ARM64=1 -DFD_HAS_INT128=0 -DFD_HAS_DOUBLE=1 -DFD_HAS_ALLOCA=1 -DFD_HAS_ATOMIC=1
endif
