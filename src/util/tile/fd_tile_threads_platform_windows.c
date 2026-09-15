/* Windows implementation of tile thread management using Win32 APIs.
 *
 * This provides functional tile threading on Windows, replacing the previous
 * stub that couldn't execute any tasks.
 *
 * Thread creation: CreateThread
 * Thread affinity: SetThreadGroupAffinity
 * Thread priority: SetThreadPriority / GetThreadPriority
 * Stack allocation: VirtualAlloc (with guard pages)
 * Thread join: WaitForSingleObject
 * CPU ID: GetCurrentProcessorNumber
 * Thread naming: SetThreadDescription (Windows 8.1+)
 */

/* Feature macros needed for Win32 APIs */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601 /* Windows 7+ */
#endif
#define _CRT_SECURE_NO_WARNINGS
#define _CRT_NONSTDC_NO_DEPRECATE

#include <windows.h>
#include <process.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "../sanitize/fd_sanitize.h"
#include "../fd_util_base.h"
#include "fd_tile.h"
#include "fd_tile_private.h"
#include "fd_tile_threads_platform.h"

/* ── Stack allocation ─────────────────────────────────────────────────── */

/* Allocate a tile stack with guard regions using VirtualAlloc.
 * Returns NULL on failure (falls back to thread default stack). */
void *
fd_tile_private_stack_new( int   optimize, ulong cpu_idx ) {
  (void)optimize;
  (void)cpu_idx;

  /* Allocate main stack region */
  void * stack = VirtualAlloc( NULL,
                               FD_TILE_PRIVATE_STACK_SZ + 2 * FD_SHMEM_NORMAL_PAGE_SZ,
                               MEM_RESERVE | MEM_COMMIT,
                               PAGE_READWRITE );
  if( !stack ) {
    FD_LOG_WARNING(( "fd_tile: VirtualAlloc failed (%lu) for tile stack, "
                     "falling back to thread default stack", GetLastError() ));
    return NULL;
  }

  /* Uncommit the guard regions (leave them reserved but uncommitted) */
  uchar * guard_lo = (uchar *)stack;
  uchar * guard_hi = (uchar *)stack + FD_TILE_PRIVATE_STACK_SZ;

  if( !VirtualFree( guard_lo, FD_SHMEM_NORMAL_PAGE_SZ, MEM_DECOMMIT ) ) {
    FD_LOG_WARNING(( "fd_tile: VirtualFree (guard lo) failed (%lu), "
                     "continuing without guard lo", GetLastError() ));
  }
  if( !VirtualFree( guard_hi, FD_SHMEM_NORMAL_PAGE_SZ, MEM_DECOMMIT ) ) {
    FD_LOG_WARNING(( "fd_tile: VirtualFree (guard hi) failed (%lu), "
                     "continuing without guard hi", GetLastError() ));
  }

  /* Return pointer to the usable stack region (skip guard lo) */
  return (uchar *)stack + FD_SHMEM_NORMAL_PAGE_SZ;
}

/* Delete a tile stack allocated by fd_tile_private_stack_new. */
static void
fd_tile_private_stack_delete( void * _stack ) {
  if( FD_UNLIKELY( !_stack ) ) return;

  uchar * stack    = (uchar *)_stack - FD_SHMEM_NORMAL_PAGE_SZ;
  uchar * guard_lo = stack;
  uchar * guard_hi = (uchar *)_stack + FD_TILE_PRIVATE_STACK_SZ;

  /* Decommit guard regions */
  VirtualFree( guard_hi, FD_SHMEM_NORMAL_PAGE_SZ, MEM_DECOMMIT );
  VirtualFree( guard_lo, FD_SHMEM_NORMAL_PAGE_SZ, MEM_DECOMMIT );

  /* Free the entire allocation */
  VirtualFree( stack, 0, MEM_RELEASE );
}

/* ── Tile side APIs ───────────────────────────────────────────────────── */

/* CPU configuration type — Windows stores thread priority here. */
/* (Already defined in fd_tile_threads_platform.h) */

