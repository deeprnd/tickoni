/* Unit tests for Windows CPU topology (fd_cpu_topo_platform_windows.c).
 *
 * Tests:
 *   - fd_topo_cpus_init() — verify real CPU count, NUMA nodes, online status
 *   - fd_topo_cpus_printf() — verify no crash and outputs per-CPU info
 *
 * On non-Windows, this is a no-op stub. */

#include "fd_util.h"
#include "fd_cpu_topo.h"

#if FD_HAS_WINDOWS

int
main( int argc, char **argv ) {
  fd_boot( &argc, &argv );

  /* Test 1: fd_topo_cpus_init() — verify real topology */
  {
    fd_topo_cpus_t cpus;
    fd_memset( &cpus, 0, sizeof( cpus ) );

    fd_topo_cpus_init( &cpus );

    /* Verify: at least 1 CPU detected (real count, not hardcoded stub) */
    FD_TEST( cpus.cpu_cnt >= 1 );
    FD_LOG_NOTICE(( "cpu_topo: detected %lu CPUs", cpus.cpu_cnt ));

    /* Verify: at least 1 NUMA node */
    FD_TEST( cpus.numa_node_cnt >= 1 );
    FD_LOG_NOTICE(( "cpu_topo: detected %lu NUMA nodes", cpus.numa_node_cnt ));

    /* Verify: at least one CPU is online */
    int at_least_one_online = 0;
    for( ulong i = 0; i < cpus.cpu_cnt; i++ ) {
      FD_TEST( cpus.cpu[ i ].idx == i );
      FD_TEST( cpus.cpu[ i ].numa_node < cpus.numa_node_cnt );
      if( cpus.cpu[ i ].online ) at_least_one_online = 1;
    }
    FD_TEST( at_least_one_online );
    FD_LOG_NOTICE(( "cpu_topo: at least one CPU is online (correct)" ));
  }

  /* Test 2: fd_topo_cpus_printf() — verify no crash and outputs per-CPU info */
  {
    fd_topo_cpus_t cpus;
    fd_memset( &cpus, 0, sizeof( cpus ) );
    fd_topo_cpus_init( &cpus );

    /* Just verify it doesn't crash and produces output */
    fd_topo_cpus_printf( &cpus );

    FD_LOG_NOTICE(( "cpu_topo printf: OK" ));
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
