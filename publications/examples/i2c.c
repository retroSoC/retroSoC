#include <retrosoc/hal/i2c.h>

rs_status_t example_i2c(rs_i2c_bus_t bus, uint32_t source_clock_hz, uint32_t bus_hz)
{
    return rs_i2c_init(bus, source_clock_hz, bus_hz);
}
