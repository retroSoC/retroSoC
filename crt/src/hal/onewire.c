#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/onewire.h>
#include <retrosoc/hal/timer.h>

void ip_1wire_test(int argc, char **argv) {
    (void)argc;
    (void)argv;
    printf("1-wire test\n");

    reg_onewire_clkdiv = (uint8_t)(CPU_FREQ / 0.8); // 72M 90
    reg_onewire_zerocnt = (uint8_t)(CPU_FREQ / 3);  // 72M 24
    reg_onewire_onecnt = (uint8_t)(CPU_FREQ / 1.6); // 72M 45
    reg_onewire_rstcnt = (uint8_t)(CPU_FREQ / 12);  // 72M 6

    for (uint32_t num = 0U; num < 6U; ++num) {
        for (uint32_t i = 0U; i < 256U; ++i) {
            // clear fifo
            reg_onewire_ctrl = (uint8_t)0b01;
            // write data(GRB888 format)
            reg_onewire_txdata = (uint32_t)i;
            reg_onewire_txdata = (uint32_t)(i << 8);
            reg_onewire_txdata = (uint32_t)(i << 16);
            reg_onewire_txdata = (uint32_t)((i << 8) | (i << 16));
            reg_onewire_ctrl = (uint8_t)0b10;
            if (rs_wait_value(&reg_onewire_status, 5U, RS_TIMEOUT_DEFAULT) != RS_OK) {
                printf("1-wire transfer timed out\n");
                return;
            }
            delay_ms(5);
        }
    }

    reg_onewire_ctrl = (uint8_t)0b01;
    reg_onewire_txdata = (uint32_t)0;
    reg_onewire_txdata = (uint32_t)0;
    reg_onewire_txdata = (uint32_t)0;
    reg_onewire_txdata = (uint32_t)0;
    reg_onewire_ctrl = (uint8_t)0b10;
    printf("1-wire test done\n");
}
