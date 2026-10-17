#include "fd_http_server.h"
#include "../../util/fd_util.h"

#include <poll.h>
#include <stdlib.h>
#if FD_HAS_WINDOWS
#include <malloc.h>
#endif

struct fake_transport_state {
  ulong runtime_init_cnt;
  ulong runtime_fini_cnt;
  ulong listen_cnt;
  ulong poll_cnt;
  ulong close_cnt;
};

typedef struct fake_transport_state fake_transport_state_t;

static fake_transport_state_t fake;

static void *
test_alloc( ulong align,
            ulong sz ) {
#if FD_HAS_WINDOWS
  return _aligned_malloc( sz, align );
#else
  return aligned_alloc( align, sz );
#endif
}

static void
test_free( void * mem ) {
#if FD_HAS_WINDOWS
  _aligned_free( mem );
#else
  free( mem );
#endif
}

static tk_http_socket_result_t
fake_ok( void ) {
  return (tk_http_socket_result_t){ .status = TK_HTTP_SOCKET_STATUS_OK };
}

static ulong
fake_poll_scratch_align( void ) {
  return (ulong)_Alignof( struct pollfd );
}

static ulong
fake_poll_scratch_footprint( ulong entry_cnt ) {
  (void)entry_cnt;
  return sizeof( ulong );
}

static tk_http_socket_result_t
fake_runtime_init( void ) {
  fake.runtime_init_cnt++;
  return fake_ok();
}

static tk_http_socket_result_t
fake_runtime_fini( void ) {
  fake.runtime_fini_cnt++;
  return fake_ok();
}

static tk_http_socket_result_t
fake_listen( uint               address,
             ushort             port,
             ulong              backlog,
             tk_http_socket_t * out_socket ) {
  (void)address;
  (void)port;
  (void)backlog;
  fake.listen_cnt++;
  *out_socket = 42UL;
  return fake_ok();
}

static tk_http_socket_result_t
fake_accept( tk_http_socket_t   listener,
             tk_http_socket_t * out_socket ) {
  (void)listener;
  (void)out_socket;
  return (tk_http_socket_result_t){ .status = TK_HTTP_SOCKET_STATUS_WOULD_BLOCK };
}

static tk_http_socket_result_t
fake_poll( tk_http_socket_poll_entry_t * entries,
           ulong                         entry_cnt,
           int                           timeout_ms,
           void *                        scratch,
           ulong *                       out_ready_cnt ) {
  (void)timeout_ms;
  (void)scratch;
  FD_TEST( entry_cnt==2UL );
  FD_TEST( entries[ 1 ].socket==42UL );
  entries[ 1 ].returned_events = TK_HTTP_SOCKET_EVENT_READ;
  *out_ready_cnt = 1UL;
  fake.poll_cnt++;
  return fake_ok();
}

static tk_http_socket_result_t
fake_receive( tk_http_socket_t socket,
              void *           buf,
              ulong            buf_sz,
              ulong *          out_received_sz ) {
  (void)socket;
  (void)buf;
  (void)buf_sz;
  *out_received_sz = 0UL;
  return (tk_http_socket_result_t){ .status = TK_HTTP_SOCKET_STATUS_WOULD_BLOCK };
}

static tk_http_socket_result_t
fake_send( tk_http_socket_t socket,
           void const *     buf,
           ulong            buf_sz,
           ulong *          out_sent_sz ) {
  (void)socket;
  (void)buf;
  (void)buf_sz;
  *out_sent_sz = 0UL;
  return (tk_http_socket_result_t){ .status = TK_HTTP_SOCKET_STATUS_WOULD_BLOCK };
}

static tk_http_socket_result_t
fake_sendv( tk_http_socket_t               socket,
            tk_http_socket_iovec_t const * iov,
            ulong                          iov_cnt,
            ulong *                        out_sent_sz ) {
  (void)socket;
  (void)iov;
  (void)iov_cnt;
  *out_sent_sz = 0UL;
  return (tk_http_socket_result_t){ .status = TK_HTTP_SOCKET_STATUS_WOULD_BLOCK };
}

static tk_http_socket_result_t
fake_close( tk_http_socket_t socket ) {
  FD_TEST( socket==42UL );
  fake.close_cnt++;
  return fake_ok();
}

static tk_http_socket_result_t
fake_local_port( tk_http_socket_t socket,
                 ushort *        out_port ) {
  (void)socket;
  *out_port = 0U;
  return fake_ok();
}

static tk_http_socket_transport_t const fake_transport = {
  .runtime_init = fake_runtime_init,
  .runtime_fini = fake_runtime_fini,
  .poll_scratch_align = fake_poll_scratch_align,
  .poll_scratch_footprint = fake_poll_scratch_footprint,
  .listen = fake_listen,
  .accept = fake_accept,
  .poll = fake_poll,
  .receive = fake_receive,
  .send = fake_send,
  .sendv = fake_sendv,
  .close = fake_close,
  .local_port = fake_local_port,
};

int
main( int     argc,
      char ** argv ) {
  fd_boot( &argc, &argv );

  fd_http_server_params_t params = {
    .max_connection_cnt = 1UL,
    .max_ws_connection_cnt = 0UL,
    .max_request_len = 1024UL,
    .max_ws_recv_frame_len = 1024UL,
    .max_ws_send_frame_cnt = 1UL,
    .outgoing_buffer_sz = 1024UL,
  };
  void * mem = test_alloc( fd_http_server_align(), fd_http_server_footprint( params ) );
  FD_TEST( mem );
  fd_http_server_t * http = fd_http_server_join(
      fd_http_server_new( mem, params, (fd_http_server_callbacks_t){0}, NULL ) );
  FD_TEST( http );
  FD_TEST( fd_http_server_set_transport( http, &fake_transport )==http );
  FD_TEST( fd_http_server_listen( http, 0U, 0U )==http );
  FD_TEST( fd_http_server_socket( http )==42UL );
  FD_TEST( fd_http_server_poll( http, 0 )==1 );
  FD_TEST( fake.runtime_init_cnt==1UL );
  FD_TEST( fake.listen_cnt==1UL );
  FD_TEST( fake.poll_cnt==1UL );
  fd_http_server_delete( fd_http_server_leave( http ) );
  FD_TEST( fake.close_cnt==1UL );
  FD_TEST( fake.runtime_fini_cnt==1UL );
  test_free( mem );

  FD_LOG_NOTICE(( "pass" ));
  fd_halt();
  return 0;
}
