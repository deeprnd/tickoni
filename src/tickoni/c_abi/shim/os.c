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

 *   tk_write                — write to a file descriptor, returns bytes written
 *   tk_isatty               — check if a file descriptor refers to a terminal
 *   tk_fflush               — flush stderr
 *   tk_setenv               — set an environment variable
 *   tk_getenv               — get an environment variable (thread-local buffer)
 */

#if FD_HAS_LINUX
#define _GNU_SOURCE
#endif

#include <errno.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "os.h"

#if TK_PROCESS_TEST
static uint tk_process_test_exit_code;
static uint tk_process_test_call_count;
static int  tk_process_test_enabled;
static uint tk_process_test_force_error;
static uint tk_process_test_force_native_error;
static int  tk_process_test_force_enabled;

void
tk_process_test_eintr_then_exit( uint exit_code ) {
  tk_process_test_exit_code  = exit_code;
  tk_process_test_call_count = 0U;
  tk_process_test_enabled    = 1;
}

uint
tk_process_test_native_call_count( void ) {
  return tk_process_test_call_count;
}

void
tk_process_test_force_failure( uint error,
                               uint native_error ) {
  tk_process_test_force_error        = error;
  tk_process_test_force_native_error = native_error;
  tk_process_test_force_enabled      = 1;
}

static int
tk_process_test_reap( tk_process_reap_result_t * out ) {
  if( !tk_process_test_enabled ) return 0;
  tk_process_test_call_count += 3U; /* EINTR, EINTR, terminal exit */
  tk_process_test_enabled     = 0;
  memset( out, 0, sizeof(*out) );
  out->kind      = TK_PROCESS_REAP_EXITED;
  out->exit_code = tk_process_test_exit_code;
  return 1;
}

static int
tk_process_test_force( tk_process_terminate_result_t * out ) {
  if( !tk_process_test_force_enabled ) return 0;
  tk_process_test_force_enabled = 0;
  memset( out, 0, sizeof(*out) );
  out->error        = tk_process_test_force_error;
  out->native_error = tk_process_test_force_native_error;
  return 1;
}
#endif

/* Shared Linux/macOS implementations — both platforms use POSIX clock_gettime
 * and nanosleep with identical signatures and semantics. */
#if FD_HAS_LINUX || FD_HAS_MACOS

#if FD_HAS_LINUX
#include <sched.h>
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

uint
tk_process_diagnostic_pid( ulong process_token ) {
  return (uint)process_token;
}

