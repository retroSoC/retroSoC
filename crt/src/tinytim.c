#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>

// 0x0011 = 0b0000000000010001
void delay_ms(uint32_t val) {
    reg_tim0_dat = (uint32_t)(CPU_FREQ * val * 1000 - 1);
    reg_tim0_cfg = (uint32_t)0b0011; // irq disable, count down, oneshot mode, timer enable
    while (reg_tim0_dat);
    reg_tim0_cfg = (uint32_t)0b0000;
}

void ip_tim_test() {
    printf("[NATV IP] counter timer test\n");
    printf("[TIM0 VALUE]  %x\n", reg_tim0_val);
    printf("[TIM0 CONFIG] %x\n", reg_tim0_cfg);
    printf("[TIM1 VALUE]  %x\n", reg_tim1_val);
    printf("[TIM1 CONFIG] %x\n", reg_tim1_cfg);

    reg_tim0_val = (uint32_t)0xffffffff;
    reg_tim0_cfg = (uint32_t)0x0001; // irq disable, count down, continuous mode, timer enable

    reg_tim1_val = (uint32_t)0x00ffffff;
    reg_tim1_cfg = (uint32_t)0x0101; // irq disable, count up, continuous mode, timer enable

    for (int i = 0; i < 10; ++i) {
        printf("[TIM0 DATA] %x\n", reg_tim0_dat);
        printf("[TIM1 DATA] %x\n", reg_tim1_dat);
    }
}