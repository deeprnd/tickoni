#if FD_HAS_WINDOWS

#include "tk_http_socket.h"

#include <winsock2.h>
#include <windows.h>

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define TK_HTTP_SOCKET_NATIVE_IOV_MAX (1024UL)

_Static_assert( sizeof(tk_http_socket_t)==8UL,
                "Windows socket handles require a 64-bit project ulong" );
_Static_assert( sizeof(tk_http_socket_t)>=sizeof(SOCKET),
                "tk_http_socket_t must hold SOCKET without narrowing" );

static volatile LONG tk_windows_runtime_refs;

static tk_http_socket_result_t
tk_windows_result( tk_http_socket_status_t status,
                   uint                    native_error ) {
  tk_http_socket_result_t result = { status, native_error };
  return result;
}

static tk_http_socket_status_t
tk_windows_status( uint error ) {
  if( error==(uint)WSAEWOULDBLOCK )
    return TK_HTTP_SOCKET_STATUS_WOULD_BLOCK;
  if( error==(uint)WSAEINTR )
    return TK_HTTP_SOCKET_STATUS_INTERRUPTED;
  if( error==(uint)WSAECONNRESET || error==(uint)WSAECONNABORTED ||
      error==(uint)WSAENETRESET || error==(uint)WSAETIMEDOUT )
    return TK_HTTP_SOCKET_STATUS_PEER_RESET;
  if( error==(uint)WSAENOTCONN || error==(uint)WSAESHUTDOWN ||
      error==(uint)WSAEDISCON )
    return TK_HTTP_SOCKET_STATUS_PEER_CLOSED;
  if( error==(uint)WSAEADDRINUSE )
    return TK_HTTP_SOCKET_STATUS_ADDRESS_IN_USE;
  if( error==(uint)WSAEMFILE || error==(uint)WSAENOBUFS ||
      error==(uint)WSA_NOT_ENOUGH_MEMORY ||
      error==(uint)ERROR_NOT_ENOUGH_MEMORY ||
      error==(uint)ERROR_NO_SYSTEM_RESOURCES ||
      error==(uint)ERROR_TOO_MANY_OPEN_FILES )
    return TK_HTTP_SOCKET_STATUS_RESOURCE_EXHAUSTED;
  if( error==(uint)WSAEACCES || error==(uint)ERROR_ACCESS_DENIED )
    return TK_HTTP_SOCKET_STATUS_ACCESS_DENIED;
  if( error==(uint)WSAEINVAL || error==(uint)WSAEFAULT ||
      error==(uint)WSAENOTSOCK || error==(uint)ERROR_INVALID_HANDLE ||
      error==(uint)ERROR_INVALID_PARAMETER )
    return TK_HTTP_SOCKET_STATUS_INVALID_ARGUMENT;
  return TK_HTTP_SOCKET_STATUS_SYSTEM_ERROR;
}

static tk_http_socket_result_t
tk_windows_error( uint error ) {
  return tk_windows_result( tk_windows_status( error ), error );
}

static SOCKET
tk_windows_socket( tk_http_socket_t socket ) {
  return (SOCKET)(UINT_PTR)socket;
}

static tk_http_socket_t
tk_windows_handle( SOCKET socket ) {
  return (tk_http_socket_t)(UINT_PTR)socket;
}

static uint
tk_windows_configure_socket( SOCKET socket ) {
  /* WSASocketW already requested WSA_FLAG_NO_HANDLE_INHERIT.  SOCKET is a
     Winsock resource, not a Win32 HANDLE for SetHandleInformation; the latter
     fails before the listener reaches bind/listen on Windows. */
  u_long nonblocking = 1UL;
  if( FD_UNLIKELY( ioctlsocket( socket, FIONBIO, &nonblocking )==
                   SOCKET_ERROR ) )
    return (uint)WSAGetLastError();
  return 0U;
}

