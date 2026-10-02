/* Thin wrappers around Firedancer workspace primitives. */

/* wksp.c — Linux/macOS shared-memory wrappers.
   Uses POSIX shm_open/mmap on all platforms (no hugetlbfs).
   Windows uses Firedancer stubs that return -ENOTSUP. */

#if FD_HAS_LINUX || FD_HAS_MACOS

#include "../../../util/fd_util.h"
#include "../../../util/wksp/fd_wksp.h"
#include "../../../util/shmem/fd_shmem_private.h"

extern char fd_shmem_private_base[ FD_SHMEM_PRIVATE_BASE_MAX ];
extern ulong fd_shmem_private_base_len;

int
tk_wksp_new_named( char const *  name,
                   ulong         page_sz,
                   ulong         sub_cnt,
                   ulong const * sub_page_cnt,
                   ulong const * sub_cpu_idx,
                   ulong         mode,
                   uint          seed,
                   ulong         opt_part_max ) {
  char path[ FD_SHMEM_PRIVATE_PATH_BUF_MAX ];
  char *p = fd_shmem_private_path( name, page_sz, path );
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s page_sz=%lu shmem_base=%s resolved_path=%s",
                name, page_sz, fd_shmem_private_base, p ));
  int rc = fd_wksp_new_named( name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max );
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s rc=%d", name, rc ));
  return rc;
}

int tk_wksp_delete_named( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_DELETE_NAMED: name=%s shmem_base=%s", name, fd_shmem_private_base ));
  return fd_wksp_delete_named( name );
}

fd_wksp_t * tk_wksp_attach( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_ATTACH: name=%s shmem_base=%s", name, fd_shmem_private_base ));
  fd_wksp_t * wksp = fd_wksp_attach( name );
  FD_LOG_INFO(( "TK_WKSP_ATTACH: name=%s returned %p", name, (void*)wksp ));
  return wksp;
}
int tk_wksp_detach( fd_wksp_t * wksp ) { return fd_wksp_detach( wksp ); }
ulong tk_wksp_alloc_at_least( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag, ulong * lo, ulong * hi ) { return fd_wksp_alloc_at_least( wksp, alignment, sz, tag, lo, hi ); }
ulong tk_wksp_alloc( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag ) { return fd_wksp_alloc( wksp, alignment, sz, tag ); }
void tk_wksp_free( fd_wksp_t * wksp, ulong gaddr ) { fd_wksp_free( wksp, gaddr ); }
void * tk_wksp_laddr( fd_wksp_t const * wksp, ulong gaddr ) { return fd_wksp_laddr( wksp, gaddr ); }
ulong tk_wksp_gaddr( fd_wksp_t const * wksp, void const * laddr ) { return fd_wksp_gaddr( wksp, laddr ); }
int tk_wksp_exists_named( char const * name ) { return !fd_shmem_info( name, 0UL, NULL ); }

#elif FD_HAS_WINDOWS

#include "fd_shmem.h"
#include "fd_wksp.h"
#include <errno.h>

/* Windows implementation using CreateFileMapping backend.
   Replaces the previous ENOTSUP stubs. */

int
tk_wksp_new_named( char const *  name,
                   ulong         page_sz,
                   ulong         sub_cnt,
                   ulong const * sub_page_cnt,
                   ulong const * sub_cpu_idx,
                   ulong         mode,
                   uint          seed,
                   ulong         opt_part_max ) {
  (void)seed; (void)opt_part_max;
  char path[ FD_SHMEM_PRIVATE_PATH_BUF_MAX ];
  char *p = fd_shmem_private_path( name, page_sz, path );
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s page_sz=%lu shmem_base=%s resolved_path=%s",
                name, page_sz, fd_shmem_private_base, p ));
  int rc = fd_wksp_new_named( name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max );
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s rc=%d", name, rc ));
  return rc;
}

int tk_wksp_delete_named( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_DELETE_NAMED: name=%s shmem_base=%s", name, fd_shmem_private_base ));
  return fd_wksp_delete_named( name );
}

fd_wksp_t * tk_wksp_attach( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_ATTACH: name=%s shmem_base=%s", name, fd_shmem_private_base ));
  fd_wksp_t * wksp = fd_wksp_attach( name );
  FD_LOG_INFO(( "TK_WKSP_ATTACH: name=%s returned %p", name, (void*)wksp ));
  return wksp;
}

int tk_wksp_detach( fd_wksp_t * wksp ) { return fd_wksp_detach( wksp ); }
ulong tk_wksp_alloc_at_least( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag, ulong * lo, ulong * hi ) { return fd_wksp_alloc_at_least( wksp, alignment, sz, tag, lo, hi ); }
ulong tk_wksp_alloc( fd_wksp_t * wksp, ulong alignment, ulong sz, ulong tag ) { return fd_wksp_alloc( wksp, alignment, sz, tag ); }
void tk_wksp_free( fd_wksp_t * wksp, ulong gaddr ) { fd_wksp_free( wksp, gaddr ); }
void * tk_wksp_laddr( fd_wksp_t const * wksp, ulong gaddr ) { return fd_wksp_laddr( wksp, gaddr ); }
ulong tk_wksp_gaddr( fd_wksp_t const * wksp, void const * laddr ) { return fd_wksp_gaddr( wksp, laddr ); }
int tk_wksp_exists_named( char const * name ) { return !fd_shmem_info( name, 0UL, NULL ); }

#endif /* FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS */
