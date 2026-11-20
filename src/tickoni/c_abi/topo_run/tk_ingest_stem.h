#ifndef __TK_INGEST_STEM_H__
#define __TK_INGEST_STEM_H__

#include <stdint.h>
#include "../../../disco/topo/fd_topo.h"
#include "../shim/audit_schema.h"

extern fd_topo_run_tile_t TK_INGEST_RUN;
extern fd_topo_run_tile_t const * tk_get_ingest_run_tile( void );
extern char const * tk_get_ingest_run_name( void );
extern void * tk_get_ingest_run_run( void );
extern void * tk_get_ingest_run_scratch_align( void );
extern void * tk_get_ingest_run_scratch_footprint( void );
extern void * tk_get_ingest_run_privileged_init( void );
extern void * tk_get_ingest_run_unprivileged_init( void );
extern ulong tkings_tile_scratch_align( void );
extern ulong tkings_tile_scratch_footprint( void );

/* The generator is the Zig payment runtime's syntheticPayment, installed
   after the child's process config has been read and validated. */
typedef void (*tkings_payment_generator_t)( uint64_t offset, PaymentMessage * out );
extern void tkings_set_event_count( uint64_t event_count );
extern void tkings_set_payment_generator( tkings_payment_generator_t generator );
extern void tkings_set_stuck_hook( uint64_t after_messages, uint64_t sleep_ns );
extern void tkings_set_crash_after_heartbeats( uint32_t heartbeat_count );

#endif
