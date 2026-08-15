#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clock.h>
#include <retrosoc/hal/sysctrl.h>

#define RS_CLOCK_ERROR_UNSUPPORTED  1U
#define RS_CLOCK_ERROR_LOCK_TIMEOUT 2U

static bool rs_clock_frequency_valid(rs_clock_frequency_t frequency) {
    return (uint32_t)frequency <= (uint32_t)RS_CLOCK_FREQ_192MHZ;
}

rs_status_t rs_clock_get_status(rs_clock_status_t *status) {
    rs_sysctrl_pll_status_t sysctrl_status;
    uint8_t requested_frequency;

    if (status == NULL) {
        return RS_EINVAL;
    }
    if ((rs_sysctrl_get_pll_config(&requested_frequency) != RS_OK) ||
        (rs_sysctrl_get_pll_status(&sysctrl_status) != RS_OK)) {
        return RS_EIO;
    }
    status->requested_frequency = (rs_clock_frequency_t)requested_frequency;
    status->active_frequency = (rs_clock_frequency_t)sysctrl_status.active_selection;
    status->error_reason = sysctrl_status.error_reason;
    status->active_valid = sysctrl_status.active_valid;
    status->busy = sysctrl_status.busy;
    status->safe_clock = sysctrl_status.safe_clock;
    status->pll_locked = sysctrl_status.pll_locked;
    status->capable = sysctrl_status.capable;
    return RS_OK;
}

rs_status_t rs_clock_frequency_hz(rs_clock_frequency_t frequency, uint32_t *frequency_hz) {
    if (!rs_clock_frequency_valid(frequency) || (frequency_hz == NULL)) {
        return RS_EINVAL;
    }
    *frequency_hz = ((uint32_t)frequency + 1U) * UINT32_C(24000000);
    return RS_OK;
}

rs_status_t rs_clock_get_active_hz(uint32_t *frequency_hz) {
    rs_clock_status_t status;

    if (frequency_hz == NULL) {
        return RS_EINVAL;
    }
    if (rs_clock_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if (!status.capable) {
        *frequency_hz = CPU_FREQ * UINT32_C(1000000);
        return RS_OK;
    }
    if (!status.active_valid || status.busy) {
        return RS_EIO;
    }
    return rs_clock_frequency_hz(status.active_frequency, frequency_hz);
}

rs_status_t rs_clock_set_frequency(rs_clock_frequency_t frequency, rs_timeout_t timeout) {
    rs_clock_status_t status;
    bool busy_observed = false;

    if (!rs_clock_frequency_valid(frequency)) {
        return RS_EINVAL;
    }
    if (rs_clock_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if (!status.capable) {
        return RS_ENOTSUP;
    }
    if (status.busy) {
        return RS_EIO;
    }

    if ((rs_sysctrl_clear_pll_error() != RS_OK) ||
        (rs_sysctrl_set_pll_config((uint8_t)frequency) != RS_OK) ||
        (rs_sysctrl_apply_pll_config() != RS_OK)) {
        return RS_EIO;
    }

    while (timeout-- != 0U) {
        if (rs_clock_get_status(&status) != RS_OK) {
            return RS_EIO;
        }
        busy_observed = busy_observed || status.busy;
        if (busy_observed && !status.busy) {
            if (status.error_reason == RS_CLOCK_ERROR_UNSUPPORTED) {
                return RS_ENOTSUP;
            }
            if (status.error_reason == RS_CLOCK_ERROR_LOCK_TIMEOUT) {
                return RS_ETIMEOUT;
            }
            return status.error_reason == 0U ? RS_OK : RS_EIO;
        }
    }

    return RS_ETIMEOUT;
}
