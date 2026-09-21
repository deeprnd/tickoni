/* Thin wrappers around Firedancer workspace primitives. */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include "../../../util/fd_util.h"
#include "../../../util/wksp/fd_wksp.h"

int
tk_wksp_new_named( char const *  name,
                   ulong         page_sz,
                   ulong         sub_cnt,
                   ulong const * sub_page_cnt,
                   ulong const * sub_cpu_idx,
                   ulong         mode,
                   uint          seed,
                   ulong         opt_part_max ) {
  return fd_wksp_new_named( name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max );
}

int tk_wksp_delete_named( char const * name ) { return fd_wksp_delete_named( name ); }
fd_wksp_t * tk_wksp_attach( char const * name ) { return fd_wksp_attach( name ); }
int tk_wksp_detach( fd_wksp_t * wksp ) { return fd_wksp_detach( wksp ); }
ulong tk_wksp_alloc_at_least( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag, ulong * lo, ulong * hi ) { return fd_wksp_alloc_at_least( wksp, alignment, sz, tag, lo, hi ); }
ulong tk_wksp_alloc( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag ) { return fd_wksp_alloc( wksp, alignment, sz, tag ); }
void tk_wksp_free( fd_wksp_t * wksp, ulong gaddr ) { fd_wksp_free( wksp, gaddr ); }
void * tk_wksp_laddr( fd_wksp_t const * wksp, ulong gaddr ) { return fd_wksp_laddr( wksp, gaddr ); }
ulong tk_wksp_gaddr( fd_wksp_t const * wksp, void const * laddr ) { return fd_wksp_gaddr( wksp, laddr ); }
int tk_wksp_exists_named( char const * name ) { return !fd_shmem_info( name, 0UL, NULL ); }
