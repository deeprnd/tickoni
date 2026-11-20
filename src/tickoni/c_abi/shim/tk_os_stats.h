/* tk_os_stats.h — per-process OS statistics probe used by the tkdiag tile.

   tkdiag publishes, for every tile, the CPU time, page faults, context
   switches and memory of that tile's process into the tile's metrics region
   (the TILE_CPU_DURATION_NANOS_*, TILE_PAGE_FAULT_*, TILE_CONTEXT_SWITCH_* and
   TILE_RESIDENT_BYTES metrics), exactly as Firedancer's diag tile does from
   /proc/<pid>/task/<tid>/stat and .../sched.  Tickoni runs one process per tile,
   so "the tile's process" is the unit on every platform.

   This header has no Firedancer dependency so the three implementations can be
   built and checked on their own:

     tk_os_stats_linux.c    /proc/<pid>/task/<tid>/{stat,sched}, as Firedancer.
                            Descriptors are opened once, before the sandbox, and
                            kept (tk_os_probe_fds lists them for the sandbox).
     tk_os_stats_macos.c    proc_pidinfo(PROC_PIDTASKINFO): CPU, faults, context
                            switches, resident size.  No wait time, no CPU id,
                            and the kernel does not split voluntary from
                            involuntary switches (all are reported voluntary).
     tk_os_stats_windows.c  GetProcessTimes and GetProcessMemoryInfo: CPU and
                            the working set.  Windows reports no wait time,
                            context switches or CPU id (they are 0), and page
                            faults are all reported minor.

   Counters are cumulative since the process started, like the Prometheus
   counters they feed. */
#ifndef __TK_OS_STATS_H__
#define __TK_OS_STATS_H__

#include <stdint.h>

typedef struct {
    uint64_t user_nanos;            /* CPU time in user mode */
    uint64_t system_nanos;          /* CPU time in kernel mode */
    uint64_t wait_nanos;            /* time runnable but not scheduled (Linux only, else 0) */
    uint64_t minor_faults;
    uint64_t major_faults;
    uint64_t voluntary_switches;
    uint64_t involuntary_switches;
    uint64_t resident_bytes;        /* resident set (Windows: working set) */
    uint64_t last_cpu;              /* CPU last executed on (Linux only, else 0) */
    uint64_t lifetime_nanos;        /* time since the process started */
} tk_os_stats_t;

typedef struct {
    int      stat_fd;               /* Linux: /proc/<pid>/task/<tid>/stat, else -1 */
    int      sched_fd;              /* Linux: /proc/<pid>/task/<tid>/sched, else -1 (absent without CONFIG_SCHED_DEBUG) */
    uint64_t pid;
    uint64_t tid;
    uint64_t os_handle;             /* Windows: process HANDLE, else 0 */
} tk_os_probe_t;

enum {
    TK_OS_PROBE_OK    =  0,
    TK_OS_PROBE_GONE  =  1,         /* the process no longer exists */
    TK_OS_PROBE_ERROR = -1          /* it exists but could not be read */
};

/* Binds the probe to a process (and, on Linux, one of its threads).  Returns
   TK_OS_PROBE_OK, TK_OS_PROBE_GONE if the process is already gone, or
   TK_OS_PROBE_ERROR.  Call before sandbox entry. */
int tk_os_probe_open( tk_os_probe_t * probe, uint64_t pid, uint64_t tid );

/* Reads the current statistics.  TK_OS_PROBE_GONE once the process has exited. */
int tk_os_probe_read( tk_os_probe_t * probe, tk_os_stats_t * out );

/* Releases the probe.  Idempotent. */
void tk_os_probe_close( tk_os_probe_t * probe );

/* The open file descriptors the probe needs to keep working after sandbox
   entry.  Writes at most `cap` of them to `out` and returns how many were
   written. */
uint64_t tk_os_probe_fds( tk_os_probe_t const * probe, int * out, uint64_t cap );

/* The calling process's and thread's ids, as tk_os_probe_open takes them (the
   tile's TILE_PID/TILE_TID gauges are not set yet while it initializes). */
void tk_os_self_ids( uint64_t * pid, uint64_t * tid );

/* sizeof(tk_os_stats_t), for tests that restate the layout. */
uint64_t tk_os_stats_size( void );

#endif /* __TK_OS_STATS_H__ */
