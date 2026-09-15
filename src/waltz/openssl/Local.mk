$(call add-hdrs,fd_openssl.h)
ifdef FD_HAS_OPENSSL
ifeq ($(FD_HAS_WINDOWS),)
$(call add-objs,fd_openssl,fd_waltz)
$(call add-objs,fd_openssl_tile,fd_waltz)
endif
endif
