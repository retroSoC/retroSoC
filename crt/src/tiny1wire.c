#include <firmware.h>
#include <tinyprintf.h>
#include <tiny1wire.h>


void ip_1wire_test() {
    printf("1-wire test\n");

    reg_onewire_clkdiv = (uint8_t)90;
    reg_onewire_zerocnt = (uint8_t)24;
    reg_onewire_onecnt = (uint8_t)45;
    reg_onewire_rstcnt = (uint8_t)6;

    for(int i = 0; i < 256; ++i) {
        // clear fifo
        reg_onewire_ctrl = (uint8_t)0b01;
        // write data(GRB888 format)
        reg_onewire_txdata = (uint32_t) i;
        reg_onewire_txdata = (uint32_t) (i << 16);
        reg_onewire_txdata = (uint32_t) (i << 24);
        reg_onewire_txdata = (uint32_t) ((i << 16) | (i << 24));
        reg_onewire_ctrl = (uint8_t)0b10;
        while((reg_onewire_status & ((uint8_t) 1)) == 0);
    }
}