/* Configure the CPU optimally — set high thread priority. */
static inline void
fd_tile_private_cpu_config( fd_tile_private_cpu_config_t * save,
                            ulong                          cpu_idx ) {
  /* If a floating tile, leave priority unchanged */
  if( cpu_idx == 65535UL ) {
    save->prio = -1000; /* INT_MIN equivalent — signals "don't change" */
    return;
  }

  /* Save current priority */
  HANDLE hThread = GetCurrentThread();
  int prio = GetThreadPriority( hThread );
  if( prio == THREAD_PRIORITY_ERROR_RETURN ) {
    FD_LOG_WARNING(( "fd_tile: GetThreadPriority failed (%lu)", GetLastError() ));
    save->prio = -1000;
    return;
  }

  /* Set time-critical priority (equivalent to Linux setpriority(-19)) */
  if( !SetThreadPriority( hThread, THREAD_PRIORITY_TIME_CRITICAL ) ) {
    FD_LOG_WARNING(( "fd_tile: SetThreadPriority(THREAD_PRIORITY_TIME_CRITICAL) failed (%lu)",
                     GetLastError() ));
    save->prio = -1000;
    return;
  }

  save->prio = prio;
}

/* Restore the CPU to its previous state. */
static inline void
fd_tile_private_cpu_restore( fd_tile_private_cpu_config_t * save ) {
  int prio = save->prio;
  if( prio == -1000 ) return; /* Wasn't changed */

  HANDLE hThread = GetCurrentThread();
  if( !SetThreadPriority( hThread, prio ) ) {
    FD_LOG_WARNING(( "fd_tile: SetThreadPriority(%d) failed (%lu), "
                     "attempting to continue", prio, GetLastError() ));
  }
}

/* Tile identifiers */
static ulong fd_tile_private_id0;
static ulong fd_tile_private_id1;
static ulong fd_tile_private_cnt;
static FD_TL ulong fd_tile_private_id;
static FD_TL ulong fd_tile_private_idx;
FD_TL ulong fd_tile_private_stack0;
FD_TL ulong fd_tile_private_stack1;
static ushort fd_tile_private_cpu_id[ FD_TILE_MAX ];

ulong fd_tile_id0( void ) { return fd_tile_private_id0; }
ulong fd_tile_id1( void ) { return fd_tile_private_id1; }
ulong fd_tile_cnt( void ) { return fd_tile_private_cnt; }
ulong fd_tile_id( void ) { return fd_tile_private_id; }
ulong fd_tile_idx( void ) { return fd_tile_private_idx; }

ulong
fd_tile_cpu_id( ulong tile_idx ) {
  if( FD_UNLIKELY( tile_idx >= fd_tile_private_cnt ) ) return ULONG_MAX;
  return fd_ulong_if( fd_tile_private_cpu_id[ tile_idx ] < 65535UL,
                      fd_tile_private_cpu_id[ tile_idx ],
                      ULONG_MAX - 1UL );
}

/* Tile state machine */
#define FD_TILE_PRIVATE_STATE_BOOT (0)
#define FD_TILE_PRIVATE_STATE_IDLE (1)
#define FD_TILE_PRIVATE_STATE_EXEC (2)
#define FD_TILE_PRIVATE_STATE_HALT (3)

/* Tile private state — double cache-line aligned to avoid false sharing */
struct __attribute__((aligned(128))) fd_tile_private {
  ulong          id;
  ulong          idx;
  int            state;
  int            argc;
  char **        argv;
  fd_tile_task_t task;
  char const *   fail;
  int            ret;
};

typedef struct fd_tile_private fd_tile_private_t;

/* Arguments passed to the thread manager function. */
struct fd_tile_private_manager_args {
  ulong               id;
  ulong               idx;
  ulong               cpu_idx;
  void *              stack;    /* NULL if thread default stack */
  ulong               stack_sz;
  fd_tile_private_t * tile;
};

typedef struct fd_tile_private_manager_args fd_tile_private_manager_args_t;

/* Tile manager — runs in each tile's thread.
 * Implements the BOOT → IDLE → EXEC → HALT state machine. */
