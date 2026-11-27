#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/lib/printf.h>

#define RS_GPIO_DATA_IN_OFFSET          UINT32_C(0x000)
#define RS_GPIO_DATA_OUT_OFFSET         UINT32_C(0x004)
#define RS_GPIO_OUT_SET_OFFSET          UINT32_C(0x008)
#define RS_GPIO_OUT_CLEAR_OFFSET        UINT32_C(0x00C)
#define RS_GPIO_OUT_TOGGLE_OFFSET       UINT32_C(0x010)
#define RS_GPIO_OUTPUT_ENABLE_OFFSET    UINT32_C(0x014)
#define RS_GPIO_OE_SET_OFFSET           UINT32_C(0x018)
#define RS_GPIO_OE_CLEAR_OFFSET         UINT32_C(0x01C)
#define RS_GPIO_OPEN_DRAIN_OFFSET       UINT32_C(0x024)
#define RS_GPIO_INPUT_CMOS_OFFSET       UINT32_C(0x028)
#define RS_GPIO_PULL_UP_OFFSET          UINT32_C(0x02C)
#define RS_GPIO_PULL_DOWN_OFFSET        UINT32_C(0x030)
#define RS_GPIO_ALT_ENABLE_OFFSET       UINT32_C(0x034)
#define RS_GPIO_ALT_SELECT_OFFSET       UINT32_C(0x038)
#define RS_GPIO_USER_SELECT_OFFSET      UINT32_C(0x03C)
#define RS_GPIO_USER_LOCK_OFFSET        UINT32_C(0x040)
#define RS_GPIO_USER_STATUS_OFFSET      UINT32_C(0x044)
#define RS_GPIO_USER_ACCESS_MASK_OFFSET UINT32_C(0x048)
#define RS_GPIO_INTR_RISE_ENABLE_OFFSET UINT32_C(0x04C)
#define RS_GPIO_INTR_FALL_ENABLE_OFFSET UINT32_C(0x050)
#define RS_GPIO_INTR_HIGH_ENABLE_OFFSET UINT32_C(0x054)
#define RS_GPIO_INTR_LOW_ENABLE_OFFSET  UINT32_C(0x058)
#define RS_GPIO_INTR_ENABLE_OFFSET      UINT32_C(0x05C)
#define RS_GPIO_INTR_STATE_OFFSET       UINT32_C(0x060)
#define RS_GPIO_INTR_TEST_OFFSET        UINT32_C(0x068)
#define RS_GPIO_FILTER_ENABLE_OFFSET    UINT32_C(0x06C)
#define RS_GPIO_FILTER_DIV_OFFSET       UINT32_C(0x070)
#define RS_GPIO_FILTER_COUNT_OFFSET     UINT32_C(0x074)
#define RS_GPIO_CONFIG_LOCK_OFFSET      UINT32_C(0x078)
#define RS_GPIO_PAD_CAPABILITY_OFFSET   UINT32_C(0x0F4)
#define RS_GPIO_IP_VERSION_OFFSET       UINT32_C(0x0F8)
#define RS_GPIO_CAPABILITY_OFFSET       UINT32_C(0x0FC)

#ifdef RS_GPIO_TEST_MMIO
extern volatile uint32_t rs_gpio_test_mmio[1024];
#define RS_GPIO_REG(offset) rs_gpio_test_mmio[(offset) / 4U]
#else
#define RS_GPIO_REG(offset) RS_SOC_REG32(RS_SOC_APB4_GPIO_ADMIN_BASE, (offset))
#endif

static void rs_gpio_update_bits(uint32_t offset, uint32_t mask, bool set) {
    uint32_t value = RS_GPIO_REG(offset);

    if (set) {
        value |= mask;
    } else {
        value &= ~mask;
    }
    RS_GPIO_REG(offset) = value;
}

static bool rs_gpio_config_valid(const rs_gpio_config_t *config) {
    return (config != NULL) && (config->mode <= RS_GPIO_MODE_USER_IP) &&
           (config->pull <= RS_GPIO_PULL_DOWN) && (config->trigger <= RS_GPIO_TRIGGER_LOW);
}

