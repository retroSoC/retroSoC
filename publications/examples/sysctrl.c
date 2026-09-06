#include <retrosoc/hal/sysctrl.h>

rs_status_t example_sysctrl(rs_sysctrl_pll_status_t *status)
{
    return rs_sysctrl_get_pll_status(status);
}
