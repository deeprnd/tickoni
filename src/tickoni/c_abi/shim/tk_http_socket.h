#ifndef HEADER_tickoni_c_abi_shim_tk_http_socket_h
#define HEADER_tickoni_c_abi_shim_tk_http_socket_h

#include "../../../util/fd_util_base.h"

typedef ulong tk_http_socket_t;

/* TK_HTTP_SOCKET_INVALID has ULONG_MAX semantics for the project ulong.
   Unlike the C ULONG_MAX macro, it remains 64 bits on Windows. */
#define TK_HTTP_SOCKET_INVALID ((tk_http_socket_t)~(tk_http_socket_t)0)

#define TK_HTTP_SOCKET_EVENT_READ    (1U<<0)
#define TK_HTTP_SOCKET_EVENT_WRITE   (1U<<1)
#define TK_HTTP_SOCKET_EVENT_ERROR   (1U<<2)
#define TK_HTTP_SOCKET_EVENT_HANGUP  (1U<<3)
#define TK_HTTP_SOCKET_EVENT_INVALID (1U<<4)

typedef struct {
  tk_http_socket_t socket;
  uint             requested_events;
  uint             returned_events;
} tk_http_socket_poll_entry_t;

typedef struct {
  void const * base;
  ulong        len;
} tk_http_socket_iovec_t;

typedef enum {
  TK_HTTP_SOCKET_STATUS_OK = 0,
  TK_HTTP_SOCKET_STATUS_WOULD_BLOCK,
  TK_HTTP_SOCKET_STATUS_INTERRUPTED,
  TK_HTTP_SOCKET_STATUS_PEER_CLOSED,
  TK_HTTP_SOCKET_STATUS_PEER_RESET,
  TK_HTTP_SOCKET_STATUS_ADDRESS_IN_USE,
  TK_HTTP_SOCKET_STATUS_RESOURCE_EXHAUSTED,
  TK_HTTP_SOCKET_STATUS_ACCESS_DENIED,
  TK_HTTP_SOCKET_STATUS_INVALID_ARGUMENT,
  TK_HTTP_SOCKET_STATUS_SYSTEM_ERROR
} tk_http_socket_status_t;

typedef struct {
  tk_http_socket_status_t status;
  uint                    native_error;
} tk_http_socket_result_t;

typedef struct tk_http_socket_transport {
  tk_http_socket_result_t
  (*runtime_init)( void );

  tk_http_socket_result_t
  (*runtime_fini)( void );

  ulong
  (*poll_scratch_align)( void );

  ulong
  (*poll_scratch_footprint)( ulong entry_cnt );

  tk_http_socket_result_t
  (*listen)( uint               address,
             ushort             port,
             ulong              backlog,
             tk_http_socket_t * out_socket );

  tk_http_socket_result_t
  (*accept)( tk_http_socket_t   listener,
             tk_http_socket_t * out_socket );

  tk_http_socket_result_t
  (*poll)( tk_http_socket_poll_entry_t * entries,
           ulong                         entry_cnt,
           int                           timeout_ms,
           void *                        scratch,
           ulong *                       out_ready_cnt );

  tk_http_socket_result_t
  (*receive)( tk_http_socket_t socket,
              void *           buf,
              ulong            buf_sz,
              ulong *          out_received_sz );

  tk_http_socket_result_t
  (*send)( tk_http_socket_t socket,
           void const *     buf,
           ulong            buf_sz,
           ulong *          out_sent_sz );

  tk_http_socket_result_t
  (*sendv)( tk_http_socket_t               socket,
            tk_http_socket_iovec_t const * iov,
            ulong                          iov_cnt,
            ulong *                        out_sent_sz );

  tk_http_socket_result_t
  (*close)( tk_http_socket_t socket );

  tk_http_socket_result_t
  (*local_port)( tk_http_socket_t socket,
                 ushort *        out_port );
} tk_http_socket_transport_t;

/* tk_http_socket_transport returns the backend for the build target. */
tk_http_socket_transport_t const *
tk_http_socket_transport( void );

#endif /* HEADER_tickoni_c_abi_shim_tk_http_socket_h */