static rs_status_t rs_gpio_check_pad_capabilities(const rs_gpio_config_t *config) {
    const uint32_t capability = RS_GPIO_REG(RS_GPIO_PAD_CAPABILITY_OFFSET);

    if ((config->input_cmos && ((capability & RS_GPIO_PAD_CAP_INPUT_CMOS) == 0U)) ||
        ((config->pull == RS_GPIO_PULL_UP) && ((capability & RS_GPIO_PAD_CAP_PULL_UP) == 0U)) ||
        ((config->pull == RS_GPIO_PULL_DOWN) && ((capability & RS_GPIO_PAD_CAP_PULL_DOWN) == 0U))) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

static void rs_gpio_configure_trigger(uint32_t mask, rs_gpio_trigger_t trigger) {
    rs_gpio_update_bits(RS_GPIO_INTR_RISE_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_FALL_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_HIGH_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_LOW_ENABLE_OFFSET, mask, false);
    if ((trigger == RS_GPIO_TRIGGER_RISING) || (trigger == RS_GPIO_TRIGGER_BOTH)) {
        rs_gpio_update_bits(RS_GPIO_INTR_RISE_ENABLE_OFFSET, mask, true);
    }
    if ((trigger == RS_GPIO_TRIGGER_FALLING) || (trigger == RS_GPIO_TRIGGER_BOTH)) {
        rs_gpio_update_bits(RS_GPIO_INTR_FALL_ENABLE_OFFSET, mask, true);
    }
    if (trigger == RS_GPIO_TRIGGER_HIGH) {
        rs_gpio_update_bits(RS_GPIO_INTR_HIGH_ENABLE_OFFSET, mask, true);
    }
    if (trigger == RS_GPIO_TRIGGER_LOW) {
        rs_gpio_update_bits(RS_GPIO_INTR_LOW_ENABLE_OFFSET, mask, true);
    }
}

rs_status_t rs_gpio_get_capabilities(rs_gpio_capabilities_t *capabilities) {
    if (capabilities == NULL) {
        return RS_EINVAL;
    }
    capabilities->version = RS_GPIO_REG(RS_GPIO_IP_VERSION_OFFSET);
    capabilities->features = RS_GPIO_REG(RS_GPIO_CAPABILITY_OFFSET);
    capabilities->pad_features = RS_GPIO_REG(RS_GPIO_PAD_CAPABILITY_OFFSET);
    return RS_OK;
}

rs_status_t rs_gpio_configure(uint32_t pin, const rs_gpio_config_t *config) {
    uint32_t mask;
    rs_status_t status;

    if ((pin >= RS_GPIO_PIN_COUNT) || !rs_gpio_config_valid(config)) {
        return RS_EINVAL;
    }
    status = rs_gpio_check_pad_capabilities(config);
    if (status != RS_OK) {
        return status;
    }
    mask = UINT32_C(1) << pin;

    RS_GPIO_REG(config->output_high ? RS_GPIO_OUT_SET_OFFSET : RS_GPIO_OUT_CLEAR_OFFSET) = mask;
    rs_gpio_update_bits(RS_GPIO_OPEN_DRAIN_OFFSET, mask, config->open_drain);
    rs_gpio_update_bits(RS_GPIO_INPUT_CMOS_OFFSET, mask, config->input_cmos);
    rs_gpio_update_bits(RS_GPIO_PULL_UP_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_PULL_DOWN_OFFSET, mask, false);
    if (config->pull == RS_GPIO_PULL_UP) {
        rs_gpio_update_bits(RS_GPIO_PULL_UP_OFFSET, mask, true);
    } else if (config->pull == RS_GPIO_PULL_DOWN) {
        rs_gpio_update_bits(RS_GPIO_PULL_DOWN_OFFSET, mask, true);
    } else {
        /* No pull requested. */
    }

    rs_gpio_configure_trigger(mask, config->trigger);
    rs_gpio_update_bits(RS_GPIO_FILTER_ENABLE_OFFSET, mask, config->filter_enable);
    rs_gpio_update_bits(RS_GPIO_INTR_ENABLE_OFFSET, mask, config->interrupt_enable);

    rs_gpio_update_bits(RS_GPIO_USER_SELECT_OFFSET, mask, config->mode == RS_GPIO_MODE_USER_IP);
    rs_gpio_update_bits(RS_GPIO_ALT_SELECT_OFFSET, mask, config->mode == RS_GPIO_MODE_ALT1);
    rs_gpio_update_bits(RS_GPIO_ALT_ENABLE_OFFSET, mask,
                        (config->mode == RS_GPIO_MODE_ALT0) || (config->mode == RS_GPIO_MODE_ALT1));

    if (config->mode == RS_GPIO_MODE_OUTPUT) {
        RS_GPIO_REG(RS_GPIO_OE_SET_OFFSET) = mask;
    } else {
        RS_GPIO_REG(RS_GPIO_OE_CLEAR_OFFSET) = mask;
    }
    return RS_OK;
}

rs_status_t rs_gpio_read(uint32_t pin, bool *high) {
    if ((pin >= RS_GPIO_PIN_COUNT) || (high == NULL)) {
        return RS_EINVAL;
    }
    *high = (RS_GPIO_REG(RS_GPIO_DATA_IN_OFFSET) & (UINT32_C(1) << pin)) != 0U;
    return RS_OK;
}

rs_status_t rs_gpio_write(uint32_t pin, bool high) {
    if (pin >= RS_GPIO_PIN_COUNT) {
        return RS_EINVAL;
    }
    RS_GPIO_REG(high ? RS_GPIO_OUT_SET_OFFSET : RS_GPIO_OUT_CLEAR_OFFSET) = UINT32_C(1) << pin;
    return RS_OK;
}

rs_status_t rs_gpio_toggle(uint32_t pin) {
    if (pin >= RS_GPIO_PIN_COUNT) {
        return RS_EINVAL;
    }
    RS_GPIO_REG(RS_GPIO_OUT_TOGGLE_OFFSET) = UINT32_C(1) << pin;
    return RS_OK;
}

rs_status_t rs_gpio_port_read(uint32_t *value) {
    if (value == NULL) {
        return RS_EINVAL;
    }
    *value = RS_GPIO_REG(RS_GPIO_DATA_IN_OFFSET);
    return RS_OK;
}

rs_status_t rs_gpio_port_set(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_OUT_SET_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_port_clear(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_OUT_CLEAR_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_port_toggle(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_OUT_TOGGLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_interrupt_state(uint32_t *state) {
    if (state == NULL) {
        return RS_EINVAL;
    }
    *state = RS_GPIO_REG(RS_GPIO_INTR_STATE_OFFSET);
    return RS_OK;
}

rs_status_t rs_gpio_interrupt_enable(uint32_t mask, bool enable) {
    rs_gpio_update_bits(RS_GPIO_INTR_ENABLE_OFFSET, mask, enable);
    return RS_OK;
}

rs_status_t rs_gpio_interrupt_clear(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_interrupt_test(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_filter_configure(uint32_t enable_mask, const rs_gpio_filter_timing_t *timing) {
    if ((timing == NULL) || (timing->stable_samples == 0U) || (timing->stable_samples > 15U)) {
        return RS_EINVAL;
    }
    RS_GPIO_REG(RS_GPIO_FILTER_ENABLE_OFFSET) = 0U;
    RS_GPIO_REG(RS_GPIO_FILTER_DIV_OFFSET) = timing->divider;
    RS_GPIO_REG(RS_GPIO_FILTER_COUNT_OFFSET) = timing->stable_samples;
    RS_GPIO_REG(RS_GPIO_FILTER_ENABLE_OFFSET) = enable_mask;
    return RS_OK;
}

rs_status_t rs_gpio_user_access_set(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_USER_ACCESS_MASK_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_user_ip_select(uint32_t mask, bool enable) {
    rs_gpio_update_bits(RS_GPIO_USER_SELECT_OFFSET, mask, enable);
    return RS_OK;
}

rs_status_t rs_gpio_user_ip_lock(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_USER_LOCK_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_gpio_configuration_lock(uint32_t mask) {
    RS_GPIO_REG(RS_GPIO_CONFIG_LOCK_OFFSET) = mask;
    return RS_OK;
}

static rs_status_t rs_gpio_user_wait(uint32_t offset, uint32_t mask, uint32_t expected,
                                     rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        if ((RS_GPIO_REG(offset) & mask) == expected) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static void rs_gpio_user_native_fallback(uint32_t mask) {
    rs_gpio_update_bits(RS_GPIO_INTR_RISE_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_FALL_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_HIGH_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_LOW_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_INTR_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_FILTER_ENABLE_OFFSET, mask, false);
    rs_gpio_update_bits(RS_GPIO_ALT_ENABLE_OFFSET, mask, false);
    RS_GPIO_REG(RS_GPIO_OE_CLEAR_OFFSET) = mask;
}

static void rs_gpio_user_select_update(uint32_t mask, bool set) {
    rs_gpio_update_bits(RS_GPIO_USER_SELECT_OFFSET, mask, set);
#ifdef RS_GPIO_TEST_MMIO
    extern void rs_gpio_test_user_select_write(uint32_t value);
    rs_gpio_test_user_select_write(RS_GPIO_REG(RS_GPIO_USER_SELECT_OFFSET));
#endif
}

rs_status_t rs_gpio_user_acquire(uint32_t claim_mask, uint32_t output_mask, rs_timeout_t timeout) {
    if ((timeout == 0U) || ((output_mask & ~claim_mask) != 0U)) {
        return RS_EINVAL;
    }
    if (((RS_GPIO_REG(RS_GPIO_CONFIG_LOCK_OFFSET) & claim_mask) != 0U) ||
        ((RS_GPIO_REG(RS_GPIO_USER_LOCK_OFFSET) & claim_mask) != 0U) ||
        ((RS_GPIO_REG(RS_GPIO_USER_SELECT_OFFSET) & claim_mask) != 0U) ||
        ((RS_GPIO_REG(RS_GPIO_OPEN_DRAIN_OFFSET) & output_mask) != 0U)) {
        return RS_EIO;
    }
    rs_gpio_user_native_fallback(claim_mask);
    rs_gpio_user_select_update(claim_mask, true);
    if (rs_gpio_user_wait(RS_GPIO_USER_STATUS_OFFSET, claim_mask, claim_mask, timeout) != RS_OK) {
        rs_gpio_user_native_fallback(claim_mask);
        rs_gpio_user_select_update(claim_mask, false);
        (void)rs_gpio_user_wait(RS_GPIO_USER_SELECT_OFFSET, claim_mask, 0U, timeout);
        return RS_EIO;
    }
    return RS_OK;
}

rs_status_t rs_gpio_user_release(uint32_t claim_mask, rs_timeout_t timeout) {
    if (timeout == 0U) {
        return RS_EINVAL;
    }
    if ((RS_GPIO_REG(RS_GPIO_CONFIG_LOCK_OFFSET) & claim_mask) != 0U ||
        (RS_GPIO_REG(RS_GPIO_USER_LOCK_OFFSET) & claim_mask) != 0U) {
        return RS_EIO;
    }
    if ((RS_GPIO_REG(RS_GPIO_USER_SELECT_OFFSET) & claim_mask) != claim_mask) {
        return RS_EIO;
    }
    rs_gpio_user_native_fallback(claim_mask);
    rs_gpio_user_select_update(claim_mask, false);
    if (rs_gpio_user_wait(RS_GPIO_USER_SELECT_OFFSET, claim_mask, 0U, timeout) != RS_OK) {
        return RS_EIO;
    }
    return RS_OK;
}

void rs_gpio_shell_test(int argc, char **argv) {
    const rs_gpio_config_t config = {
        RS_GPIO_MODE_OUTPUT,
        RS_GPIO_PULL_NONE,
        RS_GPIO_TRIGGER_NONE,
        false,
        false,
        false,
        false,
        false,
    };

    (void)argc;
    (void)argv;
    printf("gpio test\n");
    if (rs_gpio_configure(0U, &config) != RS_OK) {
        printf("gpio configuration failed\n");
        return;
    }
    for (uint32_t iteration = 0U; iteration < 10U; ++iteration) {
        (void)rs_gpio_toggle(0U);
        if (rs_timer_delay_ms(RS_TIMER_0, 300U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            printf("gpio timer delay failed\n");
            return;
        }
    }
    (void)rs_gpio_write(0U, false);
    printf("gpio test passed\n");
}
