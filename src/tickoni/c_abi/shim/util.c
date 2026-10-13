/* Thin wrappers around Firedancer utility lifecycle primitives. */

#include "../../../util/fd_util.h"

/* Lightweight boot: version + log + shmem only. Used by the supervisor
   and other bootstrap paths that spawn child tile processes instead of
   running tile threads in-process. Skips fd_tile_private_boot() which
   would create pthreads the supervisor never uses. */
void tk_boot_lite( int * pargc, char *** pargv ) {
  fd_version_private_boot( pargc, pargv );
  fd_log_private_boot( pargc, pargv );
  fd_shmem_private_boot( pargc, pargv );
}

/* Full boot: version + log + shmem + tile threads. Used by tile child
   processes that will run stem_run() and need their own tile thread. */
void tk_boot( int * pargc, char *** pargv ) {
  fd_boot( pargc, pargv );
}

void tk_halt( void ) { fd_halt(); }

/* Yields the calling logical core for one bounded-poll iteration without
   giving up the CPU to the scheduler, per fd_util_base.h FD_SPIN_PAUSE. */
void tk_spin_pause( void ) { FD_SPIN_PAUSE(); }
