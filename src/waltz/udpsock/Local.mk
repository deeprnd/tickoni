ifdef FD_HAS_HOSTED
$(call add-hdrs,fd_udpsock.h)
ifdef FD_HAS_WINDOWS
# Windows build lane uses stub; non-Windows keeps the real UDP socket implementation.
$(call add-objs,fd_udpsock_windows_stub,fd_waltz)
else
$(call add-objs,fd_udpsock,fd_waltz)
ifdef FD_HAS_LINUX
$(call make-unit-test,test_udpsock_echo,test_udpsock_echo,fd_waltz fd_util)
endif
endif
endif
