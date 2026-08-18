#include <retrosoc/board/es8388.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/lib/console.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/media/wav_audio.h>

static const uint32_t audio_addr[] = {0x61004000U, 0x64737000U};
static const uint32_t audio_len = 2U;
static uint32_t audio_idx;

static rs_status_t i2s_init(bool loopback) {
    rs_i2s_config_t config = {
        .loopback = loopback,
        .stream_tx = !loopback,
        .stream_rx = false,
        .clock_prog = false,
        .preset = RS_I2S_PRESET_16B_48K,
        .bitmode_24 = false,
        .sclk_div = 0U,
        .lrck_div = 0U,
        .mclk_div = 0U,
        .upbound = 120U,
        .lowbound = 80U,
    };

    if (rs_i2s_configure(&config) != RS_OK)
        return RS_EIO;
    return rs_i2s_enable(!loopback, false);
}

static void i2s_audio_load(void) {
    rs_wav_info_t info;
    rs_dma_config_t dma_config;
    const uint32_t start_address = audio_addr[audio_idx];
    const uint32_t available_size =
        (start_address >= TF_CARD_START) && (start_address < (TF_CARD_START + TF_CARD_OFFST))
            ? TF_CARD_OFFST - (start_address - TF_CARD_START)
            : 0U;

    if ((available_size == 0U) ||
        (rs_wav_parse_spisd(start_address, available_size, &info) != RS_OK) ||
        ((info.data_size % sizeof(uint32_t)) != 0U)) {
        printf("wav file parse/configuration error\n");
        return;
    }
    dma_config.kind = RS_DMA_KIND_MM_TO_STREAM;
    dma_config.request = RS_DMA_REQUEST_I2S_TX;
    dma_config.source = (uintptr_t)(start_address + info.data_offset);
    dma_config.destination = (uintptr_t)0U;
    dma_config.byte_count = info.data_size;
    dma_config.width = RS_DMA_WIDTH_32;
    dma_config.source_increment = true;
    dma_config.destination_increment = false;
    dma_config.priority = 2U;
    dma_config.burst_beats = RS_DMA_MAX_BURST_BEATS;
    if (rs_dma_configure(RS_DMA_CHANNEL_BULK, &dma_config) != RS_OK) {
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

void ip_i2s_player(int argc, char **argv) {
    char type_ch;
    uint32_t mode = 0, pause = 0, xfering = 0;
    rs_dma_status_t dma_status;

    (void)argc;
    (void)argv;
    es8388_init();
    printf("[APB IP] i2s test\n");
    i2s_audio_panel();
    while (true) {
        type_ch = getchar();

        if (xfering) {
            if ((rs_dma_get_status(RS_DMA_CHANNEL_BULK, &dma_status) == RS_OK) && dma_status.done) {
                printf("dma tx done\n");
                xfering = (uint32_t)0;
            }
        }

        if (type_ch == 'e' && !xfering)
            break;
        else if (type_ch == 'h' && !xfering)
            i2s_audio_panel();
        else if (type_ch == 'n' && !xfering) {
            if (audio_idx == audio_len - 1U)
                audio_idx = 0U;
            else
                ++audio_idx;
            i2s_audio_load();
        } else if (type_ch == 'm' && !xfering) {
            if (mode != 0U) {
                mode = 0U;
                printf("switch to loopback mode\n");
            } else {
                mode = 1U;
                printf("switch to fifo-xfer mode\n");
            }
            (void)i2s_init(mode == 0U);
        } else if (type_ch == 's' && !xfering) {
            (void)i2s_init(false);
            xfering = 1U;
            if (rs_dma_start(RS_DMA_CHANNEL_BULK) == RS_OK) {
                printf("start xfer\n");
            } else {
                xfering = 0U;
            }
        } else if (type_ch == 't' && xfering) {
            if (pause != 0U) {
                pause = 0U;
                (void)rs_dma_resume(RS_DMA_CHANNEL_BULK);
                (void)i2s_init(false);
                printf("resume audio play\n");
            } else {
                pause = 1U;
                (void)i2s_init(true);
                (void)rs_dma_suspend(RS_DMA_CHANNEL_BULK);
                printf("pause audio play\n");
            }
        } else if (type_ch == 'r' && xfering) {
            xfering = 0U;
            (void)i2s_init(true);
            if (rs_dma_abort_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) == RS_OK) {
                (void)rs_dma_reset(RS_DMA_CHANNEL_BULK);
            }
            printf("reset audio play\n");
        }
    }

    (void)i2s_init(true);
}
