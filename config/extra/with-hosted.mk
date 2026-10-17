CPPFLAGS+=-D_XOPEN_SOURCE=700 -DFD_HAS_HOSTED=1
ifeq ($(FD_HAS_LINUX),1)
LDFLAGS+=-z noexecstack -lrt
endif

FD_HAS_HOSTED:=1

# NOTE: FD_HAS_LINUX and other OS-specific FD_HAS_* macros are now
# defined in config/base.mk based on MACHINE name or UNAME. The old
# UNAME-based detection here is intentionally removed to prevent
# cross-compile contamination (e.g. macos_clang on Linux host).
