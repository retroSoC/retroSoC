#include <retrosoc/hal/sdram.h>

rs_status_t example_sdram(const rs_sdram_config_t *config)
{
    return rs_sdram_configure(config);
}
