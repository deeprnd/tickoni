/* Unit tests for fd_log_windows.c — logging stack, time conversion, format output.
 *
 * Tests:
 *   - fd_log_wallclock() — verify non-zero, non-negative output
 *   - fd_log_wallclock_cstr() — verify format layout
 *   - fd_log_private_0() — format a message
 *   - fd_log_private_boot() — verify initialization
 *   - fd_log_private_app_set()/fd_log_app() — round-trip
 *   - fd_log_wallclock_set() + custom clock — verify custom clock used
 *   - fd_log_private_1() with level >= stderr threshold — emit
 *   - fd_log_private_1() with level < stderr threshold — silent
 *   - fd_log_private_boot_custom() — stores levels, fd_log_level_stderr() returns configured value
 *   - fd_log_colorize()/set() round-trip
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"

#if FD_HAS_WINDOWS

/* fd_log_windows.c exports */
extern long fd_log_wallclock( void );
extern char *fd_log_wallclock_cstr( long now, char *buf );
extern void fd_log_private_boot( int *pargc, char **pargv );
extern void fd_log_private_boot_custom(
  ulong        app_id, char const * app,
  ulong        thread_id, char const * thread,
  ulong        host_id, char const * host,
  ulong        cpu_id, char const * cpu,
  ulong        group_id, char const * group,
  ulong        tid,
  ulong        user_id, char const * user,
  int          dedup,
  int          colorize,
  int          level_logfile,
  int          level_stderr,
  int          level_flush,
  int          level_core,
  int          log_fd, char const * log_path );
extern void fd_log_private_app_set( char const *app );
extern char const *fd_log_app( void );
extern void fd_log_wallclock_set( fd_clock_func_t clock, void const *args );
extern char const *fd_log_private_0( char const *fmt, ... );
extern void fd_log_private_1( int level, long now, char const *file, int line,
                              char const *func, char const *msg );

/* Accessors */
extern int fd_log_colorize( void );
extern int fd_log_level_stderr( void );
extern int fd_log_level_logfile( void );
extern void fd_log_colorize_set( int mode );
extern void fd_log_level_stderr_set( int level );
extern void fd_log_level_logfile_set( int level );

