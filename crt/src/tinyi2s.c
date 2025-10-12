#include <firmware.h>
#include <tinyprintf.h>
#include <wav_decoder.h>
#include <tinyi2s.h>

uint32_t test_data[] = {0x12345678, 0x12345679, 0x1234567A, 0x2345EF23, 0x2345EF24, 0x2345EF25};

void i2s_init(uint32_t mode) {
    reg_i2s_mode = (uint32_t)mode;
    reg_i2s_upbound = (uint32_t)120;
    reg_i2s_lowbound = (uint32_t)32;
}

void i2s_simp_test() {
    for(uint32_t i = 0; i < 6; ++i) {
        // while(reg_i2s_status & (uint32_t)1); // check if fifo is full or not
        reg_i2s_txdata = test_data[i];
    }
    printf("i2s tx done\n");

    reg_i2s_recven = (uint32_t)1;
    for(uint32_t i = 0; i < 6; ++i) {
        test_data[i] = reg_i2s_rxdata;
    }
    reg_i2s_recven = (uint32_t)0;
    for(uint32_t i = 0; i < 6; ++i) {
        printf("test_data[%d]: %x\n", i, test_data[i]);
    }

    printf("i2s rx done\n");
}

void ip_i2s_test() {
    // fifo wr mode
    printf("[APB IP] i2s test\n");
    i2s_init(1);
    // wav_file_decoder((uint32_t)0x51004000);
    wav_file_decoder((uint32_t)0x54737000);
    i2s_init(0);
}