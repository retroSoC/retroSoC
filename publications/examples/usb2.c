#include <retrosoc/hal/usb2.h>

rs_status_t example_usb2(
    uint32_t *ip_id,
    uint32_t *version,
    uint32_t *capability0,
    uint32_t *capability1)
{
    return rs_usb2_probe(ip_id, version, capability0, capability1);
}
