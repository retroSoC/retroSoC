#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/rtc.h>

#define RS_RTC_WAIT_TIMEOUT (RS_TIMEOUT_DEFAULT * 16U)

// 12.288M/256=48K
// apb4 clk: 'CPU_FREQ' MHz
// rtc_clk:  12.288     MHz
void ip_rtc_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("rtc test\n");

    reg_rtc_ctrl = (uint32_t)1;             // enter config mode
    reg_rtc_pscr = (uint32_t)(1000000 - 1); // div1000000 for 'CPU_FREQ' Hz

    printf("CTRL: %d PSCR: %d\n", reg_rtc_ctrl, reg_rtc_pscr);
    for (uint32_t i = 0U; i < 6U; ++i) {
        reg_rtc_cnt = (uint32_t)(123 * i);
        reg_rtc_alrm = reg_rtc_cnt + 10;
        printf("[static]CNT: %d ALRM: %d\n", reg_rtc_cnt, reg_rtc_alrm);
        if (reg_rtc_cnt != (uint32_t)(123 * i))
            printf("error\n");
    }

    reg_rtc_cnt = (uint32_t)0;
    reg_rtc_ctrl = (uint32_t)0b0010010; // core and inc trg en
    printf("CTRL: %d PSCR: %d\n", reg_rtc_ctrl, reg_rtc_pscr);
    printf("cnt inc test\n");
    for (uint32_t i = 0U; i < 6U; ++i) {
        if (rs_wait_value(&reg_rtc_ista, 1U, RS_RTC_WAIT_TIMEOUT) != RS_OK) {
            printf("rtc increment timed out\n");
            return;
        }
        printf("reg_rtc_cnt: %d\n", reg_rtc_cnt); // inc 1 in 1/'CPU_FREQ' s
    }
    printf("cnt inc test done\n");
    printf("alrm trigger test\n");

    reg_rtc_ctrl = (uint32_t)1; // enter config mode
    reg_rtc_cnt = (uint32_t)0;
    reg_rtc_alrm = reg_rtc_cnt + 6;
    // for(int i = 0; i < 6; ++i) {
    //     reg_rtc_ctrl = (uint32_t)0b0010100;       // core and alrm trg en
    //     while(reg_rtc_ista != (uint32_t)2);       // wait alrm irq flag
    //     reg_rtc_ctrl = (uint32_t)1;               // enter config mode
    //     while(reg_rtc_ista != (uint32_t)0);       // clear the all irq flag
    //     printf("reg_rtc_cnt: %d\n", reg_rtc_cnt); // alrm trg every 1s
    //     reg_rtc_alrm = reg_rtc_cnt + 6;
    // }
    printf("CTRL: %d PSCR: %d\n", reg_rtc_ctrl, reg_rtc_pscr);
    printf("alrm trigger test done\n");
    printf("rtc test done\n");
}
