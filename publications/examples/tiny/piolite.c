#include <retrosoc/hal/piolite.h>

/* Probe the block before acquiring GPIO or DMA resources. */
rs_status_t example_piolite(rs_piolite_info_t *info)
{
    return rs_piolite_probe(info);
}
