#include <retrosoc/hal/fabric_monitor.h>

rs_status_t example_monitor(void)
{
    return rs_fabric_monitor_snapshot();
}
