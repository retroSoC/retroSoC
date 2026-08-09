#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clock.h>

#define RS_CLOCK_CMD_APPLY           UINT32_C(0x00000001)
#define RS_CLOCK_CMD_CLEAR_ERROR     UINT32_C(0x00000002)
#define RS_CLOCK_STATUS_ACTIVE_MASK  UINT32_C(0x00000007)
#define RS_CLOCK_STATUS_ACTIVE_VALID UINT32_C(0x00000008)
#define RS_CLOCK_STATUS_BUSY         UINT32_C(0x00000010)
#define RS_CLOCK_STATUS_ERROR_SHIFT  6U
#define RS_CLOCK_STATUS_SAFE_CLOCK   UINT32_C(0x00000100)
#define RS_CLOCK_STATUS_PLL_LOCKED   UINT32_C(0x00000200)
#define RS_CLOCK_STATUS_CAPABLE      UINT32_C(0x00000400)
#define RS_CLOCK_ERROR_UNSUPPORTED   1U
#define RS_CLOCK_ERROR_LOCK_TIMEOUT  2U

static bool rs_clock_frequency_valid(rs_clock_frequency_t frequency) {
    return (uint32_t)frequency <= (uint32_t)RS_CLOCK_FREQ_192MHZ;
}

rs_status_t rs_clock_get_status(rs_clock_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = reg_sysctrl_pll_status;
    status->requested_frequency =
        (rs_clock_frequency_t)(reg_sysctrl_pll_cfg & RS_CLOCK_STATUS_ACTIVE_MASK);
    status->active_frequency = (rs_clock_frequency_t)(value & RS_CLOCK_STATUS_ACTIVE_MASK);
    status->error_reason = (uint8_t)((value >> RS_CLOCK_STATUS_ERROR_SHIFT) & UINT32_C(0x3));
    status->active_valid = (value & RS_CLOCK_STATUS_ACTIVE_VALID) != 0U;
    status->busy = (value & RS_CLOCK_STATUS_BUSY) != 0U;
    status->safe_clock = (value & RS_CLOCK_STATUS_SAFE_CLOCK) != 0U;
    status->pll_locked = (value & RS_CLOCK_STATUS_PLL_LOCKED) != 0U;
    status->capable = (value & RS_CLOCK_STATUS_CAPABLE) != 0U;
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

    reg_sysctrl_pll_cmd = RS_CLOCK_CMD_CLEAR_ERROR;
    reg_sysctrl_pll_cfg = (uint32_t)frequency;
    reg_sysctrl_pll_cmd = RS_CLOCK_CMD_APPLY;

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
