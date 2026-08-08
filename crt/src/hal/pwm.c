#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/pwm.h>

void ip_pwm_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("[APB IP] pwm test\n");

    reg_pwm_ctrl = (uint32_t)0;
    reg_pwm_pscr = (uint32_t)(CPU_FREQ - 1); // 'CPU_FREQ' MHz for 1MHz
    reg_pwm_cmp = (uint32_t)(1000 - 1);      // 1KHz
    printf("reg_pwm_ctrl: %d reg_pwm_pscr: %d reg_pwm_cmp: %d\n", reg_pwm_ctrl, reg_pwm_pscr,
           reg_pwm_cmp);
    for (int i = 0; i < 6; i++) {
        for (int j = 10; j <= 990; ++j) {
            reg_pwm_ctrl = (uint32_t)4;
            reg_pwm_cr0 = j;
            reg_pwm_ctrl = (uint32_t)3;
            reg_pwm_pscr = 49;
            if (rs_timer_delay_ms(RS_TIMER_0, 1U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
                printf("timer delay failed\n");
                return;
            }
        }

        for (int j = 990; j >= 10; --j) {
            reg_pwm_ctrl = (uint32_t)4;
            reg_pwm_cr0 = j;
            reg_pwm_ctrl = (uint32_t)3;
            reg_pwm_pscr = 49;
            if (rs_timer_delay_ms(RS_TIMER_0, 1U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
                printf("timer delay failed\n");
                return;
            }
        }
        printf("[PWM]: %d/6\n", i + 1);
    }
}