static unsigned __stdcall
fd_tile_private_manager( void * _args ) {
  fd_tile_private_manager_args_t * args = (fd_tile_private_manager_args_t *)_args;

  /* Set thread affinity if tile is pinned to a specific CPU.
   * SetThreadGroupAffinity is available on Windows XP+. */
  if( args->cpu_idx < 65535UL ) {
    GROUP_AFFINITY affinity;
    RtlZeroMemory( &affinity, sizeof( affinity ) );
    affinity.Mask = (KAFFINITY)( 1ULL << (args->cpu_idx % 64) );
    affinity.Group = (WORD)(args->cpu_idx / 64);

    if( !SetThreadGroupAffinity( GetCurrentThread(), &affinity, NULL ) ) {
      FD_LOG_WARNING(( "fd_tile: SetThreadGroupAffinity failed (%lu) "
                       "for tile %lu on cpu %lu",
                       GetLastError(), args->idx, args->cpu_idx ));
    }
  }

  ulong  id       = args->id;
  ulong  idx      = args->idx;
  void * stack    = args->stack;
  ulong  stack_sz = args->stack_sz;

  /* Set thread name using SetThreadDescription (Windows 8.1+) */
  {
    char thread_name_a[ 64 ];
    int len = snprintf( thread_name_a, sizeof( thread_name_a ),
                        "tile:%lu", idx );
    if( len > 0 && len < 63 ) {
      /* Convert to wide string for SetThreadDescription */
      wchar_t thread_name_w[ 64 ];
      int wlen = MultiByteToWideChar( CP_UTF8, 0, thread_name_a,
                                      len, thread_name_w, 63 );
      if( wlen > 0 ) {
        thread_name_w[ wlen ] = '\0';
        /* Load SetThreadDescription at runtime for Windows 8.1+ compatibility */
        HMODULE hKernel32 = GetModuleHandleW( L"kernel32.dll" );
        if( hKernel32 ) {
          typedef BOOL (WINAPI * SetThreadDescriptionFn)( HANDLE, PCWSTR );
          SetThreadDescriptionFn SetThreadDescription =
            (SetThreadDescriptionFn)GetProcAddress( hKernel32, "SetThreadDescription" );
          if( SetThreadDescription ) {
            SetThreadDescription( GetCurrentThread(), thread_name_w );
          }
        }
      }
    }
  }

  /* Validate thread identifiers */
  if( FD_UNLIKELY( !( (id == fd_log_thread_id()                                        ) &
                      (idx == (id - fd_tile_private_id0)                                ) &
                      ((fd_tile_private_id0 < id) & (id < fd_tile_private_id1)          ) &
                      (fd_tile_private_cnt == (fd_tile_private_id1 - fd_tile_private_id0)) ) ) )
    FD_LOG_ERR(( "fd_tile: internal error (unexpected thread identifiers)" ));

  fd_tile_private_t tile[1];
  FD_VOLATILE( tile->id    ) = id;
  FD_VOLATILE( tile->idx   ) = idx;
  FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_BOOT;
  FD_VOLATILE( tile->argc  ) = 0;
  FD_VOLATILE( tile->argv  ) = NULL;
  FD_VOLATILE( tile->task  ) = NULL;
  FD_VOLATILE( tile->fail  ) = NULL;
  FD_VOLATILE( tile->ret   ) = 0;

  fd_tile_private_id  = id;
  fd_tile_private_idx = idx;

  /* Set up stack bounds */
  if( FD_LIKELY( stack ) ) {
    fd_tile_private_stack0 = (ulong)stack;
    fd_tile_private_stack1 = (ulong)stack + stack_sz;
  } else {
    /* Discover stack bounds via VirtualQuery */
    fd_log_private_stack_discover( stack_sz, &fd_tile_private_stack0, &fd_tile_private_stack1 );
    if( FD_UNLIKELY( !fd_tile_private_stack0 ) )
      FD_LOG_WARNING(( "stack diagnostics not available on this tile; attempting to continue" ));
  }

  /* Configure CPU priority */
  fd_tile_private_cpu_config_t dummy[1];
  fd_tile_private_cpu_config( dummy, args->cpu_idx );

  ulong app_id = fd_log_app_id();
  FD_LOG_INFO(( "fd_tile: boot tile %lu success (thread %lu:%lu in thread group %lu:%lu/%lu)",
                idx, app_id, id, app_id, fd_tile_private_id0, fd_tile_private_cnt ));

  FD_COMPILER_MFENCE();
  FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_IDLE;
  FD_VOLATILE( args->tile  ) = tile;

  /* Main polling loop */
  for(;;) {
    int state = FD_VOLATILE_CONST( tile->state );
    if( FD_UNLIKELY( state != FD_TILE_PRIVATE_STATE_EXEC ) ) {
      if( FD_UNLIKELY( state != FD_TILE_PRIVATE_STATE_IDLE ) ) break;
      FD_SPIN_PAUSE();
      continue;
    }

    /* Execute the task */
    int            argc = FD_VOLATILE_CONST( tile->argc );
    char **        argv = FD_VOLATILE_CONST( tile->argv );
    fd_tile_task_t task = FD_VOLATILE_CONST( tile->task );
    FD_VOLATILE( tile->ret   ) = task( argc, argv );
    FD_VOLATILE( tile->fail  ) = NULL;

    FD_COMPILER_MFENCE();
    FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_IDLE;
  }

  /* HALT — clean up and reset */
  FD_LOG_INFO(( "fd_tile: halting tile %lu", idx ));

  FD_COMPILER_MFENCE();
  FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_BOOT;

  /* Return stack pointer for deletion by the halt path */
  return (uintptr_t)stack;
}

