#include <retrosoc/hal/onchip_sram.h>

rs_status_t example_sram(rs_onchip_sram_info_t *info)
{
    return rs_onchip_sram_probe(info);
}
