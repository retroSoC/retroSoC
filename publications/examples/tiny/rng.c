#include <retrosoc/hal/rng.h>

rs_status_t example_rng(rs_rng_snapshot_t *snapshot)
{
    return rs_rng_get_status(snapshot);
}