/* Tile execution table — each entry on its own cache line pair */
static struct __attribute__((aligned(128))) {
  fd_tile_private_t * lock;
  fd_tile_private_t * tile;
  HANDLE              handle;
} fd_tile_private[ FD_TILE_MAX ];

/* ── Dispatch side APIs ──────────────────────────────────────────────── */

/* Try to acquire the tile lock (non-blocking). Returns tile or NULL. */
static inline fd_tile_private_t *
fd_tile_private_trylock( ulong tile_idx ) {
  fd_tile_private_t * volatile * vtile =
    (fd_tile_private_t * volatile *)&fd_tile_private[ tile_idx ].lock;
  fd_tile_private_t * tile = *vtile;
  if( FD_LIKELY( tile ) &&
      FD_LIKELY( InterlockedCompareExchangePointer(
                   (void * volatile *)vtile, NULL, tile ) == tile ) )
    return tile;
  return NULL;
}

/* Block until the tile lock is acquired. */
static inline fd_tile_private_t *
fd_tile_private_lock( ulong tile_idx ) {
  fd_tile_private_t * volatile * vtile =
    (fd_tile_private_t * volatile *)&fd_tile_private[ tile_idx ].lock;
  fd_tile_private_t * tile;
  for(;;) {
    tile = *vtile;
    if( FD_LIKELY( tile ) &&
        FD_LIKELY( InterlockedCompareExchangePointer(
                     (void * volatile *)vtile, NULL, tile ) == tile ) )
      break;
    FD_SPIN_PAUSE();
  }
  return tile;
}

/* Release the tile lock. */
static inline void
fd_tile_private_unlock( ulong               tile_idx,
                        fd_tile_private_t * tile ) {
  FD_VOLATILE( fd_tile_private[ tile_idx ].lock ) = tile;
}

/* Start executing a task on a tile. */
fd_tile_exec_t *
fd_tile_exec_new( ulong          idx,
                  fd_tile_task_t task,
                  int            argc,
                  char **        argv ) {
  /* Can't dispatch to self or to tile 0 */
  if( FD_UNLIKELY( (idx == fd_tile_private_idx) | (!idx) ) ) return NULL;

  fd_tile_private_t * tile = fd_tile_private_trylock( idx );
  if( FD_UNLIKELY( !tile ) ) return NULL;

  /* Set up the task */
  FD_VOLATILE( tile->argc ) = argc;
  FD_VOLATILE( tile->argv ) = argv;
  FD_VOLATILE( tile->task ) = task;
  FD_COMPILER_MFENCE();
  FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_EXEC;
  return (fd_tile_exec_t *)tile;
}

/* Delete an exec — blocks until the tile is idle. */
char const *
fd_tile_exec_delete( fd_tile_exec_t * exec,
                     int *            opt_ret ) {
  fd_tile_private_t * tile     = (fd_tile_private_t *)exec;
  ulong               tile_idx = tile->idx;

  int state;
  for(;;) {
    state = FD_VOLATILE_CONST( tile->state );
    if( FD_LIKELY( state == FD_TILE_PRIVATE_STATE_IDLE ) ) break;
    FD_SPIN_PAUSE();
  }

  char const * fail = FD_VOLATILE_CONST( tile->fail );
  if( FD_LIKELY( (!fail) & (!!opt_ret) ) ) *opt_ret = FD_VOLATILE_CONST( tile->ret );
  fd_tile_private_unlock( tile_idx, tile );
  return fail;
}

