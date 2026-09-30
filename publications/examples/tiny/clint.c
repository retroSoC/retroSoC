#include <retrosoc/hal/clint.h>

rs_status_t example_clint(uint64_t *time)
{
    return rs_clint_get_time(time);
}
