#include <retrosoc/hal/piolite.h>

/* The caller has quiesced native GPIO owners and prepared the program image.
 * A successful claim retains ownership; it does not start an SM or finish DMA. */
rs_status_t example_tiny_piolite(rs_piolite_session_t *session,
                                const rs_piolite_config_t *config)
{
    rs_status_t result = rs_piolite_configure(session, config);
    if (result != RS_OK) {
        return result;
    }
    return rs_piolite_claim(session, RS_TIMEOUT_DEFAULT);
}