/* Custom clock that returns a fixed value. */
static long
custom_clock( void const *args ) {
  (void)args;
  return 0x12345678L;
}

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_log_wallclock() returns a valid timestamp */
  {
    long ts = fd_log_wallclock();
    FD_TEST( ts > 0 );
  }

  /* Test 2: fd_log_wallclock_cstr() produces correct format */
  {
    long ts = fd_log_wallclock();
    char buf[ 64 ];
    char *result = fd_log_wallclock_cstr( ts, buf );
    FD_TEST( result != NULL );
    FD_TEST( result == buf );
    /* Format: YYYY-MM-DD hh:mm:ss.NNNNNNNNN GMT ±HH */
    FD_TEST( strlen( buf ) >= 31 );
    FD_TEST( buf[0] == '2' ); /* year starts with '2' */
    FD_TEST( buf[4] == '-' );
    FD_TEST( buf[7] == '-' );
    FD_TEST( strncmp( buf + 26, " GMT", 4 ) == 0 );
  }

  /* Test 3: fd_log_private_0() formats a message */
  {
    char const *result = fd_log_private_0( "test %d %s", 42, "hello" );
    FD_TEST( result != NULL );
    FD_TEST( strlen( result ) > 0 );
  }

  /* Test 4: fd_log_private_boot() initializes state */
  {
    fd_log_private_boot( NULL, NULL );
    FD_TEST( fd_log_wallclock() > 0 ); /* clock function is set */
  }

  /* Test 5: fd_log_private_app_set()/fd_log_app() round-trip */
  {
    fd_log_private_boot( NULL, NULL );
    fd_log_private_app_set( "test_app" );
    char const *app = fd_log_app();
    FD_TEST( app != NULL );
    FD_TEST( strcmp( app, "test_app" ) == 0 );
  }

  /* Test 6: Custom clock function */
  {
    fd_log_private_boot( NULL, NULL );
    fd_log_wallclock_set( custom_clock, NULL );
    long ts = fd_log_wallclock();
    FD_TEST( ts == 0x12345678L );
  }

  /* Test 7: fd_log_private_1() respects configurable stderr threshold
   *
   * Strategy: redirect stderr to a pipe, call fd_log_private_1,
   * read pipe contents, verify expected output.
   *
   * Step 1: boot_custom with level_stderr=2 (NOTICE). Level 1 (INFO)
   * should be silent, level 2 (NOTICE) should emit.
   *
   * Step 2: manually set threshold to 0 (DEBUG). Now level 0 should emit.
   *
   * Step 3: manually set threshold to 4 (ERR). Now level 3 (WARNING)
   * should be silent. */
  {
    /* Save original stderr fd */
    int saved_stderr = _dup( 2 );
    FD_TEST( saved_stderr >= 0 );

    /* Create pipe: read end = pipe_read, write end = pipe_write */
    HANDLE pipe_read;
    HANDLE pipe_write;
    FD_TEST( CreatePipe( &pipe_read, &pipe_write, NULL, 0 ) );

    /* Convert HANDLE -> osfhandle -> int fd for _dup2 */
    intptr_t os_pipe_write = _open_osfhandle( (intptr_t)pipe_write, _O_WRONLY );
    FD_TEST( os_pipe_write >= 0 );

    /* Redirect fd 2 (stderr) to our pipe */
    int rc = _dup2( (int)os_pipe_write, 2 );
    FD_TEST( rc == 0 );

    /* Clear pipe buffer */
    char pipe_buf[ 1024 ];
    DWORD bytes_read;
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );

    /* --- Step 1: boot_custom with level_stderr=2 (default NOTICE) --- */
    fd_log_private_boot_custom(
      0UL, "test_app", 0UL, "main",
      0UL, "localhost",
      0UL, "0",
      0UL, "default",
      0UL, 0UL, "user",
      0,  /* dedup */
      0,  /* colorize */
      0,  /* level_logfile */
      2,  /* level_stderr = NOTICE */
      0,  /* level_flush */
      0,  /* level_core */
      -1, /* log_fd */
      NULL );

    /* Verify accessor returns configured value */
    FD_TEST( fd_log_level_stderr() == 2 );

    char const *test_file = "test_windows.c";
    char const *test_msg = "test message level 1";

    /* Level 1 (INFO) — should NOT emit (below threshold of 2) */
    fd_log_private_1( 1, 0L, test_file, 100, "test_func", test_msg );
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read == 0 );

    /* Level 2 (NOTICE) — should emit (at threshold) */
    fd_log_private_1( 2, 0L, test_file, 101, "test_func", "test message level 2" );
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read > 0 );
    pipe_buf[ bytes_read ] = '\0';
    FD_TEST( strstr( pipe_buf, "NOTICE" ) != NULL );
    FD_TEST( strstr( pipe_buf, "test_windows.c" ) != NULL );
    FD_TEST( strstr( pipe_buf, "test message level 2" ) != NULL );

    /* --- Step 2: lower threshold to 0 (DEBUG) via setter --- */
    fd_log_level_stderr_set( 0 );
    FD_TEST( fd_log_level_stderr() == 0 );

    /* Drain pipe */
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );

    /* Level 0 (DEBUG) — should now emit (threshold is 0) */
    fd_log_private_1( 0, 0L, test_file, 102, "test_func", "debug message" );
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read > 0 );
    pipe_buf[ bytes_read ] = '\0';
    FD_TEST( strstr( pipe_buf, "DEBUG" ) != NULL );
    FD_TEST( strstr( pipe_buf, "debug message" ) != NULL );

    /* --- Step 3: raise threshold to 4 (ERR) via setter --- */
    fd_log_level_stderr_set( 4 );
    FD_TEST( fd_log_level_stderr() == 4 );

    /* Drain pipe */
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );

    /* Level 3 (WARNING) — should NOT emit (below threshold of 4) */
    fd_log_private_1( 3, 0L, test_file, 103, "test_func", "warning message" );
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read == 0 );

    /* Level 4 (ERR) — should emit (at threshold of 4) */
    fd_log_private_1( 4, 0L, test_file, 104, "test_func", "error message" );
    ReadFile( pipe_read, pipe_buf, sizeof( pipe_buf ) - 1, &bytes_read, NULL );
    FD_TEST( bytes_read > 0 );
    pipe_buf[ bytes_read ] = '\0';
    FD_TEST( strstr( pipe_buf, "ERR" ) != NULL );

    /* Restore original stderr */
    _dup2( saved_stderr, 2 );
    _close( saved_stderr );
    CloseHandle( pipe_read );
    CloseHandle( pipe_write );
  }

  /* Test 8: fd_log_colorize()/fd_log_colorize_set() round-trip */
  {
    fd_log_private_boot( NULL, NULL );
    FD_TEST( fd_log_colorize() == 0 ); /* default off */
    fd_log_colorize_set( 1 );
    FD_TEST( fd_log_colorize() == 1 );
    fd_log_colorize_set( 0 );
    FD_TEST( fd_log_colorize() == 0 );
  }

  /* Test 9: boot_custom stores colorize and level_logfile */
  {
    fd_log_private_boot_custom(
      0UL, "test_app", 0UL, "main",
      0UL, "localhost",
      0UL, "0",
      0UL, "default",
      0UL, 0UL, "user",
      0, 1,  /* colorize=1 */
      3,      /* level_logfile=3 */
      2,      /* level_stderr=2 */
      0, 0,   /* level_flush, level_core */
      -1, NULL );

    FD_TEST( fd_log_colorize() == 1 );
    FD_TEST( fd_log_level_logfile() == 3 );
  }

  FD_LOG_NOTICE(( "pass" ));
  fd_halt();
  return 0;
}

#else

/* On non-Windows, this file is a no-op stub. */
int
main( int argc, char **argv ) {
  (void)argc;
  (void)argv;
  return 0;
}

#endif
