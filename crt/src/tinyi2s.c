#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinydma.h>
#include <tinyi2s.h>
#include <wav_audio.h>
#include <es8388.h>

uint32_t test_data[] = {0x12345678, 0x12345679, 0x1234567A, 0x2345EF23, 0x2345EF24, 0x2345EF25};

void i2s_init(uint32_t mode) {
    reg_i2s_mode = (uint32_t)mode;
    reg_i2s_upbound = (uint32_t)120;
    // NOTE: larger than 'clk/clk_aud 'size of i2x tx fifo
    reg_i2s_lowbound = (uint32_t)80;
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
    char type_ch;
    uint32_t mode = 0;

    es8388_init();
    printf("[APB IP] i2s test\n");
    printf("exit[e] mode[m] start[s] stop[t] reset[r] \n");

    while(1) {
        type_ch = getchar();
        if(type_ch == 'e') break;
        else if(type_ch == 'm') {
            if(mode) {
                mode = 0;
                printf("switch to loopback mode\n");
            } else {
                mode = 1;
                printf("switch to normal mode\n");
            }
            i2s_init(mode);
        } else if(type_ch == 's') {
            if(mode == 1) wav_audio_play((uint32_t)0x54737000);
            else printf("need to set normal mode first\n");
        } else if(type_ch == 't') {
            i2s_init(0);
            dma_stop_xfer();
        } else if(type_ch == 'r') {
            i2s_init(0);
            dma_reset_xfer();
        }
    }

    // wav_audio_play((uint32_t)0x51004000);
    i2s_init(0);
}