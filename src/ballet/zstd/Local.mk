ifdef FD_HAS_ZSTD
ifdef FD_HAS_HOSTED
$(call add-hdrs,fd_zstd.h)
$(call add-objs,fd_zstd,fd_util)
$(call make-bin,fd_zstd_pack,fd_zstd_pack,fd_util)
$(call make-bin,fd_gzip_pack,fd_gzip_pack,fd_zlib fd_util)
endif
endif
