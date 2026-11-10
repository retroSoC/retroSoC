#include <retrosoc/hal/sdio.h>

rs_status_t example_tiny_sdio(uint32_t *id, uint32_t *version, uint32_t *capability)
{
    /* Tiny has only native host 0. Probe does not initialize an external card. */
    return rs_sdio_probe(RS_SDIO_INSTANCE_0, id, version, capability);
}