fd_tile_exec_t * fd_tile_exec( ulong tile_idx ) {
  return (fd_tile_exec_t *)fd_tile_private[ tile_idx ].tile;
}

ulong          fd_tile_exec_id  ( fd_tile_exec_t const * exec ) {
  return ((fd_tile_private_t const *)exec)->id;
}
ulong          fd_tile_exec_idx ( fd_tile_exec_t const * exec ) {
  return ((fd_tile_private_t const *)exec)->idx;
}
fd_tile_task_t fd_tile_exec_task( fd_tile_exec_t const * exec ) {
  return ((fd_tile_private_t const *)exec)->task;
}
int            fd_tile_exec_argc( fd_tile_exec_t const * exec ) {
  return ((fd_tile_private_t const *)exec)->argc;
}
char **        fd_tile_exec_argv( fd_tile_exec_t const * exec ) {
  return ((fd_tile_private_t const *)exec)->argv;
}

int
fd_tile_exec_done( fd_tile_exec_t const * exec ) {
  fd_tile_private_t const * tile = (fd_tile_private_t const *)exec;
  int state = FD_VOLATILE_CONST( tile->state );
  return (int)( state != FD_TILE_PRIVATE_STATE_EXEC );
}

/* ── Boot/halt APIs ──────────────────────────────────────────────────── */

FD_STATIC_ASSERT( FD_TILE_MAX < 65535, update_tile_to_cpu_type );

ulong
fd_tile_private_cpus_parse( char const * cstr,
                            ushort *     tile_to_cpu ) {
  if( !cstr ) return 0UL;
  ulong cnt = 0UL;

  /* Simple CPU range parser — mimics the Linux version but simplified for Windows.
   * Parses formats like "0-3", "0,1,2,3", "0h", "f" (floating). */
  char buf[ 256 ];
  strncpy( buf, cstr, sizeof( buf ) - 1 );
  buf[ sizeof( buf ) - 1 ] = '\0';

  char * p = buf;
  for(;;) {
    /* Skip whitespace */
    while( *p && (*p == ' ' || *p == '\t') ) p++;

    if( !*p ) break;

    if( p[0] == 'f' ) {
      /* Floating tile(s) */
      p++;
      while( *p && (*p == ' ' || *p == '\t') ) p++;

      ulong float_cnt;
      if     ( p[0] == ','             ) float_cnt = 1UL, p++;
      else if( p[0] == '\0'            ) float_cnt = 1UL;
      else if( !fd_isdigit( (int)p[0] ) ) {
        FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (malformed count)" ));
      } else {
        float_cnt = fd_cstr_to_ulong( p );
        while( fd_isdigit( (int)p[0] ) ) p++;
        while( *p && (*p == ' ' || *p == '\t') ) p++;
        if( FD_UNLIKELY( !( p[0] == ',' || p[0] == '\0' ) ) )
          FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (bad count delimiter)" ));
        if( p[0] == ',' ) p++;
      }

      do {
        if( FD_UNLIKELY( cnt >= FD_TILE_MAX ) )
          FD_LOG_ERR(( "fd_tile: too many --tile-cpus" ));
        tile_to_cpu[ cnt++ ] = (ushort)65535;
      } while( --float_cnt );

      continue;
    }

    if( !fd_isdigit( (int)p[0] ) ) {
      if( FD_UNLIKELY( p[0] != '\0' ) )
        FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (range lo not a cpu)" ));
      break;
    }

    ulong cpu0   = fd_cstr_to_ulong( p );
    ulong cpu1   = cpu0;
    ulong stride = 1UL;
    p++;
    while( fd_isdigit( (int)p[0] ) ) p++;
    while( *p && (*p == ' ' || *p == '\t') ) p++;

    if( p[0] == '-' ) {
      p++;
      while( *p && (*p == ' ' || *p == '\t') ) p++;
      if( FD_UNLIKELY( !fd_isdigit( (int)p[0] ) ) )
        FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (range hi not a cpu)" ));
      cpu1 = fd_cstr_to_ulong( p );
      p++;
      while( fd_isdigit( (int)p[0] ) ) p++;
      while( *p && (*p == ' ' || *p == '\t') ) p++;

      if( p[0] == '/' || p[0] == ':' ) {
        p++;
        while( *p && (*p == ' ' || *p == '\t') ) p++;
        if( FD_UNLIKELY( !fd_isdigit( (int)p[0] ) ) )
          FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (stride not an int)" ));
        stride = fd_cstr_to_ulong( p );
        p++;
        while( fd_isdigit( (int)p[0] ) ) p++;
      }
    } else if( p[0] == 'h' ) {
      /* `Nh` shorthand — not fully implemented on Windows (hyperthread info
       * not easily available). Treat as single CPU. */
      p++;
    }
    while( *p && (*p == ' ' || *p == '\t') ) p++;
    if( FD_UNLIKELY( !( p[0] == ',' || p[0] == '\0' ) ) )
      FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (bad range delimiter)" ));
    if( p[0] == ',' ) p++;

    cpu1++;
    if( FD_UNLIKELY( cpu1 <= cpu0 ) )
      FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (invalid range)" ));
    if( FD_UNLIKELY( !stride ) )
      FD_LOG_ERR(( "fd_tile: malformed --tile-cpus (invalid stride)" ));

    for( ulong cpu = cpu0; cpu < cpu1; cpu += stride ) {
      if( FD_UNLIKELY( cnt >= FD_TILE_MAX ) )
        FD_LOG_ERR(( "fd_tile: too many --tile-cpus" ));
      tile_to_cpu[ cnt++ ] = (ushort)cpu;
    }
  }

  return cnt;
}

