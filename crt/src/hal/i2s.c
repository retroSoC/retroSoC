#include <retrosoc/core/soc.h>
#include <retrosoc/lib/console.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/media/wav_audio.h>
#include <retrosoc/board/es8388.h>

static const uint32_t audio_addr[] = {0x61004000U, 0x64737000U};
static const uint32_t audio_len = 2U;
static uint32_t audio_idx;

static void i2s_init(uint32_t mode) {
    reg_i2s_mode = (uint32_t)mode;
    reg_i2s_stream_ctrl = (mode == 0U) ? 0U : 1U;
    reg_i2s_upbound = (uint32_t)120;
    // NOTE: larger than 'clk/clk_aud 'size of i2x tx fifo
    reg_i2s_lowbound = (uint32_t)80;
}

static void i2s_audio_load(void) {
    rs_wav_info_t info;
    const uint32_t start_address = audio_addr[audio_idx];
    const uint32_t available_size =
        (start_address >= TF_CARD_START) && (start_address < (TF_CARD_START + TF_CARD_OFFST))
            ? TF_CARD_OFFST - (start_address - TF_CARD_START)
            : 0U;

    if ((available_size == 0U) ||
        (rs_wav_parse_spisd(start_address, available_size, &info) != RS_OK) ||
        ((info.data_size % sizeof(uint32_t)) != 0U) ||
        (rs_dma_config(RS_DMA_MODE_I2S_TX, start_address + info.data_offset, 1U,
                       (uintptr_t)&reg_i2s_txdata, 0U,
                       info.data_size / sizeof(uint32_t)) != RS_OK)) {
        printf("wav file parse/configuration error\n");
    }
}

static void i2s_audio_panel(void) {
    printf("============================================================\n");
    printf("                    retroSoC Audio Player                  \n");
    printf(" system:   help[h] exit[e] mode[m] next-audio[n]            \n");
    printf("============================================================\n");
    printf(" player: play[s] pause[t] reset[r] vol-up[u] vol-down[d]    \n");
    printf("============================================================\n");
}

void ip_i2s_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    char type_ch;
    uint32_t mode = 0, pause = 0, xfering = 0;

    es8388_init();
    printf("[APB IP] i2s test\n");
    // load first data
    // i2s_audio_load();
    i2s_audio_panel();
    while (true) {
        type_ch = getchar();

        if (xfering) {
            if (reg_dma_status == (uint32_t)1) {
                printf("dma tx done\n");
                xfering = (uint32_t)0;
            }
        }

        if (type_ch == 'e' && !xfering)
            break;
        else if (type_ch == 'h' && !xfering)
            i2s_audio_panel();
        else if (type_ch == 'n' && !xfering) {
            if (audio_idx == audio_len - 1)
                audio_idx = 0;
            else
                ++audio_idx;

            i2s_audio_load();
        } else if (type_ch == 'm' && !xfering) {
            if (mode) {
                mode = (uint32_t)0;
                printf("switch to loopback mode\n");
            } else {
                mode = (uint32_t)1;
                printf("switch to fifo-xfer mode\n");
            }
            i2s_init(mode);
        } else if (type_ch == 's' && !xfering) {
            // force switching to fifo-xfer mode
            i2s_init(1);
            xfering = (uint32_t)1;
            if (rs_dma_start() == RS_OK) {
                printf("start xfer\n");
            } else {
                xfering = 0U;
            }
        } else if (type_ch == 't' && xfering) {
            if (pause) {
                pause = (uint32_t)0;
                (void)rs_dma_stop();
                i2s_init(1);
                printf("resume audio play\n");
            } else {
                pause = (uint32_t)1;
                i2s_init(0);
                (void)rs_dma_stop();
                printf("fsm: %d\n", reg_dma_fsm);
                printf("pause audio play\n");
            }
        } else if (type_ch == 'r' && xfering) {
            xfering = (uint32_t)0;
            i2s_init(0);
            (void)rs_dma_reset();
            printf("reset audio play\n");
        }
    }

    i2s_init(0);
}
