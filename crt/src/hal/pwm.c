#include <retrosoc/hal/pwm.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_pwm_status(pwm_status_t status) {
    rs_status_t result;

    switch (status) {
    case PWM_STATUS_OK:
        result = RS_OK;
        break;
    case PWM_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case PWM_STATUS_TIMEOUT:
        result = RS_ETIMEOUT;
        break;
    case PWM_STATUS_EMPTY:
        result = RS_ENOSPC;
        break;
    case PWM_STATUS_LOCKED:
        result = RS_ENOTSUP;
        break;
    case PWM_STATUS_INCOMPATIBLE:
        result = RS_EFORMAT;
        break;
    case PWM_STATUS_BUSY:
    default:
        result = RS_EIO;
        break;
    }
    return result;
}

rs_status_t rs_pwm_probe(void) {
    return rs_pwm_status(pwm_probe((uintptr_t)RS_SOC_APB_PWM_BASE));
}

rs_status_t rs_pwm_timer_configure(uint8_t timer, const rs_pwm_timer_config_t *config) {
    return rs_pwm_status(pwm_timer_configure((uintptr_t)RS_SOC_APB_PWM_BASE, timer, config));
}

rs_status_t rs_pwm_channel_configure(uint8_t channel, const rs_pwm_channel_config_t *config) {
    return rs_pwm_status(pwm_channel_configure((uintptr_t)RS_SOC_APB_PWM_BASE, channel, config));
}

rs_status_t rs_pwm_operator_configure(uint8_t operator_id, const rs_pwm_operator_config_t *config) {
    return rs_pwm_status(
        pwm_operator_configure((uintptr_t)RS_SOC_APB_PWM_BASE, operator_id, config));
}

rs_status_t rs_pwm_fault_configure(const rs_pwm_fault_config_t *config) {
    return rs_pwm_status(pwm_fault_configure((uintptr_t)RS_SOC_APB_PWM_BASE, config));
}

rs_status_t rs_pwm_capture_configure(const rs_pwm_capture_config_t *config) {
    return rs_pwm_status(pwm_capture_configure((uintptr_t)RS_SOC_APB_PWM_BASE, config));
}

rs_status_t rs_pwm_enable(bool debug_freeze) {
    return rs_pwm_status(pwm_enable((uintptr_t)RS_SOC_APB_PWM_BASE, debug_freeze));
}

rs_status_t rs_pwm_disable(void) {
    return rs_pwm_status(pwm_disable((uintptr_t)RS_SOC_APB_PWM_BASE));
}

rs_status_t rs_pwm_apply_update(rs_timeout_t timeout) {
    return rs_pwm_status(pwm_apply_update((uintptr_t)RS_SOC_APB_PWM_BASE, timeout));
}

rs_status_t rs_pwm_software_sync(void) {
    return rs_pwm_status(pwm_software_sync((uintptr_t)RS_SOC_APB_PWM_BASE));
}

rs_status_t rs_pwm_set_duty(uint8_t channel, uint32_t duty, rs_timeout_t timeout) {
    return rs_pwm_status(pwm_set_duty((uintptr_t)RS_SOC_APB_PWM_BASE, channel, duty, timeout));
}

rs_status_t rs_pwm_fade_configure(uint8_t channel, const rs_pwm_fade_segment_t *segment) {
    return rs_pwm_status(pwm_fade_configure((uintptr_t)RS_SOC_APB_PWM_BASE, channel, segment));
}

rs_status_t rs_pwm_fade_start(uint8_t channel) {
    return rs_pwm_status(pwm_fade_start((uintptr_t)RS_SOC_APB_PWM_BASE, channel));
}

rs_status_t rs_pwm_fade_pause(uint8_t channel) {
    return rs_pwm_status(pwm_fade_pause((uintptr_t)RS_SOC_APB_PWM_BASE, channel));
}

rs_status_t rs_pwm_fade_resume(uint8_t channel) {
    return rs_pwm_status(pwm_fade_resume((uintptr_t)RS_SOC_APB_PWM_BASE, channel));
}

rs_status_t rs_pwm_fade_stop(uint8_t channel) {
    return rs_pwm_status(pwm_fade_stop((uintptr_t)RS_SOC_APB_PWM_BASE, channel));
}

