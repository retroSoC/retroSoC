#include <retrosoc/hal/extension.h>

rs_status_t example_ext_l(rs_extension_slot_t slot, rs_extension_capabilities_t *capabilities)
{
    return rs_extension_probe(slot, capabilities);
}