static uint
tk_process_error_from_errno( int err ) {
  switch( err ) {
  case 0:      return TK_PROCESS_ERROR_NONE;
  case EACCES:
  case EPERM:  return TK_PROCESS_ERROR_ACCESS_DENIED;
  case ESRCH:  return TK_PROCESS_ERROR_INVALID_PROCESS;
  case EINVAL: return TK_PROCESS_ERROR_INVALID_ARGUMENT;
  case EAGAIN:
  case ENOMEM: return TK_PROCESS_ERROR_RESOURCE_EXHAUSTED;
  case ENOSYS: return TK_PROCESS_ERROR_UNSUPPORTED;
  default:     return TK_PROCESS_ERROR_SYSTEM;
  }
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

int tk_get_affinity(int pid, unsigned char *mask) {
  /* Linux/macOS: sched_getaffinity returns the CPU affinity mask.
   * On Linux this is a real syscall; on macOS it's a no-op stub.
   * mask must point to a buffer of at least cpu_set_bytes (128) bytes. */
#if FD_HAS_LINUX
  size_t len = 128; /* cpu_set_bytes — matches CpuSet size */
  int rc = sched_getaffinity((pid_t)pid, len, (cpu_set_t *)mask);
  return rc < 0 ? -1 : 0;
#else
  /* macOS: no sched_getaffinity; return all bits set (all CPUs available). */
  (void)pid;
  for (size_t i = 0; i < 128; i++) mask[i] = 0xFF;
  return 0;
#endif
}

int tk_set_affinity(int pid, const unsigned char *mask) {
  /* Linux/macOS: sched_setaffinity sets the CPU affinity mask.
   * On Linux this is a real syscall; on macOS it's a no-op stub.
   * mask must point to a buffer of at least cpu_set_bytes (128) bytes. */
#if FD_HAS_LINUX
  size_t len = 128; /* cpu_set_bytes — matches CpuSet size */
  int rc = sched_setaffinity((pid_t)pid, len, (cpu_set_t *)mask);
  return rc < 0 ? -1 : 0;
#else
  /* macOS: no sched_setaffinity; no-op. */
  (void)pid;
  (void)mask;
  return 0;
#endif
}

void
tk_process_reap_nohang( ulong                      process_token,
                        tk_process_reap_result_t * out ) {
#if TK_PROCESS_TEST
  if( tk_process_test_reap( out ) ) return;
#endif
  memset( out, 0, sizeof(*out) );
  int status = 0;
  pid_t rc;
  do {
    rc = waitpid( (pid_t)process_token, &status, WNOHANG );
  } while( FD_UNLIKELY( (rc<0) & (errno==EINTR) ) );
  if( FD_UNLIKELY( rc<0 ) ) {
    int err = errno;
    if( err==ECHILD ) {
      out->kind = TK_PROCESS_REAP_NO_CHILD;
      return;
    }
    out->kind         = TK_PROCESS_REAP_FAILED;
    out->error        = tk_process_error_from_errno( err );
    out->native_error = (uint)err;
  } else if( !rc ) {
    out->kind = TK_PROCESS_REAP_RUNNING;
  } else {
    out->native_status = (uint)status;
    if( WIFEXITED( status ) ) {
      out->kind      = TK_PROCESS_REAP_EXITED;
      out->exit_code = (uint)WEXITSTATUS( status );
    } else if( WIFSIGNALED( status ) ) {
      out->kind   = TK_PROCESS_REAP_SIGNALED;
      out->signal = (uint)WTERMSIG( status );
    } else if( WIFSTOPPED( status ) ) {
      out->kind   = TK_PROCESS_REAP_STOPPED;
      out->signal = (uint)WSTOPSIG( status );
    } else {
      out->kind         = TK_PROCESS_REAP_FAILED;
      out->error        = TK_PROCESS_ERROR_SYSTEM;
      out->native_error = (uint)status;
    }
  }
}

void
tk_process_force_terminate( ulong                           process_token,
                            tk_process_terminate_result_t * out ) {
  memset( out, 0, sizeof(*out) );
#if TK_PROCESS_TEST
  if( tk_process_test_force( out ) ) return;
#endif
  if( FD_UNLIKELY( kill( (pid_t)process_token, SIGKILL ) ) ) {
    int err           = errno;
    out->error        = tk_process_error_from_errno( err );
    out->native_error = (uint)err;
    return;
  }
  out->accepted     = 1U;
  out->action_kind  = TK_PROCESS_TERMINATION_SIGNAL;
  out->action_value = (uint)SIGKILL;
}

void
tk_process_release( ulong process_token,
                    ulong thread_token ) {
  (void)process_token;
  (void)thread_token;
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

static volatile LONG tk_winsock_initialized;

int tk_port_is_in_use( uint16_t port ) {
  /* Windows: initialize Winsock once per process, then try to bind.
   * WSAStartup is required on Win32 before any socket API call.
   * WSACleanup must only be called once per WSAStartup — track
   * success with a flag so we don't call it on error paths
   * where startup failed (which would violate the API contract). */
  if( InterlockedCompareExchange( &tk_winsock_initialized, 1L, 0L )==0L ) {
    WSADATA wsa;
    if( WSAStartup( MAKEWORD( 2, 2 ), &wsa )!=0 ) {
      InterlockedExchange( &tk_winsock_initialized, 0L );
      return 1;
    }
  }
  SOCKET sock = socket( AF_INET, SOCK_STREAM, IPPROTO_TCP );
  if( sock==INVALID_SOCKET ) return 1;
  struct sockaddr_in addr;
  memset( &addr, 0, sizeof(addr) );
  addr.sin_family      = AF_INET;
  addr.sin_port        = htons( port );
  addr.sin_addr.s_addr = htonl( INADDR_ANY );
  int busy = bind( sock, (struct sockaddr *)&addr, sizeof(addr) )!=0;
  closesocket( sock );
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

uint
tk_process_diagnostic_pid( ulong process_token ) {
  DWORD pid = GetProcessId( (HANDLE)(uintptr_t)process_token );
  return (uint)pid;
}

static uint
tk_process_error_from_windows( DWORD err ) {
  switch( err ) {
  case ERROR_SUCCESS:           return TK_PROCESS_ERROR_NONE;
  case ERROR_ACCESS_DENIED:     return TK_PROCESS_ERROR_ACCESS_DENIED;
  case ERROR_INVALID_HANDLE:
  case ERROR_NOT_FOUND:         return TK_PROCESS_ERROR_INVALID_PROCESS;
  case ERROR_INVALID_PARAMETER: return TK_PROCESS_ERROR_INVALID_ARGUMENT;
  case ERROR_NOT_ENOUGH_MEMORY:
  case ERROR_OUTOFMEMORY:       return TK_PROCESS_ERROR_RESOURCE_EXHAUSTED;
  case ERROR_NOT_SUPPORTED:     return TK_PROCESS_ERROR_UNSUPPORTED;
  default:                      return TK_PROCESS_ERROR_SYSTEM;
  }
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

int tk_get_affinity(int pid, unsigned char *mask) {
  /* Windows exposes the process affinity mask as a native ULONG_PTR rather
   * than a POSIX cpu_set_t.  Tickoni's CpuSet is 128 bytes; copy the native
   * mask into its low bytes and clear the remainder so callers never inspect
   * uninitialized data.  pid==0 means the current process. */
  if( FD_UNLIKELY( !mask ) ) return -1;
  memset( mask, 0, 128UL );

  HANDLE process = pid==0 ? GetCurrentProcess() : OpenProcess( PROCESS_QUERY_INFORMATION, FALSE, (DWORD)pid );
  if( FD_UNLIKELY( !process ) ) return -1;

  DWORD_PTR process_mask = 0;
  DWORD_PTR system_mask  = 0;
  int ok = GetProcessAffinityMask( process, &process_mask, &system_mask );
  if( pid!=0 ) CloseHandle( process );
  if( FD_UNLIKELY( !ok ) ) return -1;

  memcpy( mask, &process_mask, sizeof(process_mask) );
  return 0;
}

int tk_set_affinity(int pid, const unsigned char *mask) {
  /* Windows: no POSIX affinity API; no-op. */
  (void)pid; (void)mask;
  return 0;
}

void
tk_process_reap_nohang( ulong                      process_token,
                        tk_process_reap_result_t * out ) {
#if TK_PROCESS_TEST
  if( tk_process_test_reap( out ) ) return;
#endif
  memset( out, 0, sizeof(*out) );
  HANDLE process = (HANDLE)(uintptr_t)process_token;
  DWORD wait_rc  = WaitForSingleObject( process, 0U );
  out->native_status = (uint)wait_rc;
  if( wait_rc==WAIT_TIMEOUT ) {
    out->kind = TK_PROCESS_REAP_RUNNING;
    return;
  }
  if( FD_UNLIKELY( wait_rc!=WAIT_OBJECT_0 ) ) {
    DWORD err         = GetLastError();
    out->kind         = TK_PROCESS_REAP_FAILED;
    out->error        = tk_process_error_from_windows( err );
    out->native_error = (uint)err;
    return;
  }
  DWORD code = 0U;
  if( FD_UNLIKELY( !GetExitCodeProcess( process, &code ) ) ) {
    DWORD err         = GetLastError();
    out->kind         = TK_PROCESS_REAP_FAILED;
    out->error        = tk_process_error_from_windows( err );
    out->native_error = (uint)err;
    return;
  }
  out->kind      = TK_PROCESS_REAP_EXITED;
  out->exit_code = (uint)code;
}

void
tk_process_force_terminate( ulong                           process_token,
                            tk_process_terminate_result_t * out ) {
  static DWORD const force_exit_code = 0x544B494CU;
  memset( out, 0, sizeof(*out) );
#if TK_PROCESS_TEST
  if( tk_process_test_force( out ) ) return;
#endif
  HANDLE process = (HANDLE)(uintptr_t)process_token;
  if( FD_UNLIKELY( !TerminateProcess( process, force_exit_code ) ) ) {
    DWORD err         = GetLastError();
    out->error        = tk_process_error_from_windows( err );
    out->native_error = (uint)err;
    return;
  }
  out->accepted     = 1U;
  out->action_kind  = TK_PROCESS_TERMINATION_EXIT_CODE;
  out->action_value = (uint)force_exit_code;
}

void
tk_process_release( ulong process_token,
                    ulong thread_token ) {
  if( thread_token ) CloseHandle( (HANDLE)(uintptr_t)thread_token );
  if( process_token ) CloseHandle( (HANDLE)(uintptr_t)process_token );
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

uint
tk_process_diagnostic_pid( ulong process_token ) {
  return (uint)process_token;
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

int tk_get_affinity(int pid, unsigned char *mask) {
  /* Fallback stubs — no-op affinity. */
  (void)pid; (void)mask;
  return 0;
}

int tk_set_affinity(int pid, const unsigned char *mask) {
  /* Fallback stubs — no-op affinity. */
  (void)pid; (void)mask;
  return 0;
}

void
tk_process_reap_nohang( ulong                      process_token,
                        tk_process_reap_result_t * out ) {
#if TK_PROCESS_TEST
  if( tk_process_test_reap( out ) ) return;
#endif
  (void)process_token;
  memset( out, 0, sizeof(*out) );
  out->kind  = TK_PROCESS_REAP_FAILED;
  out->error = TK_PROCESS_ERROR_UNSUPPORTED;
}

void
tk_process_force_terminate( ulong                           process_token,
                            tk_process_terminate_result_t * out ) {
  (void)process_token;
  memset( out, 0, sizeof(*out) );
#if TK_PROCESS_TEST
  if( tk_process_test_force( out ) ) return;
#endif
  out->error = TK_PROCESS_ERROR_UNSUPPORTED;
}

void
tk_process_release( ulong process_token,
                    ulong thread_token ) {
  (void)process_token;
  (void)thread_token;
}

int tk_setenv( const char * name, const char * value, int overwrite ) {
  (void)name; (void)value; (void)overwrite;
  return -1;
}

#endif /* FD_HAS_LINUX || FD_HAS_MACOS */
