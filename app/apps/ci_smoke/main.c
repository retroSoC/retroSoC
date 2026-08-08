#include <retrosoc/core/soc.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/service/test.h>

static bool rs_ci_smoke_archinfo_matches_reset_values(void) {
    const uint32_t archinfo_sys = reg_archinfo_sys;
    const uint32_t archinfo_idl = reg_archinfo_idl;
    const uint32_t archinfo_idh = reg_archinfo_idh;

    return (archinfo_sys == UINT32_C(0x000F1010)) && (archinfo_idl == UINT32_C(0xFFFF2022)) &&
           (archinfo_idh == UINT32_C(0x00FFFFFF));
}

static bool rs_ci_smoke_clint_standard_map(void) {
    uint64_t first;
    uint64_t current;
    uint64_t compare;
    bool pending;

    if (rs_clint_get_time(&first) != RS_OK) {
        return false;
    }
    current = first;
    for (rs_timeout_t timeout = 512U; (timeout != 0U) && (current == first); --timeout) {
        if (rs_clint_get_time(&current) != RS_OK) {
            return false;
        }
    }
    if ((current <= first) || (rs_clint_set_compare(0U, current + UINT64_C(1000)) != RS_OK) ||
        (rs_clint_get_compare(0U, &compare) != RS_OK) || (compare != (current + UINT64_C(1000)))) {
        return false;
    }
    if ((rs_clint_set_software_interrupt(0U, true) != RS_OK) ||
        (rs_clint_get_software_interrupt(0U, &pending) != RS_OK) || !pending ||
        (rs_clint_set_software_interrupt(0U, false) != RS_OK) ||
        (rs_clint_get_software_interrupt(0U, &pending) != RS_OK) || pending) {
        return false;
    }
    return rs_clint_set_compare(0U, UINT64_MAX) == RS_OK;
}

static bool rs_ci_smoke_timer_one_shot(void) {
    const rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_ONE_SHOT,
        .direction = RS_TIMER_DIRECTION_DOWN,
        .prescale = 0U,
        .load = 8U,
        .compare0 = 4U,
        .compare1 = 0U,
        .interrupt_enable = RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0,
        .freeze_in_debug = true,
        .compare0_enable = true,
        .compare1_enable = false,
    };
    rs_timer_status_t status;

    if ((rs_timer_configure(RS_TIMER_0, &config) != RS_OK) ||
        (rs_timer_start(RS_TIMER_0) != RS_OK)) {
        return false;
    }
    for (rs_timeout_t timeout = 1000U; timeout != 0U; --timeout) {
        if (rs_timer_get_status(RS_TIMER_0, &status) != RS_OK) {
            return false;
        }
        if (!status.active) {
            return (status.value == 0U) &&
                   ((status.interrupt_state &
                     (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0)) ==
                    (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE0));
        }
    }
    return false;
}

static bool rs_ci_smoke_timer_periodic(void) {
    const rs_timer_config_t config = {
        .mode = RS_TIMER_MODE_PERIODIC,
        .direction = RS_TIMER_DIRECTION_UP,
        .prescale = 0U,
        .load = 7U,
        .compare0 = 0U,
        .compare1 = 3U,
        .interrupt_enable = RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1,
        .freeze_in_debug = true,
        .compare0_enable = false,
        .compare1_enable = true,
    };
    rs_timer_status_t status;
    bool passed = false;

    if ((rs_timer_configure(RS_TIMER_1, &config) != RS_OK) ||
        (rs_timer_start(RS_TIMER_1) != RS_OK)) {
        return false;
    }
    for (rs_timeout_t timeout = 1000U; timeout != 0U; --timeout) {
        if (rs_timer_get_status(RS_TIMER_1, &status) != RS_OK) {
            break;
        }
        if ((status.interrupt_state & (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1)) ==
            (RS_TIMER_INTERRUPT_TIMEOUT | RS_TIMER_INTERRUPT_COMPARE1)) {
            passed = true;
            break;
        }
    }
    if (rs_timer_stop(RS_TIMER_1) != RS_OK) {
        return false;
    }
    return passed;
}

int main(void) {
    uart0_init(CPU_FREQ, UART_BPS);

    if (!rs_ci_smoke_archinfo_matches_reset_values()) {
        rs_test_finish(RS_TEST_FAILED, 1U);
    }
    if (!rs_ci_smoke_clint_standard_map()) {
        rs_test_finish(RS_TEST_FAILED, 2U);
    }
    if (!rs_ci_smoke_timer_one_shot()) {
        rs_test_finish(RS_TEST_FAILED, 3U);
    }
    if (!rs_ci_smoke_timer_periodic()) {
        rs_test_finish(RS_TEST_FAILED, 4U);
    }

    printf("ci_smoke: archinfo, CLINT, and timer tests passed\n");
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
