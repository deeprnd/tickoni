#if FD_HAS_LINUX
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "tk_http_socket.h"

#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <poll.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

#ifndef IOV_MAX
#define TK_HTTP_SOCKET_NATIVE_IOV_MAX (1024UL)
#else
#define TK_HTTP_SOCKET_NATIVE_IOV_MAX ((ulong)IOV_MAX)
#endif

static tk_http_socket_result_t
tk_linux_result( tk_http_socket_status_t status,
                 int                     native_error ) {
  tk_http_socket_result_t result = { status, native_error };
  return result;
}

static tk_http_socket_status_t
tk_linux_status( int error ) {
  if( error==EAGAIN || error==EWOULDBLOCK )
    return TK_HTTP_SOCKET_STATUS_WOULD_BLOCK;
  if( error==EINTR )
    return TK_HTTP_SOCKET_STATUS_INTERRUPTED;
  if( error==ECONNRESET || error==ECONNABORTED || error==EPIPE ||
      error==ENETRESET )
    return TK_HTTP_SOCKET_STATUS_PEER_RESET;
  if( error==ENOTCONN || error==ESHUTDOWN )
    return TK_HTTP_SOCKET_STATUS_PEER_CLOSED;
  if( error==EADDRINUSE )
    return TK_HTTP_SOCKET_STATUS_ADDRESS_IN_USE;
  if( error==EMFILE || error==ENFILE || error==ENOBUFS ||
      error==ENOMEM )
    return TK_HTTP_SOCKET_STATUS_RESOURCE_EXHAUSTED;
  if( error==EACCES || error==EPERM )
    return TK_HTTP_SOCKET_STATUS_ACCESS_DENIED;
  if( error==EINVAL || error==EBADF || error==EFAULT ||
      error==ENOTSOCK )
    return TK_HTTP_SOCKET_STATUS_INVALID_ARGUMENT;
  return TK_HTTP_SOCKET_STATUS_SYSTEM_ERROR;
}

static tk_http_socket_result_t
tk_linux_error( int error ) {
  return tk_linux_result( tk_linux_status( error ), error );
}

static int
tk_linux_fd( tk_http_socket_t socket,
             int *             out_fd ) {
  if( FD_UNLIKELY( socket==TK_HTTP_SOCKET_INVALID ||
                   socket>(tk_http_socket_t)INT_MAX ) ) return 0;
  *out_fd = (int)socket;
  return 1;
}

