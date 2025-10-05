#include <firmware.h>
#include <tinyprintf.h>
#include <tinyi2s.h>

uint32_t test_data[] = {0x12345678, 0x12345679, 0x1234567A};

void ip_i2s_test() {
    // fifo wr mode
    printf("i2s test\n");
    reg_i2s_mode = (uint32_t)1;

    for(uint32_t i = 0; i < 3; ++i) {
        // while(reg_i2s_status & (uint32_t)1); // check if fifo is full or not
        reg_i2s_txdata = test_data[i];
    }
    printf("i2s done\n");
}