#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2s.h>

void ip_i2s_test() {
    // fifo wr mode
    reg_i2s_mode = (uint32_t)1;

    for(uint32_t i = 0; i < 66; i += 2) {
        while(reg_i2s_status & (uint32_t)1); // check if fifo is full or not
        if(i & 1) reg_i2s_txdata = 0x1234;
        else reg_i2s_txdata = 0x5678;
    }
}