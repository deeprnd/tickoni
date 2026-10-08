/* Thin wrappers around Firedancer Tango queue/control primitives.
   Tickoni code binds only to Tickoni-owned tk_* symbols. */

#include <stdint.h>

#include "../../../tango/mcache/fd_mcache.h"
#include "../../../tango/dcache/fd_dcache.h"
#include "../../../tango/fseq/fd_fseq.h"
#include "../../../tango/fctl/fd_fctl.h"
#include "../../../tango/cnc/fd_cnc.h"
#include "../../../tango/tempo/fd_tempo.h"
#include "../../../util/fd_util.h"
#include "../../../util/rng/fd_rng.h"

extern int tk_sandbox_getpid( void );

ulong tk_mcache_align( void ) { return fd_mcache_align(); }
ulong tk_mcache_footprint( ulong depth, ulong app_sz ) { return fd_mcache_footprint( depth, app_sz ); }
void * tk_mcache_new( void * shmem, ulong depth, ulong app_sz, ulong seq0 ) { return fd_mcache_new( shmem, depth, app_sz, seq0 ); }
fd_frag_meta_t * tk_mcache_join( void * shcache ) { return fd_mcache_join( shcache ); }
void * tk_mcache_leave( fd_frag_meta_t const * mcache ) { return fd_mcache_leave( mcache ); }
void * tk_mcache_delete( void * shcache ) { return fd_mcache_delete( shcache ); }
ulong tk_mcache_depth( fd_frag_meta_t const * mcache ) { return fd_mcache_depth( mcache ); }
ulong tk_mcache_seq0( fd_frag_meta_t const * mcache ) { return fd_mcache_seq0( mcache ); }
ulong * tk_mcache_seq_laddr( fd_frag_meta_t * mcache ) { return fd_mcache_seq_laddr( mcache ); }
ulong const * tk_mcache_seq_laddr_const( fd_frag_meta_t const * mcache ) { return fd_mcache_seq_laddr_const( mcache ); }

ulong
tk_mcache_line_idx( ulong seq,
                    ulong depth ) {
  return fd_mcache_line_idx( seq, depth );
}

void
tk_mcache_publish( fd_frag_meta_t * mcache,
                   ulong            depth,
                   ulong            seq,
                   ulong            sig,
                   ulong            chunk,
                   ulong            sz,
                   ulong            ctl,
                   ulong            tsorig,
                   ulong            tspub ) {
  fd_mcache_publish( mcache, depth, seq, sig, chunk, sz, ctl, tsorig, tspub );
}

ulong
tk_frag_meta_seq_query( fd_frag_meta_t const * meta ) {
  return fd_frag_meta_seq_query( meta );
}

ulong tk_dcache_slot_footprint( ulong mtu ) { return FD_DCACHE_SLOT_FOOTPRINT( mtu ); }
ulong tk_dcache_req_data_sz( ulong mtu, ulong depth, ulong burst, int compact ) { return fd_dcache_req_data_sz( mtu, depth, burst, compact ); }
ulong tk_dcache_align( void ) { return fd_dcache_align(); }
ulong tk_dcache_footprint( ulong data_sz, ulong app_sz ) { return fd_dcache_footprint( data_sz, app_sz ); }
void * tk_dcache_new( void * shmem, ulong data_sz, ulong app_sz ) { return fd_dcache_new( shmem, data_sz, app_sz ); }
uchar * tk_dcache_join( void * shdcache ) { return fd_dcache_join( shdcache ); }
void * tk_dcache_leave( uchar const * dcache ) { return fd_dcache_leave( dcache ); }
void * tk_dcache_delete( void * shdcache ) { return fd_dcache_delete( shdcache ); }
ulong tk_dcache_data_sz( uchar const * dcache ) { return fd_dcache_data_sz( dcache ); }
ulong tk_dcache_app_sz( uchar const * dcache ) { return fd_dcache_app_sz( dcache ); }
uchar * tk_dcache_app_laddr( uchar * dcache ) { return fd_dcache_app_laddr( dcache ); }
uchar const * tk_dcache_app_laddr_const( uchar const * dcache ) { return fd_dcache_app_laddr_const( dcache ); }
int tk_dcache_compact_is_safe( void const * base, void const * dcache, ulong mtu, ulong depth ) { return fd_dcache_compact_is_safe( base, dcache, mtu, depth ); }

ulong tk_fseq_align( void ) { return fd_fseq_align(); }
ulong tk_fseq_footprint( void ) { return fd_fseq_footprint(); }
void * tk_fseq_new( void * shmem, ulong seq0 ) { return fd_fseq_new( shmem, seq0 ); }
ulong * tk_fseq_join( void * shfseq ) { return fd_fseq_join( shfseq ); }
void * tk_fseq_leave( ulong const * fseq ) { return fd_fseq_leave( fseq ); }
void * tk_fseq_delete( void * shfseq ) { return fd_fseq_delete( shfseq ); }

ulong
tk_fseq_query( ulong const * fseq ) {
  return fd_fseq_query( fseq );
}

void
tk_fseq_update( ulong * fseq,
                 ulong   seq ) {
  fd_fseq_update( fseq, seq );
}

