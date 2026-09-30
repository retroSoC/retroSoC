#include <retrosoc/hal/watchdog.h>
rs_status_t tiny_watchdog_status(rs_watchdog_status_t *status)
{
    return rs_watchdog_get_status(status, RS_TIMEOUT_DEFAULT);
}
