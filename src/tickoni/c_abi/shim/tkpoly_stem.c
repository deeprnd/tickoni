#include "../../../disco/topo/fd_topo.h"
#include "tkpoly_stem.h"

/* Policy limit for this tkpoly process.  Set by the stemRun bootstrap in
   tile_main.zig after reading payment_pipeline.config.  The default 100000
   (1000.00 USD) matches PaymentPipelineConfig's built-in default. */
static long long TKPOLY_POLICY_LIMIT_CENTS = 100000LL;

void
tkpoly_set_policy_limit_cents( long long policy_limit_cents ) {
  TKPOLY_POLICY_LIMIT_CENTS = policy_limit_cents;
}
