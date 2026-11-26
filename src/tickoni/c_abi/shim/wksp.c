/* Thin wrappers around Firedancer workspace primitives. */

/* wksp.c — Linux/macOS shared-memory wrappers.
   Uses POSIX shm_open/mmap on all platforms (no hugetlbfs).
   Windows uses Firedancer stubs that return -ENOTSUP. */

#if FD_HAS_LINUX || FD_HAS_MACOS

#include "util/fd_util.h"
#include "util/wksp/fd_wksp.h"
#include "util/shmem/fd_shmem_private.h"
#include <sys/stat.h>
#include <unistd.h>

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

/* Test fault injection: make `name` impossible to create, so that the next
   tk_wksp_new_named( name, ... ) fails even after the caller's stale-workspace
   cleanup.  A workspace here is a file under the shmem path, so a directory in
   its place cannot be unlinked and the O_EXCL create fails.  The Windows
   implementation below reaches the same outcome by other means.

   shmem_path is the value the process will boot with (--shmem-path).  It is
   passed in, not read from the boot state, so the fault can be set before the
   process boots.  The path layout is fd_shmem_private_path's.  Returns 0 on
   success. */

static char *
tk_wksp_fault_path( char const * shmem_path,
                    char const * name,
                    char *       buf ) {
  return fd_cstr_printf( buf, FD_SHMEM_PRIVATE_PATH_BUF_MAX, NULL, "%s/.%s/%s",
                         shmem_path, fd_shmem_page_sz_to_cstr( FD_SHMEM_NORMAL_PAGE_SZ ), name );
}

int
tk_wksp_fault_block_name( char const * shmem_path,
                          char const * name ) {
  char path[ FD_SHMEM_PRIVATE_PATH_BUF_MAX ];
  return mkdir( tk_wksp_fault_path( shmem_path, name, path ), 0700 );
}

void
tk_wksp_fault_unblock_name( char const * shmem_path,
                            char const * name ) {
  char path[ FD_SHMEM_PRIVATE_PATH_BUF_MAX ];
  rmdir( tk_wksp_fault_path( shmem_path, name, path ) );
}

#elif FD_HAS_WINDOWS

#include "util/shmem/fd_shmem.h"
#include "util/wksp/fd_wksp.h"
#include <errno.h>
#include <string.h>

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
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s page_sz=%lu", name, page_sz ));
  int rc = fd_wksp_new_named( name, page_sz, sub_cnt, sub_page_cnt, sub_cpu_idx, mode, seed, opt_part_max );
  FD_LOG_INFO(( "TK_WKSP_NEW_NAMED: name=%s rc=%d", name, rc ));
  return rc;
}

int tk_wksp_delete_named( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_DELETE_NAMED: name=%s", name ));
  return fd_wksp_delete_named( name );
}

fd_wksp_t * tk_wksp_attach( char const * name ) {
  FD_LOG_INFO(( "TK_WKSP_ATTACH: name=%s", name ));
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

/* Test fault injection: make `name` impossible to create (see the POSIX
   implementation above).  A Windows workspace is a named kernel mapping with
   no file behind it, so there is no path to block.  Instead the name is
   created and joined here: a joined region cannot be unlinked (the unlink is
   deferred until the last detach), so a later cleanup leaves it in place and
   the exclusive create fails with EEXIST.  One name may be blocked at a time.
   Returns 0 on success. */

#define TK_WKSP_FAULT_NAME_MAX (256UL)

static char          tk_wksp_fault_name[ TK_WKSP_FAULT_NAME_MAX ];
static fd_wksp_t *   tk_wksp_fault_wksp = NULL;

int
tk_wksp_fault_block_name( char const * shmem_path,
                          char const * name ) {
  (void)shmem_path; /* no filesystem path on Windows */
  if( tk_wksp_fault_wksp ) return -1;
  if( strlen( name )>=TK_WKSP_FAULT_NAME_MAX ) return -1;
  ulong page_cnt = 256UL;
  ulong cpu_idx  = 0UL;
  if( fd_wksp_new_named( name, FD_SHMEM_NORMAL_PAGE_SZ, 1UL, &page_cnt, &cpu_idx, 0600UL, 1U, 0UL ) ) return -1;
  tk_wksp_fault_wksp = fd_wksp_attach( name );
  if( !tk_wksp_fault_wksp ) {
    fd_wksp_delete_named( name );
    return -1;
  }
  strcpy( tk_wksp_fault_name, name );
  return 0;
}

void
tk_wksp_fault_unblock_name( char const * shmem_path,
                            char const * name ) {
  (void)shmem_path;
  if( !tk_wksp_fault_wksp || strcmp( name, tk_wksp_fault_name ) ) return;
  fd_wksp_detach( tk_wksp_fault_wksp );
  fd_wksp_delete_named( tk_wksp_fault_name );
  tk_wksp_fault_wksp = NULL;
}

#endif /* FD_HAS_LINUX || FD_HAS_MACOS || FD_HAS_WINDOWS */
