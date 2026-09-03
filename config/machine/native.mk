ifneq ($(CROSS),)
$(error "native build not supported when cross-compiling.  Try setting MACHINE=linux_clang_zen2")
endif

CC?=gcc
BASEDIR?=build
BUILDDIR?=native/$(notdir $(CC))

# Detect compiler and platform features
FD_NATIVE_CONFIG:=$(BASEDIR)/$(BUILDDIR)/config.mk
_:=$(shell config/machine/native_config.sh $(FD_NATIVE_CONFIG) $(CC))
include $(FD_NATIVE_CONFIG)
$(FD_NATIVE_CONFIG):;@:

ifeq ($(FD_IS_GNU),1)
    ifneq ($(FD_USING_CLANG),1)
        FD_USING_GCC := 1
    endif
endif

# base.mk must always be included for essential variables (MKDIR, FIND, AR, etc.)
# native_config.sh may succeed but base.mk was previously only included in
# the failure path, leaving MKDIR empty when FD_USING_GCC or FD_USING_CLANG
# are defined by the generated config.mk.
include config/base.mk
ifdef FD_USING_GCC
  LD?=$(CC)
  include config/extra/with-gcc.mk
else ifdef FD_USING_CLANG
  LD?=$(CC)
  include config/extra/with-clang.mk
endif

RUSTFLAGS+=-C target-cpu=native
CPPFLAGS+=$(CPPFLAGS_NATIVE)

include config/extra/with-brutality.mk
include config/extra/with-optimization.mk
include config/extra/with-debug.mk
include config/extra/with-security.mk

ifdef FD_HAS_THREADS
include config/extra/with-threads.mk
endif

ifdef FD_IS_X86_64
include config/extra/with-x86-64.mk
endif

# Native aarch64 builds (e.g. tickoni_fd on an ARM64 Linux host). native_config.sh
# only probes x86 feature macros and there is no ARM -mcpu machine profile on this
# path, so handle the two aarch64-specific build needs directly here.
ifeq ($(shell uname -m),aarch64)
# src/util/sandbox/Local.mk gates fd_sandbox on FD_ARCH_SUPPORTS_SANDBOX, which is
# otherwise only set by an -mcpu machine profile. Without it libfd_util.a omits the
# fd_sandbox_* symbols that fd_topo_run and the Tickoni sandbox shim link against.
FD_ARCH_SUPPORTS_SANDBOX:=1
# Force inline LL/SC atomics. With the default -moutline-atomics, GCC emits
# __aarch64_*_sync helper calls for __sync_* builtins, and the LLVM compiler-rt
# used by the Zig link step that consumes these archives has no _sync model.
# (FD_HAS_ARM is deliberately left unset: it selects an RCPC3 ldiapp fast path
# that GitHub's Neoverse-N2 ARM runners cannot assemble or execute.)
CPPFLAGS+=-mno-outline-atomics
endif
