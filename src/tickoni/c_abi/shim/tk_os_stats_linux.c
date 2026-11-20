/* tk_os_stats_linux.c — per-process OS statistics from /proc, following
   Firedancer's diag tile (src/disco/diag/fd_diag_tile.c: read_stat_file,
   read_sched_file, read_starttime).  See tk_os_stats.h. */

#define _GNU_SOURCE

#include "tk_os_stats.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

uint64_t tk_os_stats_size( void ) { return (uint64_t)sizeof(tk_os_stats_t); }

void
tk_os_self_ids( uint64_t * pid, uint64_t * tid ) {
    *pid = (uint64_t)getpid();
    *tid = (uint64_t)syscall( SYS_gettid );
}

/* Reads a whole /proc file through a kept-open descriptor.  Returns the number
   of bytes read, or -1 with *gone set if the task has exited (ESRCH) and -1
   with *gone clear on any other failure. */
static long
read_all( int fd, char * buf, size_t cap, int * gone ) {
    *gone = 0;
    if( lseek( fd, 0, SEEK_SET )==(off_t)-1 ) return -1L;
    size_t len = 0UL;
    for(;;) {
        if( len+1UL>=cap ) return -1L;                 /* leave room for the NUL */
        ssize_t n = read( fd, buf+len, cap-1UL-len );
        if( n<0 ) {
            if( errno==EINTR ) continue;
            if( errno==ESRCH ) *gone = 1;
            return -1L;
        }
        if( n==0 ) break;
        len += (size_t)n;
    }
    buf[len] = '\0';
    return (long)len;
}

static int
parse_ulong( char const * s, uint64_t * out ) {
    if( !s || !*s ) return -1;
    char * end;
    errno = 0;
    unsigned long long v = strtoull( s, &end, 10 );
    if( errno || end==s || *end!='\0' ) return -1;
    *out = (uint64_t)v;
    return 0;
}

/* Fields of /proc/<pid>/task/<tid>/stat, counted from 1 as in proc(5).  The
   command name (field 2) is in parentheses and may contain spaces, so parsing
   starts after the last ')'; token 0 there is field 3 (state). */
#define STAT_FIRST_FIELD 3
#define FIELD_MINFLT     10
#define FIELD_MAJFLT     12
#define FIELD_UTIME      14
#define FIELD_STIME      15
#define FIELD_STARTTIME  22
#define FIELD_RSS        24
#define FIELD_PROCESSOR  39

static int
parse_stat( char * contents, tk_os_stats_t * out ) {
    char * close = strrchr( contents, ')' );
    if( !close ) return -1;

    long clk_tck = sysconf( _SC_CLK_TCK );
    long page_sz = sysconf( _SC_PAGESIZE );
    if( clk_tck<=0 || page_sz<=0 ) return -1;
    uint64_t ns_per_tick = 1000000000UL / (uint64_t)clk_tck;

    uint64_t minflt = 0, majflt = 0, utime = 0, stime = 0, starttime = 0, rss_pages = 0, processor = 0;
    int got = 0;

    char * saveptr;
    char * token = strtok_r( close+1, " ", &saveptr );
    for( int field=STAT_FIRST_FIELD; token && field<=FIELD_PROCESSOR; field++, token = strtok_r( NULL, " ", &saveptr ) ) {
        uint64_t * dst = NULL;
        switch( field ) {
            case FIELD_MINFLT:    dst = &minflt;    break;
            case FIELD_MAJFLT:    dst = &majflt;    break;
            case FIELD_UTIME:     dst = &utime;     break;
            case FIELD_STIME:     dst = &stime;     break;
            case FIELD_STARTTIME: dst = &starttime; break;
            case FIELD_RSS:       dst = &rss_pages; break;
            case FIELD_PROCESSOR: dst = &processor; break;
            default: break;
        }
        if( !dst ) continue;
        if( parse_ulong( token, dst ) ) return -1;
        got++;
    }
    if( got!=7 ) return -1;

    out->minor_faults   = minflt;
    out->major_faults   = majflt;
    out->user_nanos     = utime*ns_per_tick;
    out->system_nanos   = stime*ns_per_tick;
    out->resident_bytes = rss_pages*(uint64_t)page_sz;
    out->last_cpu       = processor;

    struct timespec boot;
    if( clock_gettime( CLOCK_BOOTTIME, &boot ) ) return -1;
    uint64_t now_nanos   = (uint64_t)boot.tv_sec*1000000000UL + (uint64_t)boot.tv_nsec;
    uint64_t start_nanos = starttime*ns_per_tick;
    out->lifetime_nanos  = now_nanos>start_nanos ? now_nanos-start_nanos : 0UL;
    return 0;
}

