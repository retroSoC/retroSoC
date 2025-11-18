#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>

void delay_ms(uint32_t val) {
    reg_tim0_val = (uint32_t)(CPU_FREQ * val * 1000 - 1);
    reg_tim0_cfg = (uint32_t)0b0011; // irq disable, count down, oneshot mode, timer enable
    while (reg_tim0_val);
    reg_tim0_cfg = (uint32_t)0b0000;
}

void tim1_init() {
    reg_tim1_cfg = (uint32_t)0b0000;
    reg_tim1_rld = (uint32_t)0xFFFFFFFF;
    reg_tim1_val = (uint32_t)0;
    // printf("tim1 cfg: %x\n", reg_tim1_cfg);
    // printf("tim1 rld: %x\n", reg_tim1_rld);
    // printf("tim1 val: %x\n", reg_tim1_val);
    reg_tim1_cfg = (uint32_t)0b0111;
    // printf("tim1 cfg: %d\n", reg_tim1_cfg);
}

uint32_t tim1_get_value() {
    return reg_tim1_val;
}

void ip_tim_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("[NATV IP] counter timer test\n");
    printf("[tim0 reload] %x\n", reg_tim0_rld);
    printf("[tim0 config] %x\n", reg_tim0_cfg);
    printf("[tim1 reload] %x\n", reg_tim1_rld);
    printf("[tim1 config] %x\n", reg_tim1_cfg);

    reg_tim0_rld = (uint32_t)0xffffffff;
    reg_tim0_cfg = (uint32_t)0x0001; // irq disable, count down, continuous mode, timer enable

    reg_tim1_rld = (uint32_t)0x00ffffff;
    reg_tim1_cfg = (uint32_t)0x0101; // irq disable, count up, continuous mode, timer enable

    for (int i = 0; i < 10; ++i) {
        printf("[tim0 val] %x\n", reg_tim0_val);
        printf("[tim1 val] %x\n", reg_tim1_val);
    }
}