static tk_http_socket_result_t
tk_linux_runtime_init( void ) {
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_runtime_fini( void ) {
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static ulong
tk_linux_poll_scratch_align( void ) {
  return (ulong)_Alignof(struct pollfd);
}

static ulong
tk_linux_poll_scratch_footprint( ulong entry_cnt ) {
  if( FD_UNLIKELY( entry_cnt>
                   TK_HTTP_SOCKET_INVALID/(ulong)sizeof(struct pollfd) ) )
    return TK_HTTP_SOCKET_INVALID;
  return entry_cnt*(ulong)sizeof(struct pollfd);
}

static tk_http_socket_result_t
tk_linux_listen( uint               address,
                 ushort             port,
                 ulong              backlog,
                 tk_http_socket_t * out_socket ) {
  if( FD_UNLIKELY( !out_socket || backlog>(ulong)INT_MAX ) )
    return tk_linux_error( EINVAL );
  *out_socket = TK_HTTP_SOCKET_INVALID;

  int fd = socket( AF_INET,
                   SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC,
                   0 );
  if( FD_UNLIKELY( fd<0 ) ) return tk_linux_error( errno );

  int reuse = 1;
  if( FD_UNLIKELY( setsockopt( fd, SOL_SOCKET, SO_REUSEADDR,
                               &reuse, sizeof(reuse) )<0 ) ) {
    int error = errno;
    (void)close( fd );
    return tk_linux_error( error );
  }

  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = address;

  if( FD_UNLIKELY( bind( fd, (struct sockaddr *)&addr,
                         (socklen_t)sizeof(addr) )<0 ) ) {
    int error = errno;
    (void)close( fd );
    return tk_linux_error( error );
  }
  if( FD_UNLIKELY( listen( fd, (int)backlog )<0 ) ) {
    int error = errno;
    (void)close( fd );
    return tk_linux_error( error );
  }

  *out_socket = (tk_http_socket_t)fd;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_accept( tk_http_socket_t   listener,
                 tk_http_socket_t * out_socket ) {
  if( FD_UNLIKELY( !out_socket ) ) return tk_linux_error( EINVAL );
  *out_socket = TK_HTTP_SOCKET_INVALID;

  int listener_fd;
  if( FD_UNLIKELY( !tk_linux_fd( listener, &listener_fd ) ) )
    return tk_linux_error( EINVAL );

  int fd = accept4( listener_fd, NULL, NULL,
                    SOCK_NONBLOCK | SOCK_CLOEXEC );
  if( FD_UNLIKELY( fd<0 ) ) return tk_linux_error( errno );

  *out_socket = (tk_http_socket_t)fd;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_poll( tk_http_socket_poll_entry_t * entries,
               ulong                         entry_cnt,
               int                           timeout_ms,
               void *                        scratch,
               ulong *                       out_ready_cnt ) {
  if( FD_UNLIKELY( !out_ready_cnt ) ) return tk_linux_error( EINVAL );
  *out_ready_cnt = 0UL;

  ulong align = tk_linux_poll_scratch_align();
  if( FD_UNLIKELY( (entry_cnt && (!entries || !scratch)) ||
                   entry_cnt>(ulong)(nfds_t)~(nfds_t)0 ||
                   (entry_cnt && ((ulong)scratch & (align-1UL))) ) )
    return tk_linux_error( EINVAL );

  struct pollfd * native_entries = (struct pollfd *)scratch;
  for( ulong i=0UL; i<entry_cnt; i++ ) {
    uint requested = entries[ i ].requested_events;
    entries[ i ].returned_events = 0U;
    if( FD_UNLIKELY( requested & ~(TK_HTTP_SOCKET_EVENT_READ |
                                   TK_HTTP_SOCKET_EVENT_WRITE) ) )
      return tk_linux_error( EINVAL );

    if( entries[ i ].socket==TK_HTTP_SOCKET_INVALID ) {
      native_entries[ i ].fd = -1;
    } else {
      if( FD_UNLIKELY( entries[ i ].socket>
                       (tk_http_socket_t)INT_MAX ) )
        return tk_linux_error( EINVAL );
      native_entries[ i ].fd = (int)entries[ i ].socket;
    }
    native_entries[ i ].events = (short)(
        ((requested & TK_HTTP_SOCKET_EVENT_READ)  ? POLLIN  : 0) |
        ((requested & TK_HTTP_SOCKET_EVENT_WRITE) ? POLLOUT : 0) );
    native_entries[ i ].revents = 0;
  }

  int ready_cnt = poll( native_entries, (nfds_t)entry_cnt, timeout_ms );
  if( FD_UNLIKELY( ready_cnt<0 ) ) return tk_linux_error( errno );

  for( ulong i=0UL; i<entry_cnt; i++ ) {
    short returned = native_entries[ i ].revents;
    uint events = 0U;
    if( returned & POLLIN  ) events |= TK_HTTP_SOCKET_EVENT_READ;
    if( returned & POLLOUT ) events |= TK_HTTP_SOCKET_EVENT_WRITE;
    if( returned & POLLERR ) events |= TK_HTTP_SOCKET_EVENT_ERROR;
    if( returned & POLLHUP ) events |= TK_HTTP_SOCKET_EVENT_HANGUP;
    if( returned & POLLNVAL) events |= TK_HTTP_SOCKET_EVENT_INVALID;
    entries[ i ].returned_events = events;
  }

  *out_ready_cnt = (ulong)ready_cnt;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_receive( tk_http_socket_t socket,
                  void *           buf,
                  ulong            buf_sz,
                  ulong *          out_received_sz ) {
  if( FD_UNLIKELY( !out_received_sz || (!buf && buf_sz) ||
                   buf_sz>(ulong)SSIZE_MAX ) )
    return tk_linux_error( EINVAL );
  *out_received_sz = 0UL;
  if( !buf_sz ) return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );

  int fd;
  if( FD_UNLIKELY( !tk_linux_fd( socket, &fd ) ) )
    return tk_linux_error( EINVAL );

  ssize_t received_sz = recv( fd, buf, (size_t)buf_sz, 0 );
  if( FD_UNLIKELY( received_sz<0 ) ) return tk_linux_error( errno );
  if( FD_UNLIKELY( !received_sz ) )
    return tk_linux_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0 );

  *out_received_sz = (ulong)received_sz;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_send( tk_http_socket_t socket,
               void const *     buf,
               ulong            buf_sz,
               ulong *          out_sent_sz ) {
  if( FD_UNLIKELY( !out_sent_sz || (!buf && buf_sz) ||
                   buf_sz>(ulong)SSIZE_MAX ) )
    return tk_linux_error( EINVAL );
  *out_sent_sz = 0UL;
  if( !buf_sz ) return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );

  int fd;
  if( FD_UNLIKELY( !tk_linux_fd( socket, &fd ) )
      ) return tk_linux_error( EINVAL );

  ssize_t sent_sz = send( fd, buf, (size_t)buf_sz, MSG_NOSIGNAL );
  if( FD_UNLIKELY( sent_sz<0 ) ) return tk_linux_error( errno );
  if( FD_UNLIKELY( !sent_sz ) )
    return tk_linux_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0 );

  *out_sent_sz = (ulong)sent_sz;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_sendv( tk_http_socket_t               socket,
                tk_http_socket_iovec_t const * iov,
                ulong                          iov_cnt,
                ulong *                        out_sent_sz ) {
  if( FD_UNLIKELY( !out_sent_sz || (!iov && iov_cnt) ||
                   iov_cnt>TK_HTTP_SOCKET_NATIVE_IOV_MAX ) )
    return tk_linux_error( EINVAL );
  *out_sent_sz = 0UL;
  if( !iov_cnt ) return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );

  int fd;
  if( FD_UNLIKELY( !tk_linux_fd( socket, &fd ) ) )
    return tk_linux_error( EINVAL );

  struct iovec native_iov[ TK_HTTP_SOCKET_NATIVE_IOV_MAX ];
  ulong total_sz = 0UL;
  for( ulong i=0UL; i<iov_cnt; i++ ) {
    if( FD_UNLIKELY( (!iov[ i ].base && iov[ i ].len) ||
                     iov[ i ].len>(ulong)SSIZE_MAX-total_sz ) )
      return tk_linux_error( EINVAL );
    native_iov[ i ].iov_base = (void *)iov[ i ].base;
    native_iov[ i ].iov_len  = (size_t)iov[ i ].len;
    total_sz += iov[ i ].len;
  }
  if( !total_sz ) return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );

  struct msghdr msg;
  memset( &msg, 0, sizeof(msg) );
  msg.msg_iov    = native_iov;
  msg.msg_iovlen = (size_t)iov_cnt;

  ssize_t sent_sz = sendmsg( fd, &msg, MSG_NOSIGNAL );
  if( FD_UNLIKELY( sent_sz<0 ) ) return tk_linux_error( errno );
  if( FD_UNLIKELY( !sent_sz ) )
    return tk_linux_result( TK_HTTP_SOCKET_STATUS_PEER_CLOSED, 0 );

  *out_sent_sz = (ulong)sent_sz;
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_close( tk_http_socket_t socket ) {
  int fd;
  if( FD_UNLIKELY( !tk_linux_fd( socket, &fd ) ) )
    return tk_linux_error( EINVAL );
  if( FD_UNLIKELY( close( fd )<0 ) ) return tk_linux_error( errno );
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_result_t
tk_linux_local_port( tk_http_socket_t socket,
                     ushort *        out_port ) {
  if( FD_UNLIKELY( !out_port ) ) return tk_linux_error( EINVAL );
  *out_port = 0U;

  int fd;
  if( FD_UNLIKELY( !tk_linux_fd( socket, &fd ) ) )
    return tk_linux_error( EINVAL );

  struct sockaddr_in addr;
  socklen_t addr_sz = (socklen_t)sizeof(addr);
  if( FD_UNLIKELY( getsockname( fd, (struct sockaddr *)&addr,
                                &addr_sz )<0 ) )
    return tk_linux_error( errno );
  if( FD_UNLIKELY( addr_sz<(socklen_t)sizeof(addr) ||
                   addr.sin_family!=AF_INET ) )
    return tk_linux_error( EINVAL );

  *out_port = ntohs( addr.sin_port );
  return tk_linux_result( TK_HTTP_SOCKET_STATUS_OK, 0 );
}

static tk_http_socket_transport_t const tk_linux_transport = {
  .runtime_init          = tk_linux_runtime_init,
  .runtime_fini          = tk_linux_runtime_fini,
  .poll_scratch_align    = tk_linux_poll_scratch_align,
  .poll_scratch_footprint= tk_linux_poll_scratch_footprint,
  .listen                = tk_linux_listen,
  .accept                = tk_linux_accept,
  .poll                  = tk_linux_poll,
  .receive               = tk_linux_receive,
  .send                  = tk_linux_send,
  .sendv                 = tk_linux_sendv,
  .close                 = tk_linux_close,
  .local_port            = tk_linux_local_port,
};

tk_http_socket_transport_t const *
tk_http_socket_transport( void ) {
  return &tk_linux_transport;
}

#endif /* FD_HAS_LINUX */
