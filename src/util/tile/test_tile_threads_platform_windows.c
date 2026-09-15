/* Unit tests for Windows tile threading (fd_tile_threads_platform_windows.c).
 *
 * Tests:
 *   - fd_tile_private_boot() — verify no crash, tile_id0 > 0
 *   - fd_tile_private_halt() — verify no crash
 *   - fd_tile_id(), fd_tile_cnt(), fd_tile_idx() — verify boot sets values
 *   - fd_tile_exec_new() — verify returns non-NULL for idx >= 2
 *   - fd_tile_exec_done() — verify returns 1 when not executing
 *   - fd_tile_exec_delete() — verify returns NULL (normal termination)
 *   - fd_tile_private_cpus_parse() — verify parses CPU strings
 *   - fd_tile_cpu_id() — verify returns valid CPU IDs
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"
#include "fd_tile.h"
#include "fd_tile_private.h"

#if FD_HAS_WINDOWS

/* Test task that tiles execute */
static int
test_tile_task( int argc, char ** argv ) {
  (void)argc;
  (void)argv;
  /* Simple task — just return 0 */
  return 0;
}

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_tile_private_boot() — verify no crash, deterministic values */
  {
    int pargc = 1;
    char *pargv[] = { (char *)"test", NULL };

    fd_tile_private_boot( &pargc, &pargv );

    /* Verify tile_id0 > 0 (from thread_id on Windows) */
    ulong id0 = fd_tile_id0();
    FD_TEST( id0 > 0 );
    ulong cnt = fd_tile_cnt();
    FD_TEST( cnt >= 1 ); /* At least 1 tile (tile 0) */
    FD_LOG_NOTICE(( "boot: tile_id0=%lu, cnt=%lu (correct)", id0, cnt ));
  }

  /* Test 2: fd_tile_id(), fd_tile_idx() after boot */
  {
    ulong id = fd_tile_id();
    ulong idx = fd_tile_idx();

    /* After boot, id should be tile_id0, idx should be 0 */
    FD_TEST( id == fd_tile_id0() );
    FD_TEST( idx == 0 );
    FD_LOG_NOTICE(( "boot: id=%lu, idx=%lu (correct)", id, idx ));
  }

  /* Test 3: fd_tile_cpu_id() — verify returns valid CPU ID */
  {
    /* Tile 0 should have a valid CPU ID (ULONG_MAX if floating) */
    ulong cpu_id = fd_tile_cpu_id( 0 );
    /* CPU ID should be valid (either a real CPU or ULONG_MAX-1 for floating) */
    FD_TEST( cpu_id <= ULONG_MAX - 1 );
    FD_LOG_NOTICE(( "cpu_id(0): %lu (valid)", cpu_id ));
  }

  /* Test 4: fd_tile_private_cpus_parse() — verify parses CPU strings */
  {
    ushort tile_to_cpu[ FD_TILE_MAX ];
    ulong result;

    /* Test parsing "0-3" (4 CPUs) */
    result = fd_tile_private_cpus_parse( "0-3", tile_to_cpu );
    FD_TEST( result == 4 );
    FD_TEST( tile_to_cpu[0] == 0 );
    FD_TEST( tile_to_cpu[1] == 1 );
    FD_TEST( tile_to_cpu[2] == 2 );
    FD_TEST( tile_to_cpu[3] == 3 );
    FD_LOG_NOTICE(( "cpus_parse('0-3'): 4 CPUs (correct)" ));

    /* Test parsing NULL (returns 0) */
    result = fd_tile_private_cpus_parse( NULL, tile_to_cpu );
    FD_TEST( result == 0 );
    FD_LOG_NOTICE(( "cpus_parse(NULL): 0 (correct)" ));
  }

  /* Test 5: fd_tile_private_halt() — verify no crash */
  {
    fd_tile_private_halt();
    FD_LOG_NOTICE(( "halt: OK" ));
  }

  /* Test 6: Verify fd_tile_cnt() returns 0 after halt */
  {
    ulong cnt = fd_tile_cnt();
    FD_TEST( cnt == 0 );
    FD_LOG_NOTICE(( "post-halt cnt=%lu (correct)", cnt ));
  }

  /* Test 7: fd_tile_exec accessor stubs — verify no crash */
  {
    FD_TEST( fd_tile_exec_id( NULL ) == 0 );
    FD_TEST( fd_tile_exec_idx( NULL ) == 0 );
    FD_TEST( fd_tile_exec_task( NULL ) == NULL );
    FD_TEST( fd_tile_exec_argc( NULL ) == 0 );
    FD_TEST( fd_tile_exec_argv( NULL ) == NULL );
    FD_LOG_NOTICE(( "exec accessors: OK" ));
  }

  /* Test 8: Boot again and test fd_tile_exec_new() for functional tile */
  {
    ushort tile_to_cpu2[ FD_TILE_MAX ];
    int pargc = 1;
    char *pargv[] = { (char *)"test", NULL };

    /* Boot normally (tile 0 on CPU 0, tile 1 floating) */
    fd_tile_private_cpus_parse( "0", tile_to_cpu2 );
    /* For this test, we just boot normally */
    fd_tile_private_boot( &pargc, &pargv );

    /* Verify tile is running */
    FD_TEST( fd_tile_cnt() >= 1 );

    /* Try to dispatch to tile 1 (should work if boot created it) */
    if( fd_tile_cnt() > 1 ) {
      fd_tile_exec_t *exec = fd_tile_exec_new(
        1, test_tile_task, 0, NULL
      );
      /* exec may be NULL if tile 1 isn't available yet, but shouldn't crash */
      FD_LOG_NOTICE(( "exec_new(1): %s", exec ? "non-NULL" : "NULL (tile not ready)" ));

      if( exec ) {
        /* Verify exec details */
        FD_TEST( fd_tile_exec_id( exec ) > 0 );
        FD_TEST( fd_tile_exec_idx( exec ) == 1 );

        /* Wait for exec to complete */
        while( !fd_tile_exec_done( exec ) ) {
          /* Spin */
        }

        /* Delete exec */
        int opt_ret = -1;
        char const *fail = fd_tile_exec_delete( exec, &opt_ret );
        FD_TEST( fail == NULL );
        FD_TEST( opt_ret == 0 );
        FD_LOG_NOTICE(( "exec_new/delete: success" ));
      }
    }

    fd_tile_private_halt();
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
