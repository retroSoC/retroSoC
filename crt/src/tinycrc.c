#include <firmware.h>
#include <tinyprintf.h>
#include <tinycrc.h>

void ip_crc_test() {
    printf("[APB IP] crc test\n");

    reg_crc_ctrl = (uint32_t)0;
    reg_crc_init = (uint32_t)0xFFFF;
    reg_crc_xorv = (uint32_t)0;
    reg_crc_ctrl = (uint32_t)0b1001001;

    uint32_t val = 0x123456;
    for(int i = 0; i < 50; ++i) {
        reg_crc_data = val + i;
        while(reg_crc_stat == (uint32_t)0);
        printf("i: %d CRC: %x\n", i, reg_crc_data);
    }
}