#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clock.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/lib/printf.h>

#define RS_TIMER_CTRL_OFFSET               UINT32_C(0x000)
#define RS_TIMER_LOAD_OFFSET               UINT32_C(0x004)
#define RS_TIMER_VALUE_OFFSET              UINT32_C(0x008)
#define RS_TIMER_BGLOAD_OFFSET             UINT32_C(0x00C)
#define RS_TIMER_PRESCALE_OFFSET           UINT32_C(0x010)
#define RS_TIMER_COMPARE0_OFFSET           UINT32_C(0x014)
#define RS_TIMER_COMPARE1_OFFSET           UINT32_C(0x018)
#define RS_TIMER_STATUS_OFFSET             UINT32_C(0x01C)
#define RS_TIMER_INTR_STATE_OFFSET         UINT32_C(0x020)
#define RS_TIMER_INTR_ENABLE_OFFSET        UINT32_C(0x024)
#define RS_TIMER_INTR_TEST_OFFSET          UINT32_C(0x02C)

#define RS_TIMER_CTRL_ENABLE_SHIFT         0U
#define RS_TIMER_CTRL_MODE_SHIFT           1U
#define RS_TIMER_CTRL_DIRECTION_SHIFT      3U
#define RS_TIMER_CTRL_ENABLE_MASK          UINT32_C(0x00000001)
#define RS_TIMER_CTRL_DEBUG_FREEZE_MASK    UINT32_C(0x00000010)
#define RS_TIMER_CTRL_COMPARE0_ENABLE_MASK UINT32_C(0x00000020)
#define RS_TIMER_CTRL_COMPARE1_ENABLE_MASK UINT32_C(0x00000040)
#define RS_TIMER_STATUS_ACTIVE_MASK        UINT32_C(0x00000001)
#define RS_TIMER_STATUS_DEBUG_FROZEN_MASK  UINT32_C(0x00000002)

static bool rs_timer_id_valid(rs_timer_id_t timer) {
    return (timer == RS_TIMER_0) || (timer == RS_TIMER_1);
}

static uintptr_t rs_timer_base(rs_timer_id_t timer) {
    return timer == RS_TIMER_0 ? RS_SOC_RIBP_TIM0_BASE : RS_SOC_RIBP_TIM1_BASE;
}

static volatile uint32_t *rs_timer_register(rs_timer_id_t timer, uint32_t offset) {
    return (volatile uint32_t *)(rs_timer_base(timer) + (uintptr_t)offset);
}

static uint32_t rs_timer_ctrl_from_config(const rs_timer_config_t *config) {
    uint32_t control = ((uint32_t)config->mode << RS_TIMER_CTRL_MODE_SHIFT) |
                       ((uint32_t)config->direction << RS_TIMER_CTRL_DIRECTION_SHIFT);

    if (config->freeze_in_debug) {
        control |= RS_TIMER_CTRL_DEBUG_FREEZE_MASK;
    }
    if (config->compare0_enable) {
        control |= RS_TIMER_CTRL_COMPARE0_ENABLE_MASK;
    }
    if (config->compare1_enable) {
        control |= RS_TIMER_CTRL_COMPARE1_ENABLE_MASK;
    }
    return control;
}

static bool rs_timer_config_valid(const rs_timer_config_t *config) {
    return (config != NULL) && ((uint32_t)config->mode <= (uint32_t)RS_TIMER_MODE_ONE_SHOT) &&
           ((uint32_t)config->direction <= (uint32_t)RS_TIMER_DIRECTION_DOWN) &&
           ((config->interrupt_enable & ~RS_TIMER_INTERRUPT_ALL) == 0U);
}

rs_status_t rs_timer_configure(rs_timer_id_t timer, const rs_timer_config_t *config) {
    volatile uint32_t *control;
    uint32_t control_value;

    if (!rs_timer_id_valid(timer) || !rs_timer_config_valid(config)) {
        return RS_EINVAL;
    }

    control = rs_timer_register(timer, RS_TIMER_CTRL_OFFSET);
    *control &= ~RS_TIMER_CTRL_ENABLE_MASK;
    control_value = rs_timer_ctrl_from_config(config);
    *control = control_value;
    *rs_timer_register(timer, RS_TIMER_PRESCALE_OFFSET) = (uint32_t)config->prescale;
    *rs_timer_register(timer, RS_TIMER_COMPARE0_OFFSET) = config->compare0;
    *rs_timer_register(timer, RS_TIMER_COMPARE1_OFFSET) = config->compare1;
    *rs_timer_register(timer, RS_TIMER_LOAD_OFFSET) = config->load;
    *rs_timer_register(timer, RS_TIMER_INTR_STATE_OFFSET) = RS_TIMER_INTERRUPT_ALL;
    *rs_timer_register(timer, RS_TIMER_INTR_ENABLE_OFFSET) = config->interrupt_enable;
    return RS_OK;
}

rs_status_t rs_timer_start(rs_timer_id_t timer) {
    volatile uint32_t *control;

    if (!rs_timer_id_valid(timer)) {
        return RS_EINVAL;
    }
    control = rs_timer_register(timer, RS_TIMER_CTRL_OFFSET);
    *control |= RS_TIMER_CTRL_ENABLE_MASK;
    return RS_OK;
}

rs_status_t rs_timer_stop(rs_timer_id_t timer) {
    volatile uint32_t *control;

    if (!rs_timer_id_valid(timer)) {
        return RS_EINVAL;
    }
    control = rs_timer_register(timer, RS_TIMER_CTRL_OFFSET);
    *control &= ~RS_TIMER_CTRL_ENABLE_MASK;
    return RS_OK;
}

