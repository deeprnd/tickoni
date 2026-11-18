/* test_tile_dispatcher.c — P6.1: Dispatcher identity evidence.

   Proves that TK_POLICY_RUN resolves to a real policy tile descriptor on
   every supported build target. Tests three invariants:

   1. TK_POLICY_RUN.name == TILE_ID_TKPOLY (identity)
   2. TK_POLICY_RUN.privileged_init is non-NULL (can initialize)
   3. TK_POLICY_RUN.run is non-NULL (can dispatch)

   Only links tk_policy_stem.c (no topob.c or other shim deps).
*/

#define _GNU_SOURCE

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "../../../disco/topo/fd_topo.h"
#include "audit_schema.h"
#include "../topo_run/tk_policy_stem.h"

int
main( void ) {
    int failed = 0;

    /* Test 1: TK_POLICY_RUN.name must equal TILE_ID_TKPOLY. */
    if( TK_POLICY_RUN.name == NULL ) {
        FD_LOG_ERR(( "P6.1: TK_POLICY_RUN.name is NULL" ));
        failed = 1;
    } else if( strcmp( TK_POLICY_RUN.name, TILE_ID_TKPOLY ) != 0 ) {
        FD_LOG_ERR(( "P6.1: TK_POLICY_RUN.name='%s' != TILE_ID_TKPOLY='%s'",
                      TK_POLICY_RUN.name, TILE_ID_TKPOLY ));
        failed = 1;
    } else {
        FD_LOG_NOTICE(( "P6.1: TK_POLICY_RUN.name='%s' == TILE_ID_TKPOLY='%s' — identity OK",
                         TK_POLICY_RUN.name, TILE_ID_TKPOLY ));
    }

    /* Test 2: TK_POLICY_RUN.privileged_init must be non-NULL. */
    if( TK_POLICY_RUN.privileged_init == NULL ) {
        FD_LOG_ERR(( "P6.1: TK_POLICY_RUN.privileged_init is NULL" ));
        failed = 1;
    } else {
        FD_LOG_NOTICE(( "P6.1: TK_POLICY_RUN.privileged_init=%p — init OK",
                         (void*)TK_POLICY_RUN.privileged_init ));
    }

    /* Test 3: TK_POLICY_RUN.run must be non-NULL. */
    if( TK_POLICY_RUN.run == NULL ) {
        FD_LOG_ERR(( "P6.1: TK_POLICY_RUN.run is NULL" ));
        failed = 1;
    } else {
        FD_LOG_NOTICE(( "P6.1: TK_POLICY_RUN.run=%p — dispatch OK",
                         (void*)TK_POLICY_RUN.run ));
    }

    if( failed ) {
        FD_LOG_ERR(( "P6.1 dispatcher test: FAILED" ));
    } else {
        FD_LOG_NOTICE(( "P6.1 dispatcher test: PASSED" ));
    }

    return failed ? 1 : 0;
}
