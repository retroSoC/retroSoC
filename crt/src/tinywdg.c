#include <firmware.h>
#include <tinyprintf.h>
#include <tinywdg.h>

void ip_wdg_test() {
    printf("[APB IP] wdg test\n");

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_ctrl = (uint32_t)0x0;

    // feed wdg in every 50ms
    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_pscr = (uint32_t)(CPU_FREQ - 1);  // div/'CPU_FREQ' for 1MHz

    reg_wdg_key = WDG_MAGIC_NUM;

    reg_wdg_cmp = (uint32_t)(50000 - 1);  // overflow in every 50ms
    // reg_wdg_cmp = (uint32_t)(500 - 1);  // overflow in every 500ns

    while(reg_wdg_stat == (uint32_t)0x1); // clear irq flag

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_ctrl = (uint32_t) 0b101;      // core and ov trg en

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_feed = (uint32_t) 0x1;
    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_feed = (uint32_t) 0x0;

    for(int i = 0; i < 10; ++i) {
        printf("reg_wdg_pscr: %d\n", reg_wdg_pscr);
        while(reg_wdg_stat == (uint32_t)0);
        printf("%d wdg reset trigger\n", i);
    }
}