rs_status_t rs_pwm_gamma_program(uint8_t channel, const rs_pwm_fade_segment_t *segments,
                                 uint8_t count) {
    return rs_pwm_status(
        pwm_gamma_program((uintptr_t)RS_SOC_APB_PWM_BASE, channel, segments, count));
}

rs_status_t rs_pwm_gamma_start(uint8_t channel, uint8_t count) {
    return rs_pwm_status(pwm_gamma_start((uintptr_t)RS_SOC_APB_PWM_BASE, channel, count));
}

rs_status_t rs_pwm_fault_clear(void) {
    return rs_pwm_status(pwm_fault_clear((uintptr_t)RS_SOC_APB_PWM_BASE));
}

rs_status_t rs_pwm_fault_test(void) {
    return rs_pwm_status(pwm_fault_test((uintptr_t)RS_SOC_APB_PWM_BASE));
}

rs_status_t rs_pwm_capture_read(uint8_t channel, uint32_t *timestamp, rs_timeout_t timeout) {
    return rs_pwm_status(
        pwm_capture_read((uintptr_t)RS_SOC_APB_PWM_BASE, channel, timestamp, timeout));
}

rs_status_t rs_pwm_interrupt_enable(uint32_t mask) {
    return rs_pwm_status(pwm_interrupt_enable((uintptr_t)RS_SOC_APB_PWM_BASE, mask));
}

rs_status_t rs_pwm_interrupt_clear(uint32_t mask) {
    return rs_pwm_status(pwm_interrupt_clear((uintptr_t)RS_SOC_APB_PWM_BASE, mask));
}

rs_status_t rs_pwm_interrupt_test(uint32_t mask) {
    return rs_pwm_status(pwm_interrupt_test((uintptr_t)RS_SOC_APB_PWM_BASE, mask));
}

rs_status_t rs_pwm_get_status(rs_pwm_snapshot_t *snapshot) {
    return rs_pwm_status(pwm_get_status((uintptr_t)RS_SOC_APB_PWM_BASE, snapshot));
}

void rs_pwm_shell_test(int argc, char **argv) {
    static const rs_pwm_timer_config_t timer = {
        .divider_q16_8 = UINT32_C(0x00000100),
        .period = UINT32_C(72000),
        .phase = 0U,
        .count_mode = RS_PWM_COUNT_MODE_UP,
        .load_mode = RS_PWM_LOAD_ON_ZERO,
        .sync_enable = true,
        .enable = true,
    };
    static const rs_pwm_channel_config_t channel = {
        .phase = 0U,
        .duty = UINT32_C(36000),
        .action = UINT16_C(0x0042),
        .timer = 0U,
        .invert = false,
        .enable = true,
    };
    static const rs_pwm_operator_config_t operator_config = {
        .rising_deadtime = 0U,
        .falling_deadtime = 0U,
        .carrier_period = 0U,
        .carrier_duty = 0U,
        .carrier_invert = false,
        .complementary = false,
        .carrier_enable = false,
    };
    static const rs_pwm_fault_config_t fault = {
        .filter_cycles = 2U,
        .safe_state = {RS_PWM_SAFE_LOW, RS_PWM_SAFE_LOW, RS_PWM_SAFE_LOW, RS_PWM_SAFE_LOW},
        .active_high = true,
        .one_shot = false,
        .enable = true,
        .lock = false,
    };
    rs_pwm_snapshot_t snapshot;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_pwm_probe();
    if (status == RS_OK) {
        status = rs_pwm_disable();
    }
    if (status == RS_OK) {
        status = rs_pwm_fault_configure(&fault);
    }
    if (status == RS_OK) {
        status = rs_pwm_operator_configure(0U, &operator_config);
    }
    if (status == RS_OK) {
        status = rs_pwm_timer_configure(0U, &timer);
    }
    if (status == RS_OK) {
        status = rs_pwm_channel_configure(0U, &channel);
    }
    if (status == RS_OK) {
        status = rs_pwm_apply_update(RS_TIMEOUT_DEFAULT);
    }
    if (status == RS_OK) {
        status = rs_pwm_enable(true);
    }
    if (status == RS_OK) {
        status = rs_pwm_get_status(&snapshot);
    }
    if (status != RS_OK) {
        printf("[PWM] V2 test failed: %d\n", status);
        return;
    }
    printf("[APB IP] PWM V2 status=%x outputs=%x\n", snapshot.status, snapshot.output_status);
}
