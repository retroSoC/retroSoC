#include <retrosoc/hal/spisd.h>

rs_status_t example_spisd(uint32_t *ip_id, uint32_t *version, uint32_t *capability)
{
    return rs_spisd_probe(ip_id, version, capability);
}
