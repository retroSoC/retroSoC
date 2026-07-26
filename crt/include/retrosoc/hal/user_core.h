#ifndef RETROSOC_HAL_USER_CORE_H
#define RETROSOC_HAL_USER_CORE_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t reset_mask;
    uint8_t selected_core;
    bool bus_enabled;
    bool bus_idle;
    bool draining;
    bool config_error;
} rs_user_core_status_t;

rs_status_t rs_user_core_get_status(rs_user_core_status_t *status);
rs_status_t rs_user_core_stop(rs_timeout_t timeout);
rs_status_t rs_user_core_start(uint8_t core_id, rs_timeout_t timeout);
rs_status_t rs_user_core_reset(uint8_t core_id, rs_timeout_t timeout);

#endif
