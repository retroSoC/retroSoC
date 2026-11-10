#include <retrosoc/hal/ppalite.h>

/* Keep session and destination alive through completion or successful recovery.
 * The caller has already selected PROCESS and prepared camera pads/clocks.
 * This fragment arms a job; it does not start or publish a completed frame. */
rs_status_t example_ppalite(rs_ppalite_session_t *session,
                           const rs_ppalite_config_t *config,
                           uintptr_t destination, uint32_t capacity)
{
    return rs_ppalite_capture_begin(session, config, destination, capacity,
                                    RS_TIMEOUT_DEFAULT);
}