void * tk_fctl_new( void * shmem, ulong rx_max ) { return fd_fctl_new( shmem, rx_max ); }
fd_fctl_t * tk_fctl_join( void * shfctl ) { return fd_fctl_join( shfctl ); }
void * tk_fctl_leave( fd_fctl_t * fctl ) { return fd_fctl_leave( fctl ); }
void * tk_fctl_delete( void * shfctl ) { return fd_fctl_delete( shfctl ); }
fd_fctl_t * tk_fctl_cfg_rx_add( fd_fctl_t * fctl, ulong cr_max, ulong const * seq_laddr, ulong * slow_laddr ) { return fd_fctl_cfg_rx_add( fctl, cr_max, seq_laddr, slow_laddr ); }
fd_fctl_t * tk_fctl_cfg_done( fd_fctl_t * fctl, ulong cr_burst, ulong cr_max, ulong cr_resume, ulong cr_refill ) { return fd_fctl_cfg_done( fctl, cr_burst, cr_max, cr_resume, cr_refill ); }
ulong tk_fctl_rx_cnt( fd_fctl_t const * fctl ) { return fd_fctl_rx_cnt( fctl ); }
ulong tk_fctl_cr_burst( fd_fctl_t const * fctl ) { return fd_fctl_cr_burst( fctl ); }
ulong tk_fctl_cr_max( fd_fctl_t const * fctl ) { return fd_fctl_cr_max( fctl ); }
ulong tk_fctl_cr_resume( fd_fctl_t const * fctl ) { return fd_fctl_cr_resume( fctl ); }
ulong tk_fctl_cr_refill( fd_fctl_t const * fctl ) { return fd_fctl_cr_refill( fctl ); }
ulong tk_fctl_rx_cr_max( fd_fctl_t const * fctl, ulong rx_idx ) { return fd_fctl_rx_cr_max( fctl, rx_idx ); }

ulong
tk_fctl_cr_query( fd_fctl_t const * fctl,
                  ulong             tx_seq,
                  ulong *           rx_idx_slow ) {
  ulong  rx_idx_local = 0UL;
  ulong * rx_idx_out  = rx_idx_slow ? rx_idx_slow : &rx_idx_local;
  ulong   cr          = fd_fctl_cr_query( fctl, tx_seq, rx_idx_out );
  if( rx_idx_slow && rx_idx_slow[0]==ULONG_MAX ) rx_idx_slow[0] = ((ulong)-1);
  return cr;
}

void
tk_fctl_rx_cr_return( ulong * rx_seq_laddr,
                      ulong   rx_seq ) {
  fd_fctl_rx_cr_return( rx_seq_laddr, rx_seq );
}

static FD_TL fd_rng_t   tk_tempo_rng_mem[1];
static FD_TL fd_rng_t * tk_tempo_rng = NULL;

static fd_rng_t *
tk_tempo_rng_tls( void ) {
  if( FD_UNLIKELY( !tk_tempo_rng ) ) tk_tempo_rng = fd_rng_join( fd_rng_new( tk_tempo_rng_mem, (uint)tk_sandbox_getpid(), 0UL ) );
  return tk_tempo_rng;
}

double tk_tempo_tick_per_ns( double * opt_sigma ) { return fd_tempo_tick_per_ns( opt_sigma ); }
long tk_tempo_lazy_default( ulong cr_max ) { return fd_tempo_lazy_default( cr_max ); }
ulong tk_tempo_async_min( long lazy, ulong event_cnt, float tick_per_ns ) { return fd_tempo_async_min( lazy, event_cnt, tick_per_ns ); }
ulong tk_tempo_async_reload( ulong async_min ) { return fd_tempo_async_reload( tk_tempo_rng_tls(), async_min ); }

ulong tk_cnc_align( void ) { return fd_cnc_align(); }
ulong tk_cnc_footprint( ulong app_sz ) { return fd_cnc_footprint( app_sz ); }
void * tk_cnc_new( void * shmem, ulong app_sz, ulong type, int64_t now_ns ) {
  uint32_t now_ms = (uint32_t)((uint64_t)now_ns / 1000000ULL);
  return fd_cnc_new( shmem, app_sz, type, (long)now_ms );
}
fd_cnc_t * tk_cnc_join( void * shcnc ) { return fd_cnc_join( shcnc ); }
void * tk_cnc_leave( fd_cnc_t const * cnc ) { return fd_cnc_leave( cnc ); }
void * tk_cnc_delete( void * shcnc ) { return fd_cnc_delete( shcnc ); }
int tk_cnc_open( fd_cnc_t * cnc ) { return fd_cnc_open( cnc ); }
ulong tk_cnc_wait( fd_cnc_t const * cnc, ulong test_signal, long dt, long * opt_now ) { return fd_cnc_wait( cnc, test_signal, dt, opt_now ); }
char const * tk_cnc_strerror( int err ) { return fd_cnc_strerror( err ); }
ulong tk_cstr_to_cnc_signal( char const * cstr ) { return fd_cstr_to_cnc_signal( cstr ); }
char * tk_cnc_signal_cstr( ulong signal, char * buf ) { return fd_cnc_signal_cstr( signal, buf ); }
void * tk_cnc_app_laddr( fd_cnc_t * cnc ) { return fd_cnc_app_laddr( cnc ); }
uint32_t tk_cnc_heartbeat_query( fd_cnc_t const * cnc ) { return (uint32_t)fd_cnc_heartbeat_query( cnc ); }
void tk_cnc_heartbeat( fd_cnc_t * cnc, int64_t now_ns ) {
  uint32_t now_ms = (uint32_t)((uint64_t)now_ns / 1000000ULL);
  fd_cnc_heartbeat( cnc, (long)now_ms );
}
ulong tk_cnc_signal_query( fd_cnc_t const * cnc ) { return fd_cnc_signal_query( cnc ); }
void tk_cnc_signal( fd_cnc_t * cnc, ulong signal ) { fd_cnc_signal( cnc, signal ); }
void tk_cnc_close( fd_cnc_t * cnc ) { fd_cnc_close( cnc ); }
