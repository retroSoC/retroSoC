#include <retrosoc/hal/spi.h>

/* Configuration and GPIO personality must already match the external device. */
rs_status_t example_tiny_spi(const rs_spi_config_t *config, rs_timeout_t timeout)
{
    rs_status_t result = rs_spi_configure(config);
    if (result != RS_OK) {
        return result;
    }
    /* Acquisition retains ownership; it does not ARM or complete a transfer. */
    return rs_spi_acquire(timeout);
}
