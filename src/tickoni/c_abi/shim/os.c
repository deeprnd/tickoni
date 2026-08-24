/* Cross-platform OS operations shim.
 * Linux: uses native syscalls
 * macOS: uses Darwin equivalents via system headers
 * Windows: uses Win32 APIs and CRT file-descriptor helpers
 * Zig callers just call these — no platform forks in .zig files.
 */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if FD_HAS_LINUX
#include <signal.h>
#include <unistd.h>
#elif FD_HAS_MACOS
#include <signal.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#elif FD_HAS_WINDOWS
#include <limits.h>
#include <io.h>
#include <windows.h>
#include <tlhelp32.h>
#endif

#include "../../../util/fd_util.h"

#if FD_HAS_LINUX

int64_t tk_monotonic_nanos( void ) {
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  ssize_t n = readlink( "/proc/self/exe", buf, buf_len - 1 );
  if( n<0 ) {
    /* Container environments may not expose /proc/self/exe; fall back to
     * /proc/self/fd/0, then dladdr(). */
    n = readlink( "/proc/self/fd/0", buf, buf_len - 1 );
    if( n<0 ) {
      struct dl_info info;
      if( dladdr( (void *)tk_self_exe_path, &info ) && info.dli_fname ) {
        n = (ssize_t)strlen( info.dli_fname );
        if( (size_t)n < buf_len ) {
          memcpy( buf, info.dli_fname, (size_t)n );
          buf[ n ] = '\0';
          return n;
        }
      }
      return -1;
    }
  }
  buf[ n ] = '\0';
  return (int)n;
}

int tk_parent_pid( int pid ) {
  char path[ 64 ];
  int n = snprintf( path, sizeof(path), "/proc/%d/status", pid );
  if( (n<0) | (n>=(int)sizeof(path)) ) return -1;

  FILE * f = fopen( path, "r" );
  if( !f ) return -1;

  char line[ 256 ];
  int ppid = -1;
  while( fgets( line, sizeof(line), f ) ) {
    if( strncmp( line, "PPid:", 5 )==0 ) {
      ppid = atoi( line+5 );
      break;
    }
  }
  fclose( f );
  return ppid;
}

int tk_kill_process( int pid ) {
  return kill( pid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n<0 ? 0 : (int)n;
}

#elif FD_HAS_MACOS

int64_t tk_monotonic_nanos( void ) {
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  uint32_t size = (uint32_t)buf_len;
  if( _NSGetExecutablePath( buf, &size )==0 ) return (int)strlen( buf );
  return -1;
}

int tk_parent_pid( int pid ) {
  struct kinfo_proc info;
  size_t size = sizeof(info);
  int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
  if( sysctl( mib, 4, &info, &size, NULL, 0 )!=0 ) return -1;
  return (int)info.kp_eproc.e_ppid;
}

int tk_kill_process( int pid ) {
  return kill( pid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n<0 ? 0 : (int)n;
}

#elif FD_HAS_WINDOWS

int64_t tk_monotonic_nanos( void ) {
  LARGE_INTEGER counter;
  LARGE_INTEGER freq;
  if( FD_UNLIKELY( !QueryPerformanceFrequency( &freq ) ) ) return 0;
  if( FD_UNLIKELY( !QueryPerformanceCounter( &counter ) ) ) return 0;
  {
    int64_t whole_secs = (int64_t)(counter.QuadPart / freq.QuadPart);
    int64_t rem_ticks  = (int64_t)(counter.QuadPart % freq.QuadPart);
    return whole_secs * 1000000000LL + (rem_ticks * 1000000000LL) / (int64_t)freq.QuadPart;
  }
}

void tk_sleep_nanos( uint64_t ns ) {
  DWORD ms = (DWORD)((ns + 999999ULL) / 1000000ULL);
  if( (ms==0U) & (ns>0UL) ) ms = 1U;
  Sleep( ms );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  DWORD n = GetModuleFileNameA( NULL, buf, (DWORD)buf_len );
  if( FD_UNLIKELY( (!n) | (n>=buf_len) ) ) return -1;
  return (int)n;
}

int tk_parent_pid( int pid ) {
  HANDLE snap = CreateToolhelp32Snapshot( TH32CS_SNAPPROCESS, 0 );
  if( FD_UNLIKELY( snap==INVALID_HANDLE_VALUE ) ) return -1;

  PROCESSENTRY32 entry;
  memset( &entry, 0, sizeof(entry) );
  entry.dwSize = sizeof(entry);

  int parent = -1;
  if( Process32First( snap, &entry ) ) {
    do {
      if( entry.th32ProcessID==(DWORD)pid ) {
        parent = (int)entry.th32ParentProcessID;
        break;
      }
    } while( Process32Next( snap, &entry ) );
  }

  CloseHandle( snap );
  return parent;
}

int tk_kill_process( int pid ) {
  HANDLE process = OpenProcess( PROCESS_TERMINATE, FALSE, (DWORD)pid );
  if( FD_UNLIKELY( !process ) ) return -1;

  int rc = TerminateProcess( process, 1U ) ? 0 : -1;
  CloseHandle( process );
  return rc;
}

int tk_write( int fd, void const * buf, size_t count ) {
  unsigned int nbytes = count>(size_t)INT_MAX ? (unsigned int)INT_MAX : (unsigned int)count;
  int n = _write( fd, buf, nbytes );
  return n<0 ? 0 : n;
}

#else
/* Fallback for other hosted platforms — stubs. */
int64_t tk_monotonic_nanos( void ) {
  /* Use process time as fallback; CLOCK_MONOTONIC requires _POSIX_C_SOURCE */
  struct timespec ts = { .tv_sec = 0, .tv_nsec = 0 };
  int64_t result = 0;
  (void)ts;
  (void)result;
  return 0;
}

void tk_sleep_nanos( uint64_t ns ) {
  /* No-op sleep on non-POSIX platforms */
  (void)ns;
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  (void)buf; (void)buf_len;
  return -1;
}

int tk_parent_pid( int pid ) {
  (void)pid;
  return -1;
}

int tk_kill_process( int pid ) {
  (void)pid;
  return -1;
}

int tk_write( int fd, void const * buf, size_t count ) {
  (void)fd; (void)buf; (void)count;
  return 0;
}

#endif
