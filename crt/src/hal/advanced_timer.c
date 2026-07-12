#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/advanced_timer.h>

#define RS_ADVTIMER_LONG_TIMEOUT (RS_TIMEOUT_DEFAULT * 100U)

static rs_status_t rs_advtimer_init(uint32_t div, uint32_t cmp) {
    if ((div == 0U) || (cmp == 0U)) {
        return RS_EINVAL;
    }
    reg_tim3_ctrl = (uint32_t)0x0;
    if (rs_wait_value(&reg_tim3_stat, 0U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        return RS_ETIMEOUT;
    }
    reg_tim3_pscr = div - 1;
    reg_tim3_cmp = cmp - 1;
    printf("CTRL: %d PSCR: %d CMP: %d\n", reg_tim3_ctrl, reg_tim3_pscr, reg_tim3_cmp);
    return RS_OK;
}

static rs_status_t rs_advtimer_delay(uint32_t val, rs_timeout_t timeout) {
    reg_tim3_ctrl = (uint32_t)0xD;
    for (uint32_t i = 0U; i < val; ++i) {
        if (rs_wait_value(&reg_tim3_stat, 1U, timeout) != RS_OK) {
            reg_tim3_ctrl = (uint32_t)0x0;
            return RS_ETIMEOUT;
        }
    }
    reg_tim3_ctrl = (uint32_t)0x0;
    return RS_OK;
}

void ip_advtim_test(void) {
    printf("[APB IP] adv timer test\n");
    // 'CPU_FREQ' MHz for 1ms
    printf("no div test start\n");
    if (rs_advtimer_init(1U, CPU_FREQ * 1000U) != RS_OK) {
        printf("advanced timer initialization timed out\n");
        return;
    }
    // advtimer_init(1, 100); // for rtl simu
    for (uint32_t i = 1U; i <= 10U; ++i) {
        if (rs_advtimer_delay(1000U, RS_TIMEOUT_DEFAULT) != RS_OK) {
            printf("advanced timer delay timed out\n");
            return;
        }
        printf("delay 1s\n");
    }
    printf("no div test done\n");
    printf("div test start\n");
    // 'CPU_FREQ' MHz for 1s
    if (rs_advtimer_init(CPU_FREQ, 1000000U) != RS_OK) {
        printf("advanced timer initialization timed out\n");
        return;
    }
    // advtimer_init(100, 10); // for soc
    for (uint32_t i = 1U; i <= 10U; ++i) {
        if (rs_advtimer_delay(1U, RS_ADVTIMER_LONG_TIMEOUT) != RS_OK) {
            printf("advanced timer delay timed out\n");
            return;
        }
        printf("delay 1s\n");
    }
    printf("CTRL: %d PSCR: %d CMP: %d\n", reg_tim3_ctrl, reg_tim3_pscr, reg_tim3_cmp);
}
