#include <firmware.h>
#include <tinyprintf.h>
#include <tiny1wire.h>
#include <tinytim.h>


void ip_1wire_test(int argc, char **argv) {
    (void) argc;
    (void) argv;
    printf("1-wire test\n");

    reg_onewire_clkdiv = (uint8_t)90;
    reg_onewire_zerocnt = (uint8_t)24;
    reg_onewire_onecnt = (uint8_t)45;
    reg_onewire_rstcnt = (uint8_t)6;

    for(int num = 0; num < 6; ++num) {
        for(int i = 0; i < 256; ++i) {
            // clear fifo
            reg_onewire_ctrl = (uint8_t)0b01;
            // write data(GRB888 format)
            reg_onewire_txdata = (uint32_t) i;
            reg_onewire_txdata = (uint32_t) (i << 8);
            reg_onewire_txdata = (uint32_t) (i << 16);
            reg_onewire_txdata = (uint32_t) ((i << 8) | (i << 16));
            reg_onewire_ctrl = (uint8_t)0b10;
            while(!(reg_onewire_status == (uint32_t)5));
            delay_ms(5);
        }
    }

    reg_onewire_ctrl = (uint8_t)0b01;
    reg_onewire_txdata = (uint32_t) 0;
    reg_onewire_txdata = (uint32_t) 0;
    reg_onewire_txdata = (uint32_t) 0;
    reg_onewire_txdata = (uint32_t) 0;
    reg_onewire_ctrl = (uint8_t)0b10;
    printf("1-wire test done\n");
}