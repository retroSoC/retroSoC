#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/watchdog.h>

#define RS_WDG_WAIT_TIMEOUT (RS_TIMEOUT_DEFAULT * 16U)

void ip_wdg_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("[APB IP] wdg test\n");

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_ctrl = (uint32_t)0x0;

    // feed wdg in every 50ms
    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_pscr = (uint32_t)(CPU_FREQ - 1); // div/'CPU_FREQ' for 1MHz

    reg_wdg_key = WDG_MAGIC_NUM;

    reg_wdg_cmp = (uint32_t)(50000 - 1); // overflow in every 50ms
    // reg_wdg_cmp = (uint32_t)(500 - 1);  // overflow in every 500ns

    if (rs_wait_not_value(&reg_wdg_stat, 1U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("watchdog status did not clear\n");
        return;
    }

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_ctrl = (uint32_t)0b101; // core and ov trg en

    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_feed = (uint32_t)0x1;
    reg_wdg_key = WDG_MAGIC_NUM;
    reg_wdg_feed = (uint32_t)0x0;

    for (uint32_t i = 0U; i < 10U; ++i) {
        printf("reg_wdg_pscr: %d\n", reg_wdg_pscr);
        if (rs_wait_not_value(&reg_wdg_stat, 0U, RS_WDG_WAIT_TIMEOUT) != RS_OK) {
            printf("watchdog test timed out\n");
            return;
        }
        printf("%d wdg reset trigger\n", i);
    }
}
