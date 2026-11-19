/* Test-only linker fixture: tkmodl_run_entry references tk_topo_find_tile_obj,
   but the DURING_FRAG test never runs the tile. An unexpected call must fail. */
#include <stdlib.h>

#include "../../../disco/topo/fd_topo.h"

ulong
tk_topo_find_tile_obj( fd_topo_t const * topo, ulong tile_id, char const * obj_type ) {
    (void)topo; (void)tile_id; (void)obj_type;
    abort();
}

/* tkaudt's unprivileged_init looks up the audit watermark object; the
   DURING_FRAG tests never run init. An unexpected call must fail. */
ulong
tk_topo_audit_watermark_obj( fd_topo_t const * topo ) {
    (void)topo;
    abort();
}
