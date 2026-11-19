/* Test-only linker fixture for the P6.1 descriptor identity test.
   tkpoly_run_entry calls tk_topo_find_tile_obj(), but this test only reads
   TK_POLICY_RUN fields. An unexpected call must fail the test. */

#include <stdlib.h>

#include "../../../disco/topo/fd_topo.h"

ulong
tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type ) {
    (void)topo;
    (void)tile_id;
    (void)obj_type;
    abort();
}
