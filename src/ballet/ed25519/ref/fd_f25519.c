#include "../fd_f25519.h"

/* fd_f25519_rng generates a random fd_f25519_t element.
   Note: insecure, for tests only. */
fd_f25519_t *
fd_f25519_rng_unsafe( fd_f25519_t * r,
                      fd_rng_t *    rng ) {
#if USE_FIAT_32
  r->el[0] = fd_rng_uint( rng );
  r->el[1] = fd_rng_uint( rng );
  r->el[2] = fd_rng_uint( rng );
  r->el[3] = fd_rng_uint( rng );
  r->el[4] = fd_rng_uint( rng );
  r->el[5] = fd_rng_uint( rng );
  r->el[6] = fd_rng_uint( rng );
  r->el[7] = fd_rng_uint( rng );
  r->el[8] = fd_rng_uint( rng );
  r->el[9] = fd_rng_uint( rng );
#else
  r->el[0] = fd_rng_ulong( rng );
  r->el[1] = fd_rng_ulong( rng );
  r->el[2] = fd_rng_ulong( rng );
  r->el[3] = fd_rng_ulong( rng );
  r->el[4] = fd_rng_ulong( rng );
#endif
  fd_f25519_fiat_word_t out[FD_F25519_FIAT_LIMB_CNT];
  fd_f25519_fiat_word_t in [FD_F25519_FIAT_LIMB_CNT];
  fd_f25519_to_fiat( in, r );
  fiat_25519_carry( out, in );
  fd_f25519_from_fiat( r, out );
  return r;
}
