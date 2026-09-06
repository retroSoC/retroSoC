#include <retrosoc/hal/ps2.h>

rs_status_t example_ps2(uint32_t source_clock_hz)
{
    return rs_ps2_init(source_clock_hz);
}