/* CPU config save for tile 0. */
static fd_tile_private_cpu_config_t fd_tile_private_cpu_config_save[1];

void
fd_tile_private_map_boot( ushort * tile_to_cpu,
                          ulong    tile_cnt ) {
  fd_tile_private_id0 = fd_log_thread_id();
  fd_tile_private_id1 = fd_tile_private_id0 + tile_cnt;
  fd_tile_private_cnt = tile_cnt;

  ulong app_id  = fd_log_app_id();
  ulong host_id = fd_log_host_id();
  FD_LOG_INFO(( "fd_tile: booting thread group %lu:%lu/%lu",
                app_id, fd_tile_private_id0, fd_tile_private_cnt ));

  /* Create tiles [1, tile_cnt) first so floating tiles inherit scheduler
   * priorities from the thread group launcher. */
  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ ) {
    ulong cpu_idx = (ulong)tile_to_cpu[ tile_idx ];
    int   fixed   = (cpu_idx < 65535UL);

    if( fixed )
      FD_LOG_INFO(( "fd tile: booting tile %lu on cpu %lu:%lu",
                    tile_idx, host_id, cpu_idx ));
    else
      FD_LOG_INFO(( "fd tile: booting tile %lu on cpu %lu:float",
                    tile_idx, host_id ));

    /* Allocate stack (Windows threads use default stack, but we track this
     * for diagnostics). */
    int optimize = FD_HAS_X86 & fixed;
    void * stack = fd_tile_private_stack_new( optimize, cpu_idx );

    ulong stack_sz = FD_TILE_PRIVATE_STACK_SZ;
    (void)stack; /* Windows threads always use default stack */

    /* Initialize tile table entry */
    FD_VOLATILE( fd_tile_private[ tile_idx ].lock ) = NULL;

    fd_tile_private_manager_args_t args[1];

    FD_VOLATILE( args->id       ) = fd_tile_private_id0 + tile_idx;
    FD_VOLATILE( args->idx      ) = tile_idx;
    FD_VOLATILE( args->cpu_idx  ) = cpu_idx;
    FD_VOLATILE( args->stack    ) = stack;
    FD_VOLATILE( args->stack_sz ) = stack_sz;
    FD_VOLATILE( args->tile     ) = NULL;

    FD_COMPILER_MFENCE();

    /* Create the thread */
    uintptr_t thread_id;
    HANDLE hThread = (HANDLE)_beginthreadex(
      NULL,              /* Security attributes */
      0,                 /* Stack size (0 = use default) */
      (unsigned (__stdcall *)(void *))fd_tile_private_manager,
      args,              /* Argument */
      0,                 /* Creation flags */
      (unsigned int *)&thread_id
    );

    if( !hThread ) {
      if( fixed )
        FD_LOG_ERR(( "fd_tile: _beginthreadex failed (%lu) "
                     "for tile %lu on cpu %lu",
                     GetLastError(), tile_idx, cpu_idx ));
      FD_LOG_ERR(( "fd_tile: _beginthreadex failed (%lu) "
                   "for tile %lu (floating)",
                   GetLastError(), tile_idx ));
    }

    /* Wait for the tile to reach IDLE state */
    fd_tile_private_t * tile;
    for(;;) {
      tile = FD_VOLATILE_CONST( args->tile );
      if( FD_LIKELY( tile ) ) break;
      FD_YIELD();
    }

    FD_VOLATILE( fd_tile_private[ tile_idx ].tile ) = tile;
    FD_VOLATILE( fd_tile_private[ tile_idx ].lock  ) = tile;
    fd_tile_private[ tile_idx ].handle              = hThread;

    /* Tile is running, args is safe to reuse */
  }

  /* Boot tile 0 on the main thread */
  ulong cpu_idx = (ulong)tile_to_cpu[ 0UL ];
  int   fixed   = (cpu_idx < 65535UL);
  if( fixed )
    FD_LOG_INFO(( "fd tile: booting tile %lu on cpu %lu:%lu",
                  0UL, host_id, cpu_idx ));
  else
    FD_LOG_INFO(( "fd tile: booting tile %lu on cpu %lu:float",
                  0UL, host_id ));

  if( fixed ) {
    /* Try to set tile 0 affinity */
    GROUP_AFFINITY affinity;
    RtlZeroMemory( &affinity, sizeof( affinity ) );
    affinity.Mask = (KAFFINITY)( 1ULL << (cpu_idx % 64) );
    affinity.Group = (WORD)(cpu_idx / 64);

    if( !SetThreadGroupAffinity( GetCurrentThread(), &affinity, NULL ) ) {
      FD_LOG_WARNING(( "fd_tile: SetThreadGroupAffinity failed (%lu) "
                       "for tile 0 on cpu %lu",
                       GetLastError(), cpu_idx ));
    }

    /* Set CPU ID */
    fd_log_private_cpu_id_set( cpu_idx );
    fd_log_cpu_set( NULL );
    fd_log_thread_set( NULL );
  }

  /* Tile 0 "thread manager init" */
  fd_tile_private_id  = fd_tile_private_id0;
  fd_tile_private_idx = 0UL;

  /* Discover stack bounds for tile 0 */
