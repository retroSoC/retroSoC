#include <retrosoc/hal/sdio.h>

rs_status_t example_sdio(
    rs_sdio_instance_t instance,
    uint32_t *ip_id,
    uint32_t *version,
    uint32_t *capability)
{
    return rs_sdio_probe(instance, ip_id, version, capability);
}
