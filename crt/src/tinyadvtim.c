#include <firmware.h>
#include <tinyprintf.h>
#include <tinyadvtim.h>

void advtimer_init(uint32_t div, uint32_t cmp) {
    reg_tim3_ctrl = (uint32_t)0x0;
    while(reg_tim3_stat == 1); // clear irq
    reg_tim3_pscr = div - 1;
    reg_tim3_cmp  = cmp - 1;
    printf("CTRL: %d PSCR: %d CMP: %d\n", reg_tim3_ctrl, reg_tim3_pscr, reg_tim3_cmp);
}

void advtimer_delay(uint32_t val) {
    reg_tim3_ctrl = (uint32_t)0xD;
    for(uint32_t i = 0; i < val; ++i) {
        while(reg_tim3_stat == 0);
    }
    reg_tim3_ctrl = (uint32_t)0x0;
}

void ip_advtim_test() {
    printf("[APB IP] adv timer test\n");
    // 'CPU_FREQ' MHz for 1ms
    printf("no div test start\n");
    advtimer_init(1, CPU_FREQ * 1000);
    // advtimer_init(1, 100); // for rtl simu
    for(int i = 1; i <= 10; ++i) {
        advtimer_delay(1000);
        printf("delay 1s\n");
    }
    printf("no div test done\n");
    printf("div test start\n");
    // 'CPU_FREQ' MHz for 1s
    advtimer_init(CPU_FREQ, 1000000);
    // advtimer_init(100, 10); // for soc
    for(int i = 1; i <= 10; ++i) {
        advtimer_delay(1);
        printf("delay 1s\n");
    }
    printf("CTRL: %d PSCR: %d CMP: %d\n", reg_tim3_ctrl, reg_tim3_pscr, reg_tim3_cmp);
}