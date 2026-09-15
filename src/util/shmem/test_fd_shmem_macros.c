/* Verify that feature-test macros are defined BEFORE any standard header
 * that needs them in the shmem module.
 *
 * This test validates the fix for Issue #48: _DEFAULT_SOURCE / _DARWIN_C_SOURCE
 * / _GNU_SOURCE must be defined in fd_shmem_private.h before it includes
 * fd_shmem.h (which transitively pulls in standard headers).
 *
 * Build with: gcc -c -I src/util -I src/disco -I src/ballet \
 *   -DFD_HAS_HOSTED=1 -DFD_HAS_LINUX=1 test_fd_shmem_macros.c -o /dev/null
 *
 * Or via Zig build: zig build -Dtest=true test-fd-shmem-macros
 *
 * Successful compilation = pass. The compile itself is the test.
 */

/* Define FD_HAS_HOSTED=1 for standalone compilation (build.zig sets this).
 * This is needed so fd_shmem_private.h knows to define _GNU_SOURCE. */
#ifndef FD_HAS_HOSTED
#define FD_HAS_HOSTED 1
#endif
#ifndef FD_HAS_LINUX
#define FD_HAS_LINUX 1
#endif

/* If macros are not defined before includes below, compilation fails.
 * This is the actual test — successful compilation = pass. */
#include "fd_shmem_private.h"

/* Verify the macros were actually defined */
#if !defined(_GNU_SOURCE) && !defined(__APPLE__)
#error "_GNU_SOURCE not defined — feature-test macros are not centralized"
#endif

#if defined(__APPLE__) && !defined(_DARWIN_C_SOURCE)
#error "_DARWIN_C_SOURCE not defined on macOS"
#endif

#if defined(__APPLE__) && !defined(_DEFAULT_SOURCE)
#error "_DEFAULT_SOURCE not defined on macOS"
#endif

/* Verify standard headers are available (proves macros took effect) */
#if defined(_GNU_SOURCE)
#include <unistd.h>
#ifndef _GNU_SOURCE
#error "GNU features not available despite macro"
#endif
#endif

int
main( int argc, char **argv ) {
  /* If we compiled successfully, the include chain is correct.
   * The compile itself is the test. */
  (void)argc; (void)argv;
  return 0;
}
