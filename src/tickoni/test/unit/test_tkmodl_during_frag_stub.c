/* Test-only linker fixture: tkmodl_run_entry references tk_topo_find_tile_obj,
   but the DURING_FRAG test never runs the tile. An unexpected call must fail. */
#include <stdlib.h>

#include "../../../disco/topo/fd_topo.h"

ulong
tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type ) {
    (void)topo; (void)tile_id; (void)obj_type;
    abort();
}
