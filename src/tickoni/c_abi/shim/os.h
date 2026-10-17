#ifndef HEADER_tickoni_c_abi_shim_os_h
#define HEADER_tickoni_c_abi_shim_os_h

#include "../../../util/fd_util_base.h"

typedef enum {
  TK_PROCESS_REAP_RUNNING = 0,
  TK_PROCESS_REAP_EXITED,
  TK_PROCESS_REAP_SIGNALED,
  TK_PROCESS_REAP_STOPPED,
  TK_PROCESS_REAP_NO_CHILD,
  TK_PROCESS_REAP_FAILED
} tk_process_reap_kind_t;

typedef enum {
  TK_PROCESS_ERROR_NONE = 0,
  TK_PROCESS_ERROR_ACCESS_DENIED,
  TK_PROCESS_ERROR_INVALID_PROCESS,
  TK_PROCESS_ERROR_INVALID_ARGUMENT,
  TK_PROCESS_ERROR_RESOURCE_EXHAUSTED,
  TK_PROCESS_ERROR_UNSUPPORTED,
  TK_PROCESS_ERROR_SYSTEM
} tk_process_error_t;

typedef struct {
  uint kind;
  uint exit_code;
  uint signal;
  uint native_status;
  uint error;
  uint native_error;
} tk_process_reap_result_t;

typedef enum {
  TK_PROCESS_TERMINATION_NONE = 0,
  TK_PROCESS_TERMINATION_SIGNAL,
  TK_PROCESS_TERMINATION_EXIT_CODE
} tk_process_termination_kind_t;

typedef struct {
  uint accepted;
  uint action_kind;
  uint action_value;
  uint error;
  uint native_error;
} tk_process_terminate_result_t;

uint
tk_process_diagnostic_pid( ulong process_token );

void
tk_process_reap_nohang( ulong                      process_token,
                        tk_process_reap_result_t * out );

void
tk_process_force_terminate( ulong                           process_token,
                            tk_process_terminate_result_t * out );

void
tk_process_release( ulong process_token,
                    ulong thread_token );

#if TK_PROCESS_TEST
void
tk_process_test_eintr_then_exit( uint exit_code );

uint
tk_process_test_native_call_count( void );

void
tk_process_test_force_failure( uint error,
                               uint native_error );
#endif

#endif /* HEADER_tickoni_c_abi_shim_os_h */
