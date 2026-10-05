/* Cross-platform OS operations shim.
 *
 * Linux:   uses native syscalls (clock_gettime, nanosleep, readlink, /proc)
 * macOS:   uses Darwin equivalents (_NSGetExecutablePath, sysctl)
 * Windows: uses Win32 APIs (QueryPerformanceCounter, GetModuleFileNameA,
 *          CreateToolhelp32Snapshot, WaitForSingleObject)
 * Fallback: stubs compiled when no platform guard matches (test-only)
 *
 * Zig callers import c_abi.os and call these — no platform forks in .zig files.
 *
 * Function catalog:
 *   tk_port_is_in_use       — bind a TCP socket to check port availability (Win32 only)
 *   tk_monotonic_nanos      — monotonic clock in nanoseconds
 *   tk_sleep_nanos          — sleep for a specified nanosecond count
 *   tk_self_exe_path        — resolve the executable's file path
 *   tk_parent_pid           — get the parent PID of a given process
 *   tk_process_id_from_handle — convert a process HANDLE to PID (Win32: returns input; POSIX: stub)
 *   tk_process_poll         — poll a process for termination status
 *   tk_kill_process         — send SIGKILL / TerminateProcess to a process
 *   tk_kill_process_group   — kill entire process group (Linux/macOS only)
 *   tk_write                — write to a file descriptor, returns bytes written
 *   tk_isatty               — check if a file descriptor refers to a terminal
 *   tk_fflush               — flush stderr
 *   tk_setenv               — set an environment variable
 *   tk_getenv               — get an environment variable (thread-local buffer)
 */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Shared Linux/macOS implementations — both platforms use POSIX clock_gettime
 * and nanosleep with identical signatures and semantics. */
#if FD_HAS_LINUX || FD_HAS_MACOS

#if FD_HAS_LINUX
#include <signal.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#elif FD_HAS_MACOS
#include <signal.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#endif

#include "../../../util/fd_util.h"

int tk_port_is_in_use( uint16_t port ) {
  /* POSIX: create TCP socket, attempt bind on 0.0.0.0:port,
   * close socket, return non-zero if bind failed (port in use). */
  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = htonl( INADDR_ANY );

  int fd = socket( AF_INET, SOCK_STREAM, 0 );
  if( fd < 0 ) return 0;  /* socket() failed — can't determine, assume free */
  int busy = ( bind( fd, (struct sockaddr *)&addr, sizeof(addr) ) != 0 );
  close( fd );
  return busy;
}

