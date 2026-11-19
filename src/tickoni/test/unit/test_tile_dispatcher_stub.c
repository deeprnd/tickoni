/* Test-only linker fixture for the P6.1 descriptor identity test.
   tkpoly_run_entry calls tk_topo_find_tile_obj(), and the stem housekeeping
   callback (stk_cnc_liveness, stem_helpers.h) calls tk_monotonic_nanos() and
   tk_cnc_heartbeat(), but this test only reads TK_POLICY_RUN fields. An
   unexpected call must fail the test. */

#include <stdint.h>
#include <stdlib.h>

#include "../../../disco/topo/fd_topo.h"

ulong
tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type ) {
    (void)topo;
    (void)tile_id;
    (void)obj_type;
    abort();
}

int64_t
tk_monotonic_nanos( void ) {
    abort();
}

void
tk_cnc_heartbeat( void * cnc, int64_t now_ns ) {
    (void)cnc;
    (void)now_ns;
    abort();
}
