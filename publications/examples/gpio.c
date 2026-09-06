#include <retrosoc/hal/gpio.h>

rs_status_t example_gpio(uint32_t pin, const rs_gpio_config_t *config)
{
    return rs_gpio_configure(pin, config);
}
