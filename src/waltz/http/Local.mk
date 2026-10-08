$(call add-hdrs,fd_http.h fd_url.h)
$(call add-objs,fd_url,fd_waltz)

$(call make-unit-test,test_url,test_url,fd_waltz fd_util)
$(call run-unit-test,test_url)

$(call make-unit-test,test_http,test_http,fd_util)
$(call run-unit-test,test_http)

ifdef FD_HAS_HOSTED
$(call add-hdrs,fd_http_server.h)
$(call add-objs,fd_http_server,fd_waltz)
ifdef FD_HAS_LINUX
$(call add-objs,../../tickoni/c_abi/shim/tk_http_socket_linux,fd_waltz)
else ifdef FD_HAS_MACOS
$(call add-objs,../../tickoni/c_abi/shim/tk_http_socket_macos,fd_waltz)
else ifdef FD_HAS_WINDOWS
$(call add-objs,../../tickoni/c_abi/shim/tk_http_socket_windows,fd_waltz)
endif

$(call make-unit-test,test_http_server_transport,test_http_server_transport,fd_waltz fd_ballet fd_util)
$(call run-unit-test,test_http_server_transport)

ifndef FD_HAS_WINDOWS
$(call make-unit-test,test_http_server,test_http_server,fd_waltz fd_ballet fd_util)
$(call run-unit-test,test_http_server)

$(call make-unit-test,test_live_http_server,test_live_http_server,fd_waltz fd_ballet fd_util)

$(call make-fuzz-test,fuzz_httpserver,fuzz_httpserver,fd_waltz fd_ballet fd_util)
endif

$(call make-fuzz-test,fuzz_url_parse,fuzz_url_parse,fd_waltz fd_util)
endif