int64_t tk_monotonic_nanos( void ) {
  /* Uses clock_gettime(CLOCK_MONOTONIC) which is guaranteed monotonic
   * across suspend/resume cycles — unlike CLOCK_REALTIME. */
  struct timespec ts;
  clock_gettime( CLOCK_MONOTONIC, &ts );
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

void tk_sleep_nanos( uint64_t ns ) {
  /* nanosleep is interruptible by signals; the caller loops if EINTR
   * is returned (via the Zig wrapper's sleepNanos). */
  struct timespec ts = { .tv_sec  = (time_t)(ns / 1000000000ULL),
                         .tv_nsec = (long)(ns % 1000000000ULL) };
  nanosleep( &ts, NULL );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
#if FD_HAS_LINUX
  /* Linux: /proc/self/exe is a symlink to the running binary.
   * Readlink returns the target without null-terminating it. */
  ssize_t n = readlink( "/proc/self/exe", buf, buf_len - 1 );
  if( n<0 ) return -1;
  buf[ n ] = '\0';
  return (int)n;
#else
  /* macOS: _NSGetExecutablePath fills a buffer with the path.
   * Returns -1 if buffer is too small, 0 on success. */
  uint32_t size = (uint32_t)buf_len;
  if( _NSGetExecutablePath( buf, &size )==0 ) return (int)strlen( buf );
  return -1;
#endif
}

int tk_parent_pid( int pid ) {
#if FD_HAS_LINUX
  /* Linux: parse /proc/<pid>/status for the PPid field.
   * Reliable because /proc is mounted per-system and always available. */
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
#else
  /* macOS: sysctl(KERN_PROC_PID) returns a kinfo_proc struct containing
   * kp_eproc.e_ppid. This is the Darwin equivalent of /proc parsing. */
  struct kinfo_proc info;
  size_t size = sizeof(info);
  int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
  if( sysctl( mib, 4, &info, &size, NULL, 0 )!=0 ) return -1;
  return (int)info.kp_eproc.e_ppid;
#endif
}

int tk_process_id_from_handle( uintptr_t handle ) {
  /* Linux/macOS: no concept of HANDLE→PID conversion; return as-is.
   * Windows overrides this with GetProcessId(). */
  return (int)handle;
}

int tk_process_poll( int pid ) {
  /* Linux/macOS: no direct poll equivalent; return -2 (unsupported).
   * Windows overrides this with WaitForSingleObject + GetExitCodeProcess. */
  (void)pid;
  return -2;
}

int tk_process_waitpid( int pid, int * status, int options ) {
  /* POSIX: standard waitpid(2) for non-blocking process reaping.
   * Returns the PID on success, 0 if no child waited on, or -1 on error.
   * Windows does not use this — use tk_process_poll() instead. */
  pid_t rc = waitpid( (pid_t)pid, status, options );
  return rc < 0 ? -1 : (int)rc;
}

int tk_kill_process( int pid ) {
  /* POSIX kill() sends SIGKILL to the target process. Returns -1 on error. */
  return kill( pid, SIGKILL );
}

int tk_kill_process_group( int pgid ) {
  /* Negative pgid kills the entire process group. Used for emergency
   * teardown of stuck tiles (epoll_wait blocks can survive SIGKILL
   * on individual PIDs but are interrupted by group-wide delivery). */
  return kill( -pgid, SIGKILL );
}

int tk_write( int fd, void const * buf, size_t count ) {
  ssize_t n = write( fd, buf, count );
  return n<0 ? 0 : (int)n;
}

int tk_isatty( int fd ) {
  return isatty( fd );
}

void tk_fflush( void ) {
  fflush( stderr );
}

int tk_setenv( const char * name, const char * value, int overwrite ) {
  return setenv( name, value, overwrite );
}

const char * tk_getenv( const char * name ) {
  /* Static thread-local buffer — zero heap, cross-platform stable.
   * Env var values are small and short-lived; caller must use the
   * returned slice before the next getEnv() call on any thread. */
  static _Thread_local char buf[ 4096 ];
  const char * val = getenv( name );
  if( val ) {
    size_t len = strlen( val );
    if( len >= sizeof(buf) ) len = sizeof(buf) - 1;
    memcpy( buf, val, len );
    buf[ len ] = '\0';
    return buf;
  }
  return NULL;
}

#elif FD_HAS_WINDOWS

/* Windows block — uses Win32 APIs throughout.
 * winsock2.h MUST come before windows.h to avoid socket type conflicts. */

#include <winsock2.h>
#include <limits.h>
#include <io.h>
#include <windows.h>
#include <tlhelp32.h>

#include "../../../util/fd_util.h"

int tk_port_is_in_use( uint16_t port ) {
  /* Windows: initialize Winsock, try to bind, clean up.
   * WSAStartup is required on Win32 before any socket API call. */
  WSADATA wsa;
  if( WSAStartup( MAKEWORD( 2, 2 ), &wsa )!=0 ) return 1;
  SOCKET sock = socket( AF_INET, SOCK_STREAM, IPPROTO_TCP );
  if( sock==INVALID_SOCKET ) { WSACleanup(); return 1; }
  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = htonl( INADDR_ANY );
  int busy = bind( sock, (struct sockaddr *)&addr, sizeof(addr) )!=0;
  closesocket( sock );
  WSACleanup();
  return busy;
}

int64_t tk_monotonic_nanos( void ) {
  /* Windows: no clock_gettime. Uses QueryPerformanceCounter (QPC),
   * a high-resolution hardware counter guaranteed monotonic.
   * freq.QuadPart gives ticks per second for nanosecond conversion. */
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
  /* Windows: Sleep() takes milliseconds. Round up to avoid sleeping 0
   * when ns > 0 but ms would truncate to 0. */
  DWORD ms = (DWORD)((ns + 999999ULL) / 1000000ULL);
  if( (ms==0U) & (ns>0UL) ) ms = 1U;
  Sleep( ms );
}

int tk_self_exe_path( char * buf, size_t buf_len ) {
  /* Windows: GetModuleFileNameA returns the full path of the module
   * (exe) that contains the calling code. */
  DWORD n = GetModuleFileNameA( NULL, buf, (DWORD)buf_len );
  if( FD_UNLIKELY( (!n) | (n>=buf_len) ) ) return -1;
  return (int)n;
}

int tk_parent_pid( int pid ) {
  /* Windows: CreateToolhelp32Snapshot enumerates all processes;
   * PROCESSENTRY32 contains th32ParentProcessID for each.
   * This is the Windows equivalent of /proc/<pid>/status parsing. */
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

int tk_process_id_from_handle( uintptr_t handle ) {
  /* Windows: GetProcessId converts a HANDLE to its owning PID.
   * On POSIX, this is a no-op cast (see above). */
  DWORD pid = GetProcessId( (HANDLE)handle );
  return pid ? (int)pid : -1;
}

int tk_process_poll( int pid ) {
  /* Windows: WaitForSingleObject with 0ms timeout checks if the process
   * has exited. GetExitCodeProcess then retrieves the exit code.
   * This is the Windows equivalent of poll(2) or select(2) for processes. */
  HANDLE process = OpenProcess( PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, (DWORD)pid );
  if( FD_UNLIKELY( !process ) ) return -2;
  DWORD wait_rc = WaitForSingleObject( process, 0U );
  if( wait_rc==WAIT_TIMEOUT ) { CloseHandle( process ); return -1; }
  if( wait_rc!=WAIT_OBJECT_0 ) { CloseHandle( process ); return -2; }
  DWORD code = 0U;
  int rc = GetExitCodeProcess( process, &code ) ? (int)(code & 0x7fffffffU) : -2;
  CloseHandle( process );
  return rc;
}

int tk_kill_process( int pid ) {
  /* Windows: TerminateProcess is the equivalent of POSIX SIGKILL.
   * It is immediate and cannot be caught or ignored by the target. */
  HANDLE process = OpenProcess( PROCESS_TERMINATE, FALSE, (DWORD)pid );
  if( FD_UNLIKELY( !process ) ) return -1;

  int rc = TerminateProcess( process, 255U ) ? 0 : -1;
  CloseHandle( process );
  return rc;
}

int tk_write( int fd, void const * buf, size_t count ) {
  /* Windows: _write() operates on C runtime file descriptors.
   * Unlike POSIX write(), it returns int (not ssize_t). */
  unsigned int nbytes = count>(size_t)INT_MAX ? (unsigned int)INT_MAX : (unsigned int)count;
  int n = _write( fd, buf, nbytes );
  return n<0 ? 0 : n;
}

int tk_isatty( int fd ) {
  /* Windows: _isatty() has the same signature as POSIX isatty(). */
  return _isatty( fd );
}

void tk_fflush( void ) {
  fflush( stderr );
}

int tk_setenv( const char * name, const char * value, int overwrite ) {
  /* Windows: _putenv_s does not support the 'overwrite' flag.
   * Always overwrite (consistent with POSIX setenv's 3rd arg=1).
   * POSIX setenv replaces; this matches that behavior. */
  if( overwrite ) {
    if( _putenv_s( name, value )==0 ) return 0;
  }
  return -1;
}

const char * tk_getenv( const char * name ) {
  /* Windows: _dupenv_s allocates a heap buffer (caller must free).
   * We copy into a thread-local buffer to match the POSIX implementation. */
  char * val = NULL;
  size_t sz = 0;
  if( _dupenv_s( &val, &sz, name )==0 && val!=NULL ) {
    static _Thread_local char buf[ 4096 ];
    if( sz<=sizeof(buf) ) memcpy( buf, val, sz-1 ), buf[ sz-1 ] = '\0';
    else memcpy( buf, val, sizeof(buf)-1 ), buf[ sizeof(buf)-1 ] = '\0';
    free( val );
    return buf;
  }
  return NULL;
}

#else

/* Fallback for other hosted platforms — stubs.
 * Compiled when none of FD_HAS_LINUX, FD_HAS_MACOS, or FD_HAS_WINDOWS
 * is true. These stubs are only reachable in test contexts where callers
 * handle null/error returns gracefully. */
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

int tk_process_id_from_handle( uintptr_t handle ) {
  return (int)handle;
}

int tk_process_poll( int pid ) {
  (void)pid;
  return -2;
}

int tk_kill_process( int pid ) {
  (void)pid;
  return -1;
}

int tk_write( int fd, void const * buf, size_t count ) {
  (void)fd; (void)buf; (void)count;
  return 0;
}

int tk_isatty( int fd ) {
  (void)fd;
  return 0;
}

void tk_fflush( void ) {
  /* No-op flush on unsupported platforms */
}

const char * tk_getenv( const char * name ) {
  (void)name;
  return NULL;
}

int tk_setenv( const char * name, const char * value, int overwrite ) {
  (void)name; (void)value; (void)overwrite;
  return -1;
}

#endif /* FD_HAS_LINUX || FD_HAS_MACOS */