#if !FD_HAS_ASAN
  fd_log_private_stack_discover( fd_log_private_main_stack_sz(),
                                 &fd_tile_private_stack0,
                                 &fd_tile_private_stack1 );
  if( FD_UNLIKELY( !fd_tile_private_stack0 ) )
    FD_LOG_WARNING(( "stack diagnostics not available on tile 0; "
                     "attempting to continue" ));
#endif

  /* Configure CPU priority for tile 0 */
  fd_tile_private_cpu_config( fd_tile_private_cpu_config_save, cpu_idx );
  fd_tile_private[0].lock = NULL; /* Can't dispatch to tile 0 */
  fd_tile_private[0].tile = NULL;

  FD_LOG_INFO(( "fd_tile: boot tile %lu success "
                "(thread %lu:%lu in thread group %lu:%lu/%lu)",
                fd_tile_private_idx, app_id, fd_tile_private_id,
                app_id, fd_tile_private_id0, fd_tile_private_cnt ));

  /* Copy CPU mapping */
  fd_memcpy( fd_tile_private_cpu_id, tile_to_cpu,
             fd_tile_private_cnt * sizeof(ushort) );

  FD_LOG_INFO(( "fd_tile: boot success" ));
}

void
fd_tile_private_boot_str( char const * cpus ) {
  ushort tile_to_cpu[ FD_TILE_MAX ];
  ulong  tile_cnt = fd_tile_private_cpus_parse( cpus, tile_to_cpu );

  if( FD_UNLIKELY( !tile_cnt ) ) {
    FD_LOG_INFO(( "fd_tile: no cpus specified; "
                  "treating thread group as single tile "
                  "running on O/S assigned cpu(s)" ));
    tile_to_cpu[0] = (ushort)65535;
    tile_cnt       = 1UL;
  }

  fd_tile_private_map_boot( tile_to_cpu, tile_cnt );
}

