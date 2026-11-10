#include <retrosoc/hal/dvp.h>

rs_status_t example_dvp(const rs_dvp_config_t *config)
{
    return rs_dvp_configure(config);
}
