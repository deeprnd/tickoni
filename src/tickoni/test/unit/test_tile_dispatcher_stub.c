/* test_tile_dispatcher_stub.c — Minimal stub so tk_policy_stem.c links without
   pulling in the full topob.c dependency chain.

   Only needed because tk_policy_stem.c calls tk_topo_find_tile_obj() inside
   tkpoly_privileged_init and tkpoly_run_entry — but the P6.1 test only reads
   the TK_POLICY_RUN descriptor fields, never calls those init/run functions.
*/

#include <stddef.h>

#include "../../../disco/topo/fd_topo.h"

/* Stub: never actually called by the P6.1 identity test. */
ulong
tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type ) {
    (void)topo;
    (void)tile_id;
    (void)obj_type;
    return 0UL;
}