rs_status_t rs_timer_set_load(rs_timer_id_t timer, uint32_t load) {
    if (!rs_timer_id_valid(timer)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, RS_TIMER_LOAD_OFFSET) = load;
    return RS_OK;
}

rs_status_t rs_timer_set_background_load(rs_timer_id_t timer, uint32_t load) {
    if (!rs_timer_id_valid(timer)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, RS_TIMER_BGLOAD_OFFSET) = load;
    return RS_OK;
}

rs_status_t rs_timer_set_compare(rs_timer_id_t timer, uint32_t channel, uint32_t compare) {
    if (!rs_timer_id_valid(timer) || (channel > 1U)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, channel == 0U ? RS_TIMER_COMPARE0_OFFSET : RS_TIMER_COMPARE1_OFFSET) =
        compare;
    return RS_OK;
}

rs_status_t rs_timer_get_value(rs_timer_id_t timer, uint32_t *value) {
    if (!rs_timer_id_valid(timer) || (value == NULL)) {
        return RS_EINVAL;
    }
    *value = *rs_timer_register(timer, RS_TIMER_VALUE_OFFSET);
    return RS_OK;
}

rs_status_t rs_timer_get_status(rs_timer_id_t timer, rs_timer_status_t *status) {
    uint32_t value;

    if (!rs_timer_id_valid(timer) || (status == NULL)) {
        return RS_EINVAL;
    }
    value = *rs_timer_register(timer, RS_TIMER_STATUS_OFFSET);
    status->value = *rs_timer_register(timer, RS_TIMER_VALUE_OFFSET);
    status->interrupt_state = *rs_timer_register(timer, RS_TIMER_INTR_STATE_OFFSET);
    status->active = (value & RS_TIMER_STATUS_ACTIVE_MASK) != 0U;
    status->debug_frozen = (value & RS_TIMER_STATUS_DEBUG_FROZEN_MASK) != 0U;
    return RS_OK;
}

rs_status_t rs_timer_interrupt_enable(rs_timer_id_t timer, uint32_t mask) {
    if (!rs_timer_id_valid(timer) || ((mask & ~RS_TIMER_INTERRUPT_ALL) != 0U)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, RS_TIMER_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_timer_interrupt_clear(rs_timer_id_t timer, uint32_t mask) {
    if (!rs_timer_id_valid(timer) || ((mask & ~RS_TIMER_INTERRUPT_ALL) != 0U)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, RS_TIMER_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_timer_interrupt_test(rs_timer_id_t timer, uint32_t mask) {
    if (!rs_timer_id_valid(timer) || ((mask & ~RS_TIMER_INTERRUPT_ALL) != 0U)) {
        return RS_EINVAL;
    }
    *rs_timer_register(timer, RS_TIMER_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_timer_delay_ms(rs_timer_id_t timer, uint32_t milliseconds, rs_timeout_t timeout) {
    rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_ONE_SHOT,
        .direction = RS_TIMER_DIRECTION_DOWN,
        .prescale = 0U,
        .load = 0U,
        .compare0 = 0U,
        .compare1 = 0U,
        .interrupt_enable = 0U,
        .freeze_in_debug = true,
        .compare0_enable = false,
        .compare1_enable = false,
    };
    rs_timer_period_t period;
    uint32_t frequency_hz;

    if (!rs_timer_id_valid(timer)) {
        return RS_EINVAL;
    }
    if (milliseconds == 0U) {
        return RS_OK;
    }
    if ((rs_clock_get_active_hz(&frequency_hz) != RS_OK) ||
        (rs_timer_period_from_ms(frequency_hz, milliseconds, &period) != RS_OK)) {
        return RS_EINVAL;
    }
    config.prescale = period.prescale;
    config.load = period.load;
    if ((rs_timer_configure(timer, &config) != RS_OK) || (rs_timer_start(timer) != RS_OK)) {
        return RS_EIO;
    }

    while (timeout-- != 0U) {
        if ((*rs_timer_register(timer, RS_TIMER_STATUS_OFFSET) & RS_TIMER_STATUS_ACTIVE_MASK) ==
            0U) {
            return RS_OK;
        }
    }
    (void)rs_timer_stop(timer);
    return RS_ETIMEOUT;
}

void rs_timer_shell_test(int argc, char **argv) {
    rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_PERIODIC,
        .direction = RS_TIMER_DIRECTION_UP,
        .prescale = 0U,
        .load = UINT32_C(0x00FFFFFF),
        .compare0 = UINT32_C(0x0000FFFF),
        .compare1 = UINT32_C(0x000FFFFF),
        .interrupt_enable = 0U,
        .freeze_in_debug = true,
        .compare0_enable = true,
        .compare1_enable = true,
    };
    uint32_t value;

    (void)argc;
    (void)argv;
    printf("[RIBP IP] general timer test\n");
    if ((rs_timer_configure(RS_TIMER_1, &config) != RS_OK) ||
        (rs_timer_start(RS_TIMER_1) != RS_OK)) {
        printf("timer configuration failed\n");
        return;
    }
    for (uint32_t index = 0U; index < 10U; ++index) {
        if (rs_timer_get_value(RS_TIMER_1, &value) != RS_OK) {
            printf("timer read failed\n");
            break;
        }
        printf("[timer1 value] %x\n", value);
    }
    (void)rs_timer_stop(RS_TIMER_1);
}
