/* Thin wrappers around Firedancer utility lifecycle primitives. */

#include "../../../util/fd_util.h"

void tk_boot( int * pargc, char *** pargv ) { fd_boot( pargc, pargv ); }
void tk_halt( void ) { fd_halt(); }

/* Yields the calling logical core for one bounded-poll iteration without
   giving up the CPU to the scheduler, per fd_util_base.h FD_SPIN_PAUSE. */
void tk_spin_pause( void ) { FD_SPIN_PAUSE(); }

/* V2.14.S8.T4: Tickoni builds a synthetic argv as a Zig [4][*:0]u8
   stack array, but fd_boot expects char*** — address of a char** variable.
   Zig's @ptrCast between fixed-size and open-ended arrays is unreliable
   for C ABI. This shim takes a char** pointing into the Zig array and
   re-interprets it as char*** the way C expects. */
void tk_boot_with_argv( int argc, char ** argv ) {
  char *** pargv = &argv;
  int *    pargc   = &argc;
  fd_boot( pargc, pargv );
}
