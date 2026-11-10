#include <retrosoc/hal/rcu.h>

/* Call only after affected clients and their accepted traffic are quiescent. */
rs_status_t example_tiny_rcu(rs_tiny_rcu_snapshot_t *snapshot, rs_timeout_t timeout)
{
    rs_status_t result = rs_tiny_rcu_request_profile(RS_TINY_RCU_PROFILE_SAFE24, timeout);
    if (result != RS_OK) {
        return result;
    }
    /* Reinitialize PSRAM sessions and peripheral timing before resuming them. */
    return rs_tiny_rcu_get_snapshot(snapshot);
}