static tk_http_socket_result_t
tk_windows_runtime_init( void ) {
  WSADATA data;
  int error = WSAStartup( MAKEWORD( 2, 2 ), &data );
  if( FD_UNLIKELY( error ) ) return tk_windows_error( (uint)error );

  if( FD_UNLIKELY( LOBYTE( data.wVersion )!=2 ||
                   HIBYTE( data.wVersion )!=2 ) ) {
    (void)WSACleanup();
    return tk_windows_error( (uint)WSAVERNOTSUPPORTED );
  }

  LONG refs = InterlockedIncrement( &tk_windows_runtime_refs );
  if( FD_UNLIKELY( refs<=0L ) ) {
    (void)InterlockedDecrement( &tk_windows_runtime_refs );
    (void)WSACleanup();
    return tk_windows_error( (uint)WSAENOBUFS );
  }
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_runtime_fini( void ) {
  LONG refs;
  for(;;) {
    refs = InterlockedCompareExchange( &tk_windows_runtime_refs, 0L, 0L );
    if( FD_UNLIKELY( refs<=0L ) )
      return tk_windows_error( (uint)WSAEINVAL );
    if( InterlockedCompareExchange( &tk_windows_runtime_refs,
                                    refs-1L, refs )==refs ) break;
  }

  if( FD_UNLIKELY( WSACleanup()==SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static ulong
tk_windows_poll_scratch_align( void ) {
  return (ulong)_Alignof(WSAPOLLFD);
}

static ulong
tk_windows_poll_scratch_footprint( ulong entry_cnt ) {
  if( FD_UNLIKELY( entry_cnt>
                   TK_HTTP_SOCKET_INVALID/(ulong)sizeof(WSAPOLLFD) ) )
    return TK_HTTP_SOCKET_INVALID;
  return entry_cnt*(ulong)sizeof(WSAPOLLFD);
}

static tk_http_socket_result_t
tk_windows_listen( uint               address,
                   ushort             port,
                   ulong              backlog,
                   tk_http_socket_t * out_socket ) {
  if( FD_UNLIKELY( !out_socket || backlog>(ulong)INT_MAX ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_socket = TK_HTTP_SOCKET_INVALID;

  SOCKET socket = WSASocketW( AF_INET, SOCK_STREAM, IPPROTO_TCP,
                              NULL, 0U, WSA_FLAG_NO_HANDLE_INHERIT );
  if( FD_UNLIKELY( socket==INVALID_SOCKET ) )
    return tk_windows_error( (uint)WSAGetLastError() );

  uint error = tk_windows_configure_socket( socket );
  if( FD_UNLIKELY( error ) ) {
    (void)closesocket( socket );
    return tk_windows_error( error );
  }

  BOOL exclusive = TRUE;
  if( FD_UNLIKELY( setsockopt( socket, SOL_SOCKET,
                               SO_EXCLUSIVEADDRUSE,
                               (char const *)&exclusive,
                               (int)sizeof(exclusive) )==SOCKET_ERROR ) ) {
    error = (uint)WSAGetLastError();
    (void)closesocket( socket );
    return tk_windows_error( error );
  }

  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = address;

  if( FD_UNLIKELY( bind( socket, (struct sockaddr const *)&addr,
                         (int)sizeof(addr) )==SOCKET_ERROR ) ) {
    error = (uint)WSAGetLastError();
    (void)closesocket( socket );
    return tk_windows_error( error );
  }
  if( FD_UNLIKELY( listen( socket, (int)backlog )==SOCKET_ERROR ) ) {
    error = (uint)WSAGetLastError();
    (void)closesocket( socket );
    return tk_windows_error( error );
  }

  *out_socket = tk_windows_handle( socket );
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_accept( tk_http_socket_t   listener,
                   tk_http_socket_t * out_socket ) {
  if( FD_UNLIKELY( !out_socket ||
                   listener==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_socket = TK_HTTP_SOCKET_INVALID;

  SOCKET socket = accept( tk_windows_socket( listener ), NULL, NULL );
  if( FD_UNLIKELY( socket==INVALID_SOCKET ) )
    return tk_windows_error( (uint)WSAGetLastError() );

  uint error = tk_windows_configure_socket( socket );
  if( FD_UNLIKELY( error ) ) {
    (void)closesocket( socket );
    return tk_windows_error( error );
  }

  *out_socket = tk_windows_handle( socket );
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_poll( tk_http_socket_poll_entry_t * entries,
                 ulong                         entry_cnt,
                 int                           timeout_ms,
                 void *                        scratch,
                 ulong *                       out_ready_cnt ) {
  if( FD_UNLIKELY( !out_ready_cnt ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_ready_cnt = 0UL;

  ulong align = tk_windows_poll_scratch_align();
  if( FD_UNLIKELY( (entry_cnt && (!entries || !scratch)) ||
                   entry_cnt>(ulong)ULONG_MAX ||
                   (entry_cnt && ((ulong)scratch & (align-1UL))) ) )
    return tk_windows_error( (uint)WSAEINVAL );

  WSAPOLLFD * native_entries = (WSAPOLLFD *)scratch;
  ULONG native_cnt = 0UL;
  for( ulong i=0UL; i<entry_cnt; i++ ) {
    uint requested = entries[ i ].requested_events;
    entries[ i ].returned_events = 0U;
    if( FD_UNLIKELY( requested & ~(TK_HTTP_SOCKET_EVENT_READ |
                                   TK_HTTP_SOCKET_EVENT_WRITE) ) )
      return tk_windows_error( (uint)WSAEINVAL );
    if( entries[ i ].socket==TK_HTTP_SOCKET_INVALID ) continue;

    native_entries[ native_cnt ].fd =
        tk_windows_socket( entries[ i ].socket );
    native_entries[ native_cnt ].events = (SHORT)(
        ((requested & TK_HTTP_SOCKET_EVENT_READ)  ? POLLIN  : 0) |
        ((requested & TK_HTTP_SOCKET_EVENT_WRITE) ? POLLOUT : 0) );
    native_entries[ native_cnt ].revents = 0;
    native_cnt++;
  }

  if( FD_UNLIKELY( !native_cnt ) ) {
    if( timeout_ms<0 ) Sleep( INFINITE );
    else if( timeout_ms ) Sleep( (DWORD)timeout_ms );
    return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
  }

  int ready_cnt = WSAPoll( native_entries, native_cnt, timeout_ms );
  if( FD_UNLIKELY( ready_cnt==SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );

  ULONG native_idx = 0UL;
  for( ulong i=0UL; i<entry_cnt; i++ ) {
    if( entries[ i ].socket==TK_HTTP_SOCKET_INVALID ) continue;
    SHORT returned = native_entries[ native_idx++ ].revents;
    uint events = 0U;
    if( returned & POLLIN  ) events |= TK_HTTP_SOCKET_EVENT_READ;
    if( returned & POLLOUT ) events |= TK_HTTP_SOCKET_EVENT_WRITE;
    if( returned & POLLERR ) events |= TK_HTTP_SOCKET_EVENT_ERROR;
    if( returned & POLLHUP ) events |= TK_HTTP_SOCKET_EVENT_HANGUP;
    if( returned & POLLNVAL) events |= TK_HTTP_SOCKET_EVENT_INVALID;
    entries[ i ].returned_events = events;
  }

  *out_ready_cnt = (ulong)ready_cnt;
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_receive( tk_http_socket_t socket,
                    void *           buf,
                    ulong            buf_sz,
                    ulong *          out_received_sz ) {
  if( FD_UNLIKELY( !out_received_sz || (!buf && buf_sz) ||
                   buf_sz>(ulong)INT_MAX ||
                   socket==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_received_sz = 0UL;
  if( !buf_sz ) return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );

  int received_sz = recv( tk_windows_socket( socket ), (char *)buf,
                          (int)buf_sz, 0 );
  if( FD_UNLIKELY( received_sz==SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  if( FD_UNLIKELY( !received_sz ) )
    return tk_windows_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0U );

  *out_received_sz = (ulong)received_sz;
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_send( tk_http_socket_t socket,
                 void const *     buf,
                 ulong            buf_sz,
                 ulong *          out_sent_sz ) {
  if( FD_UNLIKELY( !out_sent_sz || (!buf && buf_sz) ||
                   buf_sz>(ulong)ULONG_MAX ||
                   socket==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_sent_sz = 0UL;
  if( !buf_sz ) return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );

  WSABUF native_buf = {
    .len = (ULONG)buf_sz,
    .buf = (CHAR *)buf,
  };
  DWORD sent_sz = 0UL;
  if( FD_UNLIKELY( WSASend( tk_windows_socket( socket ), &native_buf,
                            1UL, &sent_sz, 0UL, NULL, NULL )==
                   SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  if( FD_UNLIKELY( !sent_sz ) )
    return tk_windows_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0U );

  *out_sent_sz = (ulong)sent_sz;
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_sendv( tk_http_socket_t               socket,
                  tk_http_socket_iovec_t const * iov,
                  ulong                          iov_cnt,
                  ulong *                        out_sent_sz ) {
  if( FD_UNLIKELY( !out_sent_sz || (!iov && iov_cnt) ||
                   iov_cnt>TK_HTTP_SOCKET_NATIVE_IOV_MAX ||
                   socket==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_sent_sz = 0UL;
  if( !iov_cnt ) return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );

  WSABUF native_iov[ TK_HTTP_SOCKET_NATIVE_IOV_MAX ];
  int has_data = 0;
  for( ulong i=0UL; i<iov_cnt; i++ ) {
    if( FD_UNLIKELY( (!iov[ i ].base && iov[ i ].len) ||
                     iov[ i ].len>(ulong)ULONG_MAX ) )
      return tk_windows_error( (uint)WSAEINVAL );
    native_iov[ i ].buf = (CHAR *)iov[ i ].base;
    native_iov[ i ].len = (ULONG)iov[ i ].len;
    has_data |= !!iov[ i ].len;
  }
  if( !has_data ) return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );

  DWORD sent_sz = 0UL;
  if( FD_UNLIKELY( WSASend( tk_windows_socket( socket ), native_iov,
                            (DWORD)iov_cnt, &sent_sz, 0UL, NULL, NULL )==
                   SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  if( FD_UNLIKELY( !sent_sz ) )
    return tk_windows_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0U );

  *out_sent_sz = (ulong)sent_sz;
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_close( tk_http_socket_t socket ) {
  if( FD_UNLIKELY( socket==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  if( FD_UNLIKELY( closesocket( tk_windows_socket( socket ) )==
                   SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_result_t
tk_windows_local_port( tk_http_socket_t socket,
                       ushort *        out_port ) {
  if( FD_UNLIKELY( !out_port || socket==TK_HTTP_SOCKET_INVALID ) )
    return tk_windows_error( (uint)WSAEINVAL );
  *out_port = 0U;

  struct sockaddr_in addr;
  int addr_sz = (int)sizeof(addr);
  if( FD_UNLIKELY( getsockname( tk_windows_socket( socket ),
                                (struct sockaddr *)&addr,
                                &addr_sz )==SOCKET_ERROR ) )
    return tk_windows_error( (uint)WSAGetLastError() );
  if( FD_UNLIKELY( addr_sz<(int)sizeof(addr) ||
                   addr.sin_family!=AF_INET ) )
    return tk_windows_error( (uint)WSAEINVAL );

  *out_port = ntohs( addr.sin_port );
  return tk_windows_result( TK_HTTP_SOCKET_STATUS_OK, 0U );
}

static tk_http_socket_transport_t const tk_windows_transport = {
  .runtime_init          = tk_windows_runtime_init,
  .runtime_fini          = tk_windows_runtime_fini,
  .poll_scratch_align    = tk_windows_poll_scratch_align,
  .poll_scratch_footprint= tk_windows_poll_scratch_footprint,
  .listen                = tk_windows_listen,
  .accept                = tk_windows_accept,
  .poll                  = tk_windows_poll,
  .receive               = tk_windows_receive,
  .send                  = tk_windows_send,
  .sendv                 = tk_windows_sendv,
  .close                 = tk_windows_close,
  .local_port            = tk_windows_local_port,
};

tk_http_socket_transport_t const *
tk_http_socket_transport( void ) {
  return &tk_windows_transport;
}

#endif /* FD_HAS_WINDOWS */
