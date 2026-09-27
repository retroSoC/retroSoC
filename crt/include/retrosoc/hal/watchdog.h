#ifndef RETROSOC_WDG_H
#define RETROSOC_WDG_H

#include <wdg.h>

#include <retrosoc/core/status.h>

typedef wdg_config_t rs_watchdog_config_t;
typedef wdg_snapshot_t rs_watchdog_status_t;

rs_status_t rs_watchdog_configure(const rs_watchdog_config_t *config);
rs_status_t rs_watchdog_start(rs_timeout_t timeout);
rs_status_t rs_watchdog_service(rs_timeout_t timeout);
rs_status_t rs_watchdog_get_status(rs_watchdog_status_t *status, rs_timeout_t timeout);
rs_status_t rs_watchdog_clear_reset_cause(rs_timeout_t timeout);

void ip_wdg_test(int argc, char **argv);
#endif