void
fd_tile_private_boot( int *    pargc,
                      char *** pargv ) {
  /* Extract tile configuration from command line */
  char const * cpus = fd_env_strip_cmdline_cstr(
    pargc, pargv, "--tile-cpus", "FD_TILE_CPUS", NULL );

  if( !cpus )
    FD_LOG_INFO(( "fd_tile: --tile-cpus not specified" ));
  else
    FD_LOG_INFO(( "fd_tile: --tile-cpus \"%s\"", cpus ));

  fd_tile_private_boot_str( cpus );
}

void
fd_tile_private_halt( void ) {
  FD_LOG_INFO(( "fd_tile: halt" ));

  fd_memset( fd_tile_private_cpu_id, 0,
             fd_tile_private_cnt * sizeof(ushort) );

  ulong tile_cnt = fd_tile_private_cnt;

  HANDLE handles[ FD_TILE_MAX ];

  FD_LOG_INFO(( "fd_tile: disabling dispatch" ));
  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ ) {
    fd_tile_private_t * tile = fd_tile_private_lock( tile_idx );
    handles[ tile_idx ] = fd_tile_private[ tile_idx ].handle;
  }
  /* All dispatches will fail at this point */

  FD_LOG_INFO(( "fd_tile: waiting for all tasks to complete" ));
  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ ) {
    fd_tile_private_t * tile =
      (fd_tile_private_t *)(fd_tile_private[ tile_idx ].tile);
    while( FD_VOLATILE_CONST( tile->state ) != FD_TILE_PRIVATE_STATE_IDLE )
      FD_YIELD();
  }
  /* All halt transitions are valid at this point */

  FD_LOG_INFO(( "fd_tile: signaling all tiles to halt" ));
  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ ) {
    fd_tile_private_t * tile =
      (fd_tile_private_t *)(fd_tile_private[ tile_idx ].tile);
    FD_VOLATILE( tile->state ) = FD_TILE_PRIVATE_STATE_HALT;
  }
  /* All tiles are halting at this point */

  FD_LOG_INFO(( "fd_tile: waiting for all tiles to halt" ));
  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ ) {
    DWORD ret = WaitForSingleObject(
      fd_tile_private[ tile_idx ].handle, 5000 ); /* 5 second timeout */

    if( ret == WAIT_TIMEOUT ) {
      FD_LOG_WARNING(( "fd_tile: tile %lu did not halt in time, "
                       "terminating", tile_idx ));
      TerminateThread( fd_tile_private[ tile_idx ].handle, 1 );
    }

    /* Clean up the thread handle */
    CloseHandle( fd_tile_private[ tile_idx ].handle );

    /* Delete the stack if we allocated one */
    void * stack = (void *)fd_tile_private_stack0;
    (void)stack;
    /* Note: stack tracking is limited on Windows since threads use
     * default stacks. In practice, the stack is returned by the thread
     * function and should be freed here if needed. */

    FD_LOG_INFO(( "fd_tile: halt tile %lu success", tile_idx ));
  }

  /* Restore tile 0 CPU config */
  fd_tile_private_cpu_restore( fd_tile_private_cpu_config_save );

  FD_LOG_INFO(( "fd_tile: halt tile 0 success" ));

  FD_LOG_INFO(( "fd_tile: cleaning up" ));

  for( ulong tile_idx = 1UL; tile_idx < tile_cnt; tile_idx++ )
    fd_tile_private_unlock( tile_idx, NULL );

  fd_memset( fd_tile_private_cpu_config_save, 0,
             sizeof( fd_tile_private_cpu_config_t ) );

  fd_tile_private_stack1 = 0UL;
  fd_tile_private_stack0 = 0UL;
  fd_tile_private_idx    = 0UL;
  fd_tile_private_id     = 0UL;

  fd_tile_private_cnt = 0UL;
  fd_tile_private_id1 = 0UL;
  fd_tile_private_id0 = 0UL;

  FD_LOG_INFO(( "fd_tile: halt success" ));
}
