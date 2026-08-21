#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/user_core.h>

static uint32_t rs_user_core_reset_mask_all(void) {
    return UINT32_MAX >> (UINT32_C(32) - RS_SOC_USER_CORE_COUNT);
}

rs_status_t rs_user_core_get_status(rs_user_core_status_t *status) {
    rs_sysctrl_user_core_status_t sysctrl_status;

    if (status == NULL) {
        return RS_EINVAL;
    }
    if (rs_sysctrl_get_user_core_status(&sysctrl_status) != RS_OK) {
        return RS_EIO;
    }
    status->reset_mask = sysctrl_status.reset_mask;
    status->selected_core = sysctrl_status.selected_core;
    status->bus_enabled = sysctrl_status.bus_enabled;
    status->bus_idle = sysctrl_status.bus_idle;
    status->draining = sysctrl_status.draining;
    status->config_error = sysctrl_status.config_error;
    return RS_OK;
}

rs_status_t rs_user_core_stop(rs_timeout_t timeout) {
    rs_user_core_status_t status;

    if (rs_sysctrl_set_user_core_reset(rs_user_core_reset_mask_all()) != RS_OK) {
        return RS_EIO;
    }
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
    if ((rs_sysctrl_clear_user_core_config_error() != RS_OK) ||
        (rs_sysctrl_set_core_select(core_id) != RS_OK)) {
        return RS_EIO;
    }
    if (rs_user_core_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if (status.config_error || status.selected_core != core_id) {
        return RS_EIO;
    }
    reset_mask = rs_user_core_reset_mask_all() & ~(UINT32_C(1) << core_id);
    if (rs_sysctrl_set_user_core_reset(reset_mask) != RS_OK) {
        return RS_EIO;
    }
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
