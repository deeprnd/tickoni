#ifndef HEADER_tickoni_c_abi_shim_topo_run_platform_common_h
#define HEADER_tickoni_c_abi_shim_topo_run_platform_common_h

/* Shared initialize_logging for all topo_run_platform_*.c files.
 * Each platform file must define these macros before including this header:
 *   TK_PRE_BOOT_THREAD_NAME() — call to set the thread name (or (void)0)
 *   TK_STACK_DIAGNOSTICS      — comment or block about stack diagnostics
 *
 * This eliminates ~33 lines of near-identical code per platform file.
 */

#ifndef TK_PRE_BOOT_THREAD_NAME
#error "TK_PRE_BOOT_THREAD_NAME must be defined by the including platform file"
#endif

#ifndef TK_STACK_DIAGNOSTICS
#error "TK_STACK_DIAGNOSTICS must be defined by the including platform file"
#endif

static void
tk_initialize_logging( char const * tile_name,
                       ulong        tile_kind_id,
                       ulong        tid ) {
  fd_log_cpu_set( NULL );
  fd_log_private_tid_set( tid );
  char thread_name[ 20 ];
  FD_TEST( fd_cstr_printf_check( thread_name, sizeof( thread_name ), NULL, "%s:%lu", tile_name, tile_kind_id ) );
  fd_log_thread_set( thread_name );
  TK_STACK_DIAGNOSTICS;
  FD_LOG_INFO(( "booting tile %s pid:%lu tid:%lu", thread_name, fd_log_group_id(), tid ));

  char wallclock[ FD_LOG_WALLCLOCK_CSTR_BUF_SZ ];
  fd_log_wallclock_cstr( 0L, wallclock );
}

#endif /* HEADER_tickoni_c_abi_shim_topo_run_platform_common_h */