/* /proc/<pid>/task/<tid>/sched: "wait_sum" (seconds.microseconds, only with
   CONFIG_SCHEDSTATS), "nr_voluntary_switches", "nr_involuntary_switches". */
static void
parse_sched( char * contents, tk_os_stats_t * out ) {
    char * line = contents;
    while( line && *line ) {
        char * next = strchr( line, '\n' );
        if( next ) *next = '\0';

        char * colon = strchr( line, ':' );
        if( colon ) {
            char * value = colon+1;
            while( *value==' ' || *value=='\t' ) value++;
            if( !strncmp( line, "wait_sum", 8UL ) ) {
                char * endptr;
                errno = 0;
                unsigned long long seconds = strtoull( value, &endptr, 10 );
                if( !errno && *endptr=='.' ) {
                    unsigned long long micros = strtoull( endptr+1, &endptr, 10 );
                    if( !errno && *endptr=='\0' )
                        out->wait_nanos = (uint64_t)seconds*1000000000UL + (uint64_t)micros*1000UL;
                }
            } else if( !strncmp( line, "nr_voluntary_switches", 21UL ) ) {
                uint64_t v;
                if( !parse_ulong( value, &v ) ) out->voluntary_switches = v;
            } else if( !strncmp( line, "nr_involuntary_switches", 23UL ) ) {
                uint64_t v;
                if( !parse_ulong( value, &v ) ) out->involuntary_switches = v;
            }
        }
        line = next ? next+1 : NULL;
    }
}

int
tk_os_probe_open( tk_os_probe_t * probe, uint64_t pid, uint64_t tid ) {
    memset( probe, 0, sizeof(*probe) );
    probe->stat_fd  = -1;
    probe->sched_fd = -1;
    probe->pid = pid;
    probe->tid = tid;

    char path[ 96 ];
    int n = snprintf( path, sizeof(path), "/proc/%lu/task/%lu/stat", (unsigned long)pid, (unsigned long)tid );
    if( n<0 || (size_t)n>=sizeof(path) ) return TK_OS_PROBE_ERROR;
    probe->stat_fd = open( path, O_RDONLY | O_CLOEXEC );
    if( probe->stat_fd<0 ) return (errno==ENOENT || errno==ESRCH) ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;

    /* The sched file is absent on kernels without CONFIG_SCHED_DEBUG: the wait
       time and context switches are then simply not reported. */
    n = snprintf( path, sizeof(path), "/proc/%lu/task/%lu/sched", (unsigned long)pid, (unsigned long)tid );
    if( n>0 && (size_t)n<sizeof(path) ) probe->sched_fd = open( path, O_RDONLY | O_CLOEXEC );
    return TK_OS_PROBE_OK;
}

int
tk_os_probe_read( tk_os_probe_t * probe, tk_os_stats_t * out ) {
    memset( out, 0, sizeof(*out) );
    if( probe->stat_fd<0 ) return TK_OS_PROBE_ERROR;

    char contents[ 8192 ];
    int gone;
    if( read_all( probe->stat_fd, contents, sizeof(contents), &gone )<0 ) return gone ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;
    if( parse_stat( contents, out ) ) return TK_OS_PROBE_ERROR;

    if( probe->sched_fd>=0 ) {
        if( read_all( probe->sched_fd, contents, sizeof(contents), &gone )<0 ) return gone ? TK_OS_PROBE_GONE : TK_OS_PROBE_ERROR;
        parse_sched( contents, out );
    }
    return TK_OS_PROBE_OK;
}

void
tk_os_probe_close( tk_os_probe_t * probe ) {
    if( probe->stat_fd>=0 )  close( probe->stat_fd );
    if( probe->sched_fd>=0 ) close( probe->sched_fd );
    probe->stat_fd  = -1;
    probe->sched_fd = -1;
}

uint64_t
tk_os_probe_fds( tk_os_probe_t const * probe, int * out, uint64_t cap ) {
    uint64_t cnt = 0UL;
    if( probe->stat_fd>=0  && cnt<cap ) out[ cnt++ ] = probe->stat_fd;
    if( probe->sched_fd>=0 && cnt<cap ) out[ cnt++ ] = probe->sched_fd;
    return cnt;
}
