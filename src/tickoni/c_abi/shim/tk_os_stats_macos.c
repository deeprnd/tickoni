/* tk_os_stats_macos.c — per-process OS statistics from proc_pidinfo, the macOS
   counterpart of Firedancer's /proc reads.  See tk_os_stats.h for what macOS
   does and does not report.

   Compile-checked for macOS targets; it has not been run on macOS. */

#include "tk_os_stats.h"

#include <errno.h>
#include <libproc.h>
#include <pthread.h>
#include <unistd.h>
#include <mach/mach_time.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/time.h>

uint64_t tk_os_stats_size( void ) { return (uint64_t)sizeof(tk_os_stats_t); }

void
tk_os_self_ids( uint64_t * pid, uint64_t * tid ) {
    uint64_t t = 0UL;
    pthread_threadid_np( NULL, &t );
    *pid = (uint64_t)getpid();
    *tid = t;
}

int
tk_os_probe_open( tk_os_probe_t * probe, uint64_t pid, uint64_t tid ) {
    memset( probe, 0, sizeof(*probe) );
    probe->stat_fd  = -1;
    probe->sched_fd = -1;
    probe->pid = pid;
    probe->tid = tid;

    struct proc_taskinfo ti;
    int n = proc_pidinfo( (int)pid, PROC_PIDTASKINFO, 0, &ti, (int)sizeof(ti) );
    if( n==(int)sizeof(ti) ) return TK_OS_PROBE_OK;
    return (n<=0 && (errno==ESRCH || errno==0)) ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;
}

/* pti_total_user and pti_total_system are in mach absolute time units. */
static uint64_t
mach_to_nanos( uint64_t ticks ) {
    mach_timebase_info_data_t tb;
    if( mach_timebase_info( &tb ) || !tb.denom ) return ticks;
    return (uint64_t)(((unsigned __int128)ticks * tb.numer) / tb.denom);
}

int
tk_os_probe_read( tk_os_probe_t * probe, tk_os_stats_t * out ) {
    memset( out, 0, sizeof(*out) );

    struct proc_taskinfo ti;
    int n = proc_pidinfo( (int)probe->pid, PROC_PIDTASKINFO, 0, &ti, (int)sizeof(ti) );
    if( n!=(int)sizeof(ti) ) return (n<=0 && (errno==ESRCH || errno==0)) ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;

    out->user_nanos           = mach_to_nanos( ti.pti_total_user );
    out->system_nanos         = mach_to_nanos( ti.pti_total_system );
    out->major_faults         = (uint64_t)ti.pti_pageins;
    out->minor_faults         = ti.pti_faults>ti.pti_pageins ? (uint64_t)(ti.pti_faults-ti.pti_pageins) : 0UL;
    out->voluntary_switches   = (uint64_t)ti.pti_csw;      /* not split by the kernel */
    out->involuntary_switches = 0UL;
    out->resident_bytes       = (uint64_t)ti.pti_resident_size;

    struct proc_bsdinfo bi;
    if( proc_pidinfo( (int)probe->pid, PROC_PIDTBSDINFO, 0, &bi, (int)sizeof(bi) )==(int)sizeof(bi) ) {
        struct timeval now;
        if( !gettimeofday( &now, NULL ) ) {
            uint64_t now_us   = (uint64_t)now.tv_sec*1000000UL + (uint64_t)now.tv_usec;
            uint64_t start_us = bi.pbi_start_tvsec*1000000UL + bi.pbi_start_tvusec;
            out->lifetime_nanos = now_us>start_us ? (now_us-start_us)*1000UL : 0UL;
        }
    }
    return TK_OS_PROBE_OK;
}

void tk_os_probe_close( tk_os_probe_t * probe ) { (void)probe; }

uint64_t
tk_os_probe_fds( tk_os_probe_t const * probe, int * out, uint64_t cap ) {
    (void)probe; (void)out; (void)cap;
    return 0UL;
}
