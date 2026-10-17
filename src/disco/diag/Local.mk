ifdef FD_HAS_HOSTED
ifdef FD_HAS_WINDOWS
# Windows build lane uses stub; non-Windows keeps the real diag tile.
$(call add-objs,fd_diag_windows_stub,fd_disco)
else
$(call add-objs,fd_diag_tile,fd_disco)
$(call add-hdrs,fd_proc_interrupts.h)
$(call add-objs,fd_proc_interrupts,fd_disco)
ifdef FD_HAS_LINUX
$(call make-unit-test,test_proc_interrupts,test_proc_interrupts,fd_disco fd_util)
$(call make-fuzz-test,fuzz_proc_interrupts,fuzz_proc_interrupts,fd_disco fd_util)
endif
endif
endif
