#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinydma.h>
#include <tinyi2s.h>
#include <wav_audio.h>
#include <es8388.h>

uint32_t test_data[] = {0x12345678, 0x12345679, 0x1234567A, 0x2345EF23, 0x2345EF24, 0x2345EF25};
uint32_t audio_addr[] = {0x51004000, 0x54737000};
uint32_t audio_len = 2, audio_idx = 0;

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

void i2s_audio_load() {
    WAVFile_t res = wav_audio_parse(audio_addr[audio_idx]);
    if(res.addr == 0 || res.size == 0) printf("wav file pase error\n");
    else dma_config(1, res.addr, (uint32_t)1, (uint32_t)&reg_i2s_txdata, (uint32_t)0, res.size);
}

void ip_i2s_test() {
    char type_ch;
    uint32_t mode = 0, stop = 0, xfering = 0;

    es8388_init();
    printf("[APB IP] i2s test\n");
    // load first data
    i2s_audio_load();
    printf("help[h] next[n] mode[m] start[s] stop[t] reset[r] exit[e]\n");
    while(1) {
        type_ch = getchar();

        if(xfering) {
            if(reg_dma_status == (uint32_t)1) printf("dma tx done\n");
        }

        if(type_ch == 'e' && !xfering) break;
        else if(type_ch == 'h' && !xfering) printf("help[h] next[n] mode[m] start[s] stop[t] reset[r] exit[e]\n");
        else if(type_ch == 'n' && !xfering) {
            if(audio_idx == audio_len - 1) audio_idx = 0;
            else ++audio_idx;

            i2s_audio_load();
        } else if(type_ch == 'm' && !xfering) {
            if(mode) {
                mode = (uint32_t)0;
                printf("switch to loopback mode\n");
            } else {
                mode = (uint32_t)1;
                printf("switch to fifo-xfer mode\n");
            }
            i2s_init(mode);
        } else if(type_ch == 's' && !xfering) {
            if(mode == 1) {
                xfering = (uint32_t)1;
                dma_start_xfer();
            } else printf("need to set fifo-xfer mode first\n");
        } else if(type_ch == 't' && xfering) {
            dma_stop_toggle();
            if(stop) {
                stop = (uint32_t)0;
                i2s_init(1);
                printf("restore wav audio\n");
            } else {
                stop = (uint32_t)1;
                i2s_init(0);    
                printf("stop wav audio\n");
            }
        } else if(type_ch == 'r' && xfering) {
            xfering = 0;
            i2s_init(0);
            dma_reset_xfer();
            printf("reset wav audio\n");
        }
    }

    i2s_init(0);
}