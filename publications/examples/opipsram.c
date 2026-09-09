#include <retrosoc/hal/opipsram.h>

rs_status_t example_opipsram(rs_opipsram_status_t *status)
{
    return rs_opipsram_get_status(status);
}
