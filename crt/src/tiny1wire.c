#include <firmware.h>
#include <tinyprintf.h>
#include <tiny1wire.h>


void ip_1wire_test() {
    printf("1-wire test\n");

    reg_onewire_clkdiv = (uint8_t)90;
    reg_onewire_zerocnt = (uint8_t)24;
    reg_onewire_onecnt = (uint8_t)45;
    reg_onewire_rstnum = (uint8_t)6;

    // clear fifo
    reg_onewire_ctrl = (uint8_t)0b01;
    // write data(GRB888 format)
    reg_onewire_txdata = (uint32_t) 0x00FF0000;
    reg_onewire_txdata = (uint32_t) 0x0000FF00;
    reg_onewire_txdata = (uint32_t) 0x000000FF;
    reg_onewire_txdata = (uint32_t) 0x00FF00FF;

    reg_onewire_ctrl = (uint8_t)0b10;
}