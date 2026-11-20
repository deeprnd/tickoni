/* tk_os_stats_windows.c — per-process OS statistics from GetProcessTimes and
   GetProcessMemoryInfo, the Windows counterpart of Firedancer's /proc reads.
   See tk_os_stats.h for what Windows does and does not report.

   Compile-checked for Windows targets; it has not been run on Windows. */

#define WIN32_LEAN_AND_MEAN
#define PSAPI_VERSION 2     /* GetProcessMemoryInfo from kernel32, no psapi.lib */
#include <windows.h>
#include <psapi.h>
#include <string.h>

#include "tk_os_stats.h"

uint64_t tk_os_stats_size( void ) { return (uint64_t)sizeof(tk_os_stats_t); }

void
tk_os_self_ids( uint64_t * pid, uint64_t * tid ) {
    *pid = (uint64_t)GetCurrentProcessId();
    *tid = (uint64_t)GetCurrentThreadId();
}

/* FILETIME is in 100 ns units. */
static uint64_t
filetime_nanos( FILETIME ft ) {
    return (((uint64_t)ft.dwHighDateTime<<32) | (uint64_t)ft.dwLowDateTime) * 100UL;
}

int
tk_os_probe_open( tk_os_probe_t * probe, uint64_t pid, uint64_t tid ) {
    memset( probe, 0, sizeof(*probe) );
    probe->stat_fd  = -1;
    probe->sched_fd = -1;
    probe->pid = pid;
    probe->tid = tid;

    HANDLE h = OpenProcess( PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid );
    if( !h ) return GetLastError()==ERROR_INVALID_PARAMETER ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;
    probe->os_handle = (uint64_t)(uintptr_t)h;
    return TK_OS_PROBE_OK;
}

int
tk_os_probe_read( tk_os_probe_t * probe, tk_os_stats_t * out ) {
    memset( out, 0, sizeof(*out) );
    HANDLE h = (HANDLE)(uintptr_t)probe->os_handle;
    if( !h ) return TK_OS_PROBE_ERROR;

    DWORD code;
    if( GetExitCodeProcess( h, &code ) && code!=STILL_ACTIVE ) return TK_OS_PROBE_GONE;

    FILETIME created, exited, kernel, user;
    if( !GetProcessTimes( h, &created, &exited, &kernel, &user ) ) return TK_OS_PROBE_ERROR;
    out->user_nanos   = filetime_nanos( user );
    out->system_nanos = filetime_nanos( kernel );

    FILETIME now_ft;
    GetSystemTimeAsFileTime( &now_ft );
    uint64_t now_nanos = filetime_nanos( now_ft );
    uint64_t created_nanos = filetime_nanos( created );
    out->lifetime_nanos = now_nanos>created_nanos ? now_nanos-created_nanos : 0UL;

    PROCESS_MEMORY_COUNTERS pmc;
    if( !GetProcessMemoryInfo( h, &pmc, sizeof(pmc) ) ) return TK_OS_PROBE_ERROR;
    out->resident_bytes = (uint64_t)pmc.WorkingSetSize;
    out->minor_faults   = (uint64_t)pmc.PageFaultCount;   /* not split into major */
    return TK_OS_PROBE_OK;
}

void
tk_os_probe_close( tk_os_probe_t * probe ) {
    if( probe->os_handle ) CloseHandle( (HANDLE)(uintptr_t)probe->os_handle );
    probe->os_handle = 0UL;
}

uint64_t
tk_os_probe_fds( tk_os_probe_t const * probe, int * out, uint64_t cap ) {
    (void)probe; (void)out; (void)cap;
    return 0UL;
}
