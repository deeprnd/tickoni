/* Thin wrappers around Firedancer utility lifecycle primitives. */

#include "../../../util/fd_util.h"

/* Lightweight boot: version + log + shmem only. Used by the supervisor
   and other bootstrap paths that are not tile processes. */
void tk_boot_lite( int * pargc, char *** pargv ) {
  fd_version_private_boot( pargc, pargv );
  fd_log_private_boot( pargc, pargv );
  fd_shmem_private_boot( pargc, pargv );
}

/* Full boot: version + log + shmem + tile-subsystem initialization. With
   no --tile-cpus, the calling thread becomes tile 0 and no extra pthread is
   created. Used by tile child processes before entering their run loop. */
void tk_boot( int * pargc, char *** pargv ) {
  fd_boot( pargc, pargv );
}

void tk_halt( void ) { fd_halt(); }

/* Yields the calling logical core for one bounded-poll iteration without
   giving up the CPU to the scheduler, per fd_util_base.h FD_SPIN_PAUSE. */
void tk_spin_pause( void ) { FD_SPIN_PAUSE(); }
