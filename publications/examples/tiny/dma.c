#include <retrosoc/hal/dma.h>

rs_status_t example_dma(uint32_t channel, const rs_dma_config_t *config)
{
    rs_status_t result = rs_dma_configure(channel, config);
    if (result != RS_OK) {
        return result;
    }
    return rs_dma_start(channel);
}
