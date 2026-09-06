#include <retrosoc/hal/ws2812.h>

rs_status_t example_ws2812(const rs_ws2812_config_t *config)
{
    return rs_ws2812_init(config);
}
