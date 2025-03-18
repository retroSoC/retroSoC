#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
#include <tinypwm.h>

void ip_pwm_test()
{
    printf("pwm test\n");

    reg_cust_pwm_ctrl = (uint32_t)0;
    reg_cust_pwm_pscr = (uint32_t)(CPU_FREQ - 1); // 50M / 50 = 1MHz
    reg_cust_pwm_cmp = (uint32_t)(1000 - 1);      // 1KHz
    printf("reg_cust_pwm_ctrl: %d reg_cust_pwm_pscr: %d reg_cust_pwm_cmp: %d\n", reg_cust_pwm_ctrl, reg_cust_pwm_pscr, reg_cust_pwm_cmp);
    for (int i = 0; i < 36; i++)
    {
        printf("[PWM]: %d/36\n", i + 1);
        for (int j = 10; j <= 990; ++j)
        {
            reg_cust_pwm_ctrl = (uint32_t)4;
            reg_cust_pwm_cr0 = j;
            reg_cust_pwm_ctrl = (uint32_t)3;
            reg_cust_pwm_pscr = 49;
            delay_ms(5);
        }

        for (int j = 990; j >= 10; --j)
        {
            reg_cust_pwm_ctrl = (uint32_t)4;
            reg_cust_pwm_cr0 = j;
            reg_cust_pwm_ctrl = (uint32_t)3;
            reg_cust_pwm_pscr = 49;
            delay_ms(5);
        }
    }
}