#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/xpi_psram.h>

/* Caller owns XPI, routes NSS1/GPIO29 and runs code/IRQs from SRAM. */
rs_status_t example_xpi(rs_xpi_psram_t *device, rs_timeout_t timeout)
{
    rs_tiny_rcu_snapshot_t clocks;
    rs_status_t result = rs_tiny_rcu_get_snapshot(&clocks);
    if (result != RS_OK) {
        return result;
    }
    /* A later clock change or reset invalidates this software session. */
    return rs_xpi_psram_initialize(clocks.mem_hz, timeout, device);
}
