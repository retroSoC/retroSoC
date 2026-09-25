#include <retrosoc/hal/timer.h>

rs_status_t example_timer(rs_timer_id_t timer, const rs_timer_config_t *config)
{
    rs_status_t result = rs_timer_configure(timer, config);
    if (result != RS_OK) {
        return result;
    }
    return rs_timer_start(timer);
}
