#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/user_core.h>

#define RS_USER_CORE_STATUS_SEL_MASK     UINT32_C(0x0000001F)
#define RS_USER_CORE_STATUS_BUS_ENABLED  UINT32_C(0x00000100)
#define RS_USER_CORE_STATUS_BUS_IDLE     UINT32_C(0x00000200)
#define RS_USER_CORE_STATUS_DRAINING     UINT32_C(0x00000400)
#define RS_USER_CORE_STATUS_CONFIG_ERROR UINT32_C(0x00000800)

static uint32_t rs_user_core_reset_mask_all(void) {
    return UINT32_MAX >> (UINT32_C(32) - RS_SOC_USER_CORE_COUNT);
}

rs_status_t rs_user_core_get_status(rs_user_core_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = reg_sysctrl_user_core_status;
    status->reset_mask = reg_sysctrl_user_core_reset;
    status->selected_core = (uint8_t)(value & RS_USER_CORE_STATUS_SEL_MASK);
    status->bus_enabled = (value & RS_USER_CORE_STATUS_BUS_ENABLED) != UINT32_C(0);
    status->bus_idle = (value & RS_USER_CORE_STATUS_BUS_IDLE) != UINT32_C(0);
    status->draining = (value & RS_USER_CORE_STATUS_DRAINING) != UINT32_C(0);
    status->config_error = (value & RS_USER_CORE_STATUS_CONFIG_ERROR) != UINT32_C(0);
    return RS_OK;
}

rs_status_t rs_user_core_stop(rs_timeout_t timeout) {
    rs_user_core_status_t status;

    reg_sysctrl_user_core_reset = rs_user_core_reset_mask_all();
    while (timeout-- != 0U) {
        if (rs_user_core_get_status(&status) != RS_OK) {
            return RS_EIO;
        }
        if (status.config_error) {
            return RS_EIO;
        }
        if (!status.bus_enabled && status.bus_idle && !status.draining) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_user_core_start(uint8_t core_id, rs_timeout_t timeout) {
    rs_user_core_status_t status;
    rs_status_t result;
    uint32_t reset_mask;

    if ((uint32_t)core_id >= RS_SOC_USER_CORE_COUNT) {
        return RS_EINVAL;
    }
    result = rs_user_core_stop(timeout);
    if (result != RS_OK) {
        return result;
    }
    reg_sysctrl_user_core_status = RS_USER_CORE_STATUS_CONFIG_ERROR;
    reg_sysctrl_coresel = (uint32_t)core_id;
    if (rs_user_core_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if (status.config_error || status.selected_core != core_id) {
        return RS_EIO;
    }
    reset_mask = rs_user_core_reset_mask_all() & ~(UINT32_C(1) << core_id);
    reg_sysctrl_user_core_reset = reset_mask;
    while (timeout-- != 0U) {
        if (rs_user_core_get_status(&status) != RS_OK) {
            return RS_EIO;
        }
        if (status.config_error) {
            return RS_EIO;
        }
        if (status.bus_enabled && !status.draining && status.selected_core == core_id) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_user_core_reset(uint8_t core_id, rs_timeout_t timeout) {
    if ((uint32_t)core_id >= RS_SOC_USER_CORE_COUNT) {
        return RS_EINVAL;
    }
    return rs_user_core_stop(timeout);
}
