#include <stddef.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/generated/irq_metadata.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/crc.h>
#include <retrosoc/hal/crypto.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/hal/rng.h>
#include <retrosoc/hal/sdio.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/ws2812.h>
#include <retrosoc/lib/printf.h>

#include "mcu_shared_acceptance.h"

static volatile uint32_t rs_p6_irq_count;
static uint32_t rs_p6_irq_selected;
static volatile bool rs_p6_irq_error;
static _Alignas(64) uint32_t rs_p6_source[256];
static _Alignas(64) uint32_t rs_p6_destination[258];
static _Alignas(64) uint32_t rs_p6_audio_tx[768];
static _Alignas(64) uint32_t rs_p6_audio_rx[562];
static _Alignas(64) rs_dma_tcd_t rs_p6_descriptors[4];
static rs_dma_session_t rs_p6_audio_tx_owner;
static rs_dma_session_t rs_p6_audio_rx_owner;
static rs_dma_session_t rs_p6_background_owner;
static uint32_t rs_p6_pixels[65];

static void rs_p6_irq_handler(uintptr_t cause, uintptr_t stack) {
    (void)cause;
    (void)stack;
    ++rs_p6_irq_count;
    if (rs_irq_disable_external(rs_p6_irq_selected) != RS_OK) {
        rs_p6_irq_error = true;
    }
}

static bool rs_p6_irq_arm(uint32_t irq) {
    rs_p6_irq_selected = irq;
    rs_p6_irq_count = 0U;
    rs_p6_irq_error = false;
    if ((rs_irq_register_external(irq, rs_p6_irq_handler) != RS_OK) ||
        (rs_irq_enable_external(irq, rs_p6_irq_handler) != RS_OK)) {
        return false;
    }
    __RV_CSR_SET(CSR_MSTATUS, UINT32_C(8));
    return true;
}

static bool rs_p6_irq_received(void) {
    uint32_t timeout = UINT32_C(100000);
    while ((rs_p6_irq_count == 0U) && (timeout != 0U)) {
        --timeout;
    }
    return (rs_p6_irq_count == 1U) && !rs_p6_irq_error;
}

static bool rs_p6_route(uint32_t pin, bool open_drain) {
    const rs_gpio_config_t config = {
        .mode = RS_GPIO_MODE_ALT0,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .open_drain = open_drain,
        .filter_enable = false,
    };
    return rs_gpio_configure(pin, &config) == RS_OK;
}

static bool rs_p6_uart(void) {
    const uint8_t transmit[4] = {0xA5U, 0x5AU, 0x96U, 0x69U};
    rs_uart_rx_data_t receive[4];
    const rs_uart_config_t unsupported = {
        .source_clock_hz = RS_PCLK_CLOCK_HZ,
        .baud_rate = UART_BPS,
        .data_bits = 8U,
        .stop_bits = 1U,
        .parity = RS_UART_PARITY_NONE,
        .rx_watermark = 1U,
        .rx_timeout_bits = 16U,
        .tx_enable = true,
        .rx_enable = true,
        .auto_cts_enable = true,
    };
    if ((rs_uart_configure(&unsupported, RS_TIMEOUT_DEFAULT) != RS_ENOTSUP) ||
        (rs_uart_write(transmit, sizeof(transmit), RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_uart_read(receive, 4U, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    for (uint32_t index = 0U; index < 4U; ++index) {
        if (receive[index].data != transmit[index] || receive[index].errors != 0U) {
            return false;
        }
    }
    printf("\nR2_P6_UART pads=1 echo_bytes=4 flow_rejected=1\n");
    return true;
}

static bool rs_p6_rng(void) {
    const rs_rng_config_t config = {.fifo_watermark = 1U};
    rs_rng_snapshot_t snapshot;
    uint32_t word = 0U;
    if ((rs_rng_init(&config) != RS_OK) ||
        (rs_rng_read_entropy(&word, RS_TIMEOUT_DEFAULT) != RS_ENOTSUP) ||
        (rs_rng_read_diagnostic(&word, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_rng_get_status(&snapshot) != RS_OK) || snapshot.source_qualified ||
        !rs_p6_irq_arm(RS_SOC_EXT_IRQ_RNG) ||
        (rs_rng_interrupt_enable(RS_RNG_INTERRUPT_SOURCE_FAULT) != RS_OK) ||
        (rs_rng_interrupt_test(RS_RNG_INTERRUPT_SOURCE_FAULT) != RS_OK) || !rs_p6_irq_received() ||
        (rs_rng_interrupt_enable(0U) != RS_OK) ||
        (rs_rng_interrupt_clear(RS_RNG_INTERRUPT_ALL) != RS_OK)) {
        return false;
    }
    printf("R2_P6_RNG unqualified=1 diagnostic=1 irq=1\n");
    return true;
}

static bool rs_p6_dma_capabilities(void) {
    const uint32_t capability = RS_DMA_REG(RS_DMA_REG_CAPABILITY);
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_p6_source,
        .destination = (uintptr_t)rs_p6_destination,
        .byte_count = 4U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .burst_beats = 1U,
    };
    rs_dma_status_t status;
    const uint32_t unsupported[] = {9U, 10U, 11U, 14U, 15U};
    if (((capability >> 8U) & UINT32_C(0xFF)) != 8U) {
        return false;
    }
    for (size_t index = 0U; index < sizeof(unsupported) / sizeof(unsupported[0]); ++index) {
        rs_p6_destination[0] = UINT32_C(0x12345678);
        if (rs_dma_configure(RS_DMA_CHANNEL_DVP, &config) != RS_OK) {
            return false;
        }
        /* Exercise hardware rejection independently of the SDK's earlier gate. */
        RS_DMA_CH_REG(RS_DMA_CHANNEL_DVP, RS_DMA_CH_REG_REQUEST_SEL) = unsupported[index];
        if ((rs_dma_start(RS_DMA_CHANNEL_DVP) != RS_OK) ||
            (rs_dma_wait(RS_DMA_CHANNEL_DVP, RS_TIMEOUT_DEFAULT) != RS_EIO) ||
            (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &status) != RS_OK) || !status.error ||
            status.busy || (status.bytes_done != 0U) ||
            (rs_p6_destination[0] != UINT32_C(0x12345678))) {
            return false;
        }
    }
    printf("R2_P6_DMA channels=8 rejected_requests=5\n");
    return true;
}

static uint32_t rs_p6_crc_reference(const uint8_t *data, size_t bytes) {
    uint32_t value = UINT32_MAX;
    for (size_t index = 0U; index < bytes; ++index) {
        value ^= (uint32_t)data[index];
        for (uint32_t bit = 0U; bit < 8U; ++bit) {
            value = (value >> 1U) ^ (((value & 1U) != 0U) ? UINT32_C(0xEDB88320) : 0U);
        }
    }
    return ~value;
}

static bool rs_p6_crc(void) {
    rs_crc_config_t crc;
    static rs_dma_session_t lease;
    uint32_t result;
    rs_dma_config_t transfer = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_p6_source,
        .destination = RS_SOC_APB4_CRC_BASE + CRC_DATA_OFFSET,
        .byte_count = UINT32_C(64),
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .burst_beats = 1U,
    };
    for (uint32_t index = 0U; index < 256U; ++index) {
        rs_p6_source[index] = UINT32_C(0x12345678) ^ (index * UINT32_C(0x01020408));
    }
    if ((rs_crc_get_profile(RS_CRC_PROFILE_CRC32_ISO_HDLC, &crc) != RS_OK) ||
        (rs_dma_session_acquire(&lease, RS_DMA_CHANNEL_BULK) != RS_OK)) {
        return false;
    }
    for (size_t tail = 0U; tail < 4U; ++tail) {
        if ((rs_crc_init(&crc) != RS_OK) || (rs_crc_start() != RS_OK) ||
            (rs_dma_session_configure(&lease, &transfer) != RS_OK) ||
            (rs_dma_session_start(&lease) != RS_OK) ||
            (rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK) ||
            (rs_crc_update((const uint8_t *)rs_p6_source + 64U, tail) != RS_OK) ||
            (rs_crc_finish(&result) != RS_OK) ||
            (result != rs_p6_crc_reference((const uint8_t *)rs_p6_source, 64U + tail))) {
            return false;
        }
    }
    if ((rs_dma_session_release(&lease) != RS_OK) ||
        (rs_crc_compute(&crc, rs_p6_source, 0U, &result) != RS_OK) || (result != 0U)) {
        return false;
    }
    printf("R2_P6_CRC dma=1 tails=4 empty=1\n");
    return true;
}

static bool rs_p6_crypto(void) {
    static uint32_t modulus[RS_CRYPTO_RSA_WORDS];
    static uint32_t base[RS_CRYPTO_RSA_WORDS];
    static uint32_t exponent[RS_CRYPTO_RSA_WORDS];
    static uint32_t rsa_result[RS_CRYPTO_RSA_WORDS];
    static const uint8_t key[16] = {
        0x00U, 0x01U, 0x02U, 0x03U, 0x04U, 0x05U, 0x06U, 0x07U,
        0x08U, 0x09U, 0x0AU, 0x0BU, 0x0CU, 0x0DU, 0x0EU, 0x0FU,
    };
    static const uint32_t input[4] = {
        UINT32_C(0x33221100),
        UINT32_C(0x77665544),
        UINT32_C(0xBBAA9988),
        UINT32_C(0xFFEEDDCC),
    };
    static const uint32_t expected[4] = {
        UINT32_C(0xD8E0C469),
        UINT32_C(0x30047B6A),
        UINT32_C(0x80B7CDD8),
        UINT32_C(0x5AC5B470),
    };
    if ((rs_crypto_zeroize_wait(1U) != RS_ETIMEOUT) ||
        (rs_crypto_zeroize_wait(RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_crypto_init(2050U) != RS_ETIMEOUT) ||
        (rs_crypto_selftest(RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_crypto_aes_set_key(key, sizeof(key), RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    for (uint32_t index = 0U; index < 16U; ++index) {
        rs_p6_source[index] = input[index % 4U];
    }
    rs_p6_destination[0] = UINT32_C(0x5A5AA5A5);
    rs_p6_destination[17] = UINT32_C(0xA5A55A5A);
    if (rs_crypto_aes_crypt_dma(RS_CRYPTO_AES_ECB, false, NULL, rs_p6_source, &rs_p6_destination[1],
                                64U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        return false;
    }
    for (uint32_t index = 0U; index < 16U; ++index) {
        if (rs_p6_destination[index + 1U] != expected[index % 4U]) {
            return false;
        }
    }
    /* A small public-operation integration vector exercises the full 2048-bit
     * storage/control path. Full private vectors remain in the shared suite. */
    for (uint32_t index = 0U; index < RS_CRYPTO_RSA_WORDS; ++index) {
        modulus[index] = UINT32_MAX;
    }
    base[0] = 2U;
    exponent[0] = 3U;
    if ((rs_crypto_rsa_prepare(modulus, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_crypto_rsa_modexp(base, exponent, 2U, false, rsa_result, RS_TIMEOUT_DEFAULT) !=
         RS_OK)) {
        return false;
    }
    for (uint32_t index = 0U; index < RS_CRYPTO_RSA_WORDS; ++index) {
        if (rsa_result[index] != ((index == 0U) ? 8U : 0U)) {
            return false;
        }
    }
    if ((rs_p6_destination[0] != UINT32_C(0x5A5AA5A5)) ||
        (rs_p6_destination[17] != UINT32_C(0xA5A55A5A)) || !rs_p6_irq_arm(RS_SOC_EXT_IRQ_CRYPTO)) {
        return false;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) = RS_CRYPTO_IRQ_ALL;
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_ENABLE) = RS_CRYPTO_IRQ_ZEROIZED;
    if ((rs_crypto_zeroize_wait(0U) != RS_ETIMEOUT) ||
        (rs_crypto_zeroize_wait(RS_TIMEOUT_DEFAULT) != RS_OK) || !rs_p6_irq_received()) {
        return false;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_ENABLE) = 0U;
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) = RS_CRYPTO_IRQ_ALL;
    printf("R2_P6_CRYPTO init=1 aes_sha=1 dma45=1 rsa_public=1 zeroize=1\n");
    return true;
}

static bool rs_p6_stop_session(rs_dma_session_t *owner) {
    rs_dma_status_t status;
    uint32_t timeout = UINT32_C(100000);
    if ((rs_dma_get_status(owner->channel, &status) != RS_OK) ||
        (status.busy && (rs_dma_session_abort(owner) != RS_OK))) {
        return false;
    }
    do {
        if ((rs_dma_get_status(owner->channel, &status) != RS_OK) || (timeout == 0U)) {
            return false;
        }
        --timeout;
    } while (status.busy);
    return rs_dma_session_release(owner) == RS_OK;
}

static uint32_t rs_p6_audio_sample(bool wide, uint32_t index) {
    const uint32_t word = rs_p6_audio_rx[1U + (wide ? index : index / 2U)];
    return wide ? word : ((word >> ((index % 2U) * 16U)) & UINT32_C(0xFFFF));
}

static bool rs_p6_audio_words(bool wide, uint32_t received_words) {
    const uint32_t samples = wide ? received_words : received_words * 2U;
    const uint32_t first = wide ? UINT32_C(0x120020) : UINT32_C(0x2020);
    uint32_t offset = 0U;
    /* Ignore only the bounded PHY startup preamble, never a missing payload.
     * Exactly 256 stereo frames must then match consecutive independent samples. */
    while ((offset < 40U) && (rs_p6_audio_sample(wide, offset) != first)) {
        ++offset;
    }
    if ((offset >= 40U) || ((offset + 512U) > samples)) {
        return false;
    }
    for (uint32_t sample = 0U; sample < 512U; ++sample) {
        if (rs_p6_audio_sample(wide, offset + sample) != (first + sample)) {
            printf("R2_P6_AUDIO mismatch wide=%u sample=%lu got=%lx expected=%lx\n", wide ? 1U : 0U,
                   (unsigned long)sample, (unsigned long)rs_p6_audio_sample(wide, offset + sample),
                   (unsigned long)(first + sample));
            return false;
        }
    }
    return (rs_p6_audio_rx[0] == UINT32_C(0x5A5AA5A5)) &&
           (rs_p6_audio_rx[received_words + 1U] == UINT32_C(0xA5A55A5A));
}

static bool rs_p6_audio_ws(bool wide) {
    printf("R2_P6_STAGE audio_bits=%u cycles=%lu\n", wide ? 24U : 16U,
           (unsigned long)__RV_CSR_READ(CSR_MCYCLE));
    const uint32_t rx_words = wide ? 548U : 280U;
    const rs_i2s_config_t audio = {
        .stream_tx = true,
        .stream_rx = true,
        .preset = wide ? RS_I2S_PRESET_24B_48K : RS_I2S_PRESET_16B_48K,
        .upbound = 96U,
        .lowbound = 32U,
    };
    const rs_ws2812_config_t ws = {
        .source_clock_hz = RS_PCLK_CLOCK_HZ,
        .bit_period_ns = 1250U,
        .t0h_ns = 350U,
        .t1h_ns = 700U,
        .reset_ns = 300000U,
        .fifo_watermark = 8U,
    };
    rs_dma_config_t tx = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_I2S_TX,
        .source = (uintptr_t)rs_p6_audio_tx,
        .byte_count = sizeof(rs_p6_audio_tx),
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .priority = 3U,
        .burst_beats = 16U,
    };
    rs_dma_config_t rx = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_I2S_RX,
        .destination = (uintptr_t)&rs_p6_audio_rx[1],
        .byte_count = rx_words * 4U,
        .width = RS_DMA_WIDTH_32,
        .destination_increment = true,
        .priority = 3U,
        .burst_beats = 16U,
    };
    rs_dma_config_t background = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_p6_source,
        .destination = (uintptr_t)&rs_p6_destination[1],
        .byte_count = 256U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .burst_beats = 16U,
    };
    rs_i2s_status_t audio_status;
    rs_dma_status_t rx_status, bg_status;
    rs_ws2812_dma_status_t ws_status;
    uint64_t now, deadline, start;
    uint32_t cycles, instructions;
    uint32_t frame = 0U, background_jobs = 0U;
    for (uint32_t pin = 12U; pin <= 17U; ++pin) {
        if (!rs_p6_route(pin, false)) {
            return false;
        }
    }
    if (!rs_p6_route(26U, false) || (rs_i2s_disable() != RS_OK) ||
        (rs_i2s_flush(true, true, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_i2s_configure(&audio) != RS_OK) || (rs_ws2812_init(&ws) != RS_OK)) {
        return false;
    }
    printf("R2_P6_STAGE audio_host_ready=1 cycles=%lu\n", (unsigned long)__RV_CSR_READ(CSR_MCYCLE));
    for (uint32_t index = 0U; index < 768U; ++index) {
        rs_p6_audio_tx[index] =
            wide ? UINT32_C(0x120000) + index
                 : ((UINT32_C(0x2001) + 2U * index) << 16U) | (UINT32_C(0x2000) + 2U * index);
    }
    for (uint32_t index = 0U; index < 65U; ++index) {
        rs_p6_pixels[index] = index * UINT32_C(0x010203);
    }
    for (uint32_t index = 0U; index < 256U; ++index) {
        rs_p6_source[index] = UINT32_C(0x5A123456) ^ index;
        rs_p6_destination[index + 1U] = 0U;
    }
    rs_p6_destination[0] = UINT32_C(0x5A5AA5A5);
    rs_p6_destination[257] = UINT32_C(0xA5A55A5A);
    rs_p6_audio_rx[0] = UINT32_C(0x5A5AA5A5);
    rs_p6_audio_rx[rx_words + 1U] = UINT32_C(0xA5A55A5A);
    for (uint32_t index = 0U; index < 4U; ++index) {
        rs_p6_descriptors[index] = (rs_dma_tcd_t){
            .source = (uint32_t)(uintptr_t)&rs_p6_source[index * 64U],
            .destination = (uint32_t)(uintptr_t)&rs_p6_destination[1U + index * 64U],
            .byte_count = 256U,
            .next_ptr = index == 3U ? 0U : (uint32_t)(uintptr_t)&rs_p6_descriptors[index + 1U],
            .control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                       (UINT32_C(16) << RS_DMA_TCD_BURST_SHIFT),
        };
    }
    if (!rs_p6_irq_arm(RS_SOC_EXT_IRQ_I2S) ||
        (rs_i2s_interrupt_enable(RS_I2S_INTERRUPT_TX_LOW) != RS_OK) ||
        (rs_i2s_interrupt_test(RS_I2S_INTERRUPT_TX_LOW) != RS_OK) || !rs_p6_irq_received() ||
        (rs_i2s_interrupt_enable(0U) != RS_OK) ||
        (rs_i2s_interrupt_clear(RS_I2S_INTERRUPT_ALL) != RS_OK) ||
        (rs_dma_session_acquire(&rs_p6_audio_tx_owner, RS_DMA_CHANNEL_I2S_TX) != RS_OK) ||
        (rs_dma_session_acquire(&rs_p6_audio_rx_owner, RS_DMA_CHANNEL_I2S_RX) != RS_OK) ||
        (rs_dma_session_acquire(&rs_p6_background_owner, RS_DMA_CHANNEL_DVP) != RS_OK) ||
        (rs_dma_session_configure(&rs_p6_audio_tx_owner, &tx) != RS_OK) ||
        (rs_dma_session_configure(&rs_p6_audio_rx_owner, &rx) != RS_OK) ||
        (rs_dma_session_start(&rs_p6_audio_tx_owner) != RS_OK) ||
        (rs_dma_session_start(&rs_p6_audio_rx_owner) != RS_OK) ||
        (rs_clint_get_time(&start) != RS_OK)) {
        return false;
    }
    deadline = start + UINT64_C(50000);
    printf("R2_P6_STAGE audio_dma_started=1 cycles=%lu\n",
           (unsigned long)__RV_CSR_READ(CSR_MCYCLE));
    do {
        if ((rs_i2s_get_status(&audio_status) != RS_OK) || (rs_clint_get_time(&now) != RS_OK) ||
            (now >= deadline)) {
            return false;
        }
    } while (audio_status.tx_level < 96U);
    printf("R2_P6_STAGE audio_prefilled=1 cycles=%lu\n", (unsigned long)__RV_CSR_READ(CSR_MCYCLE));
    cycles = (uint32_t)__RV_CSR_READ(CSR_MCYCLE);
    instructions = (uint32_t)__RV_CSR_READ(CSR_MINSTRET);
    if (!rs_p6_irq_arm(RS_SOC_EXT_IRQ_WS2812) ||
        (rs_ws2812_irq_enable(RS_WS2812_INTR_FIFO_LOW | RS_WS2812_INTR_DONE) != RS_OK) ||
        (rs_i2s_enable(true, true) != RS_OK) ||
        (rs_ws2812_dma_begin(rs_p6_pixels, 33U, now, deadline) != RS_OK)) {
        return false;
    }
    do {
        if ((rs_clint_get_time(&now) != RS_OK) || (now >= deadline) ||
            (rs_ws2812_dma_service(now) != RS_OK) || (rs_ws2812_dma_status(&ws_status) != RS_OK) ||
            (rs_dma_get_status(RS_DMA_CHANNEL_I2S_RX, &rx_status) != RS_OK) ||
            (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &bg_status) != RS_OK) || rx_status.error ||
            bg_status.error) {
            return false;
        }
        if (!bg_status.busy && (background_jobs < 64U)) {
            if (rs_dma_session_configure(&rs_p6_background_owner, &background) != RS_OK) {
                return false;
            }
            /* This application exclusively leases channel 2; the ordinary TCD
             * helper is blocking, so publish the same finite hardware chain. */
            RS_DMA_CH_REG(RS_DMA_CHANNEL_DVP, RS_DMA_CH_REG_TCD_HEAD) =
                wide ? (uint32_t)(uintptr_t)rs_p6_descriptors : 0U;
            RS_DMA_CH_REG(RS_DMA_CHANNEL_DVP, RS_DMA_CH_REG_TCD_COUNT) = wide ? 4U : 0U;
            if (rs_dma_session_start(&rs_p6_background_owner) != RS_OK) {
                return false;
            }
            ++background_jobs;
        }
        if (!ws_status.active && (frame == 0U)) {
            if ((ws_status.result != RS_OK) ||
                (rs_ws2812_dma_begin(rs_p6_pixels, 65U, now, deadline) != RS_OK)) {
                return false;
            }
            frame = 1U;
            ws_status.active = true;
        }
    } while (rx_status.busy || ws_status.active);
    cycles = (uint32_t)__RV_CSR_READ(CSR_MCYCLE) - cycles;
    instructions = (uint32_t)__RV_CSR_READ(CSR_MINSTRET) - instructions;
    if ((rx_status.bytes_done != rx_words * 4U) || !rx_status.done || (ws_status.result != RS_OK) ||
        (rs_p6_irq_count != 1U) || (rs_i2s_get_status(&audio_status) != RS_OK) ||
        ((audio_status.interrupt_state &
          (RS_I2S_INTERRUPT_TX_UNDERRUN | RS_I2S_INTERRUPT_RX_OVERRUN)) != 0U) ||
        !rs_p6_stop_session(&rs_p6_audio_tx_owner) || !rs_p6_stop_session(&rs_p6_audio_rx_owner) ||
        (rs_i2s_disable() != RS_OK) ||
        (rs_dma_wait(RS_DMA_CHANNEL_DVP, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_dma_session_release(&rs_p6_background_owner) != RS_OK) ||
        (rs_i2s_flush(true, true, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_ws2812_irq_enable(0U) != RS_OK) || !rs_p6_audio_words(wide, rx_words)) {
        return false;
    }
    for (uint32_t index = 0U; index < (wide ? 256U : 64U); ++index) {
        if (rs_p6_destination[index + 1U] != rs_p6_source[index]) {
            return false;
        }
    }
    if ((rs_p6_destination[0] != UINT32_C(0x5A5AA5A5)) ||
        (rs_p6_destination[257] != UINT32_C(0xA5A55A5A))) {
        return false;
    }
    if (!wide) {
        for (uint32_t index = 65U; index <= 256U; ++index) {
            if (rs_p6_destination[index] != 0U) {
                return false;
            }
        }
    }
    printf("R2_P6_AUDIO bits=%u frames=256 ws_frames=2 background_jobs=%lu tcd=%u elapsed_us=%lu "
           "cycles=%lu instructions=%lu\n",
           wide ? 24U : 16U, (unsigned long)background_jobs, wide ? 1U : 0U,
           (unsigned long)(now - start), (unsigned long)cycles, (unsigned long)instructions);
    return background_jobs != 0U;
}

static bool rs_p6_audio_ws_recovery(void) {
    const rs_ws2812_config_t config = {
        .source_clock_hz = RS_PCLK_CLOCK_HZ,
        .bit_period_ns = 1250U,
        .t0h_ns = 350U,
        .t1h_ns = 700U,
        .reset_ns = 300000U,
        .fifo_watermark = 8U,
    };
    uint64_t now, began;
    rs_i2s_status_t audio;
    rs_ws2812_status_t ws;
    for (uint32_t phase = 0U; phase < 2U; ++phase) {
        if ((rs_gpio_write(27U, true) != RS_OK) || (rs_clint_get_time(&began) != RS_OK)) {
            return false;
        }
        do {
            if (rs_clint_get_time(&now) != RS_OK) {
                return false;
            }
        } while ((now - began) < 10U);
        if ((rs_i2s_flush(true, true, 16U) != RS_ETIMEOUT) ||
            (rs_i2s_get_status(&audio) != RS_OK)) {
            return false;
        }
        /* A timed-out command remains owned by the controller. Do not issue
         * another COMMAND while BUSY: that write is correctly rejected. */
        do {
            if ((rs_i2s_get_status(&audio) != RS_OK) || (rs_clint_get_time(&now) != RS_OK) ||
                ((now - began) > 1000U)) {
                return false;
            }
        } while ((audio.status & (RS_I2S_STATUS_TX_FLUSH_BUSY | RS_I2S_STATUS_RX_FLUSH_BUSY)) !=
                 0U);
        if (rs_gpio_write(27U, false) != RS_OK) {
            return false;
        }
    }
    if ((rs_ws2812_init(&config) != RS_OK) || (rs_ws2812_push(0U, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_ws2812_start(2U) != RS_OK) || (rs_ws2812_wait(RS_TIMEOUT_DEFAULT) != RS_EIO) ||
        (rs_ws2812_get_status(&ws) != RS_OK) ||
        ((ws.error_status & RS_WS2812_ERROR_UNDERFLOW) == 0U) ||
        (rs_clint_get_time(&began) != RS_OK)) {
        return false;
    }
    do {
        if ((rs_ws2812_get_status(&ws) != RS_OK) || (rs_clint_get_time(&now) != RS_OK) ||
            ((now - began) > 1000U)) {
            return false;
        }
    } while (ws.busy);
    if ((rs_ws2812_init(&config) != RS_OK) || (rs_ws2812_push(0U, RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_ws2812_start(65U) != RS_OK) || (rs_ws2812_abort(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    printf("R2_P6_RECOVERY audio_stops=2 ws_underflow=1 ws_abort=1\n");
    return true;
}

static bool rs_p6_sdio_step(rs_status_t result, uint32_t step) {
    rs_sdio_status_t status;
    if (result == RS_OK) {
        return true;
    }
    if (rs_sdio_status_get(RS_SDIO_INSTANCE_0, &status) == RS_OK) {
        printf("R2_P6_SDIO_ERROR step=%lu result=%ld command=%lx data=%lx dma=%lx errors=%lx\n",
               (unsigned long)step, (long)result, (unsigned long)status.command_status,
               (unsigned long)status.data_status, (unsigned long)status.dma_status,
               (unsigned long)status.error_status);
    }
    return false;
}

static bool rs_p6_sdio(void) {
    static _Alignas(16) rs_sdio_descriptor_t descriptor;
    rs_sd_memory_info_t card;
    rs_sdio_clock_t clock;
    rs_sdio_response_t response;
    rs_dma_config_t background = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)rs_p6_audio_tx,
        .destination = (uintptr_t)&rs_p6_audio_rx[1],
        .byte_count = 1024U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .burst_beats = 16U,
    };
    rs_sdio_command_t command = {
        .index = 17U,
        .argument = 1U,
        .response = RS_SDIO_RESPONSE_R1,
        .crc_check = true,
        .index_check = true,
    };
    const rs_sdio_data_config_t pio = {
        .block_size = 512U,
        .block_count = 1U,
        .direction = RS_SDIO_DATA_FROM_CARD,
        .dma = false,
        .block_mode = true,
    };
    const rs_sdio_data_config_t dma_write = {
        .block_size = 512U,
        .block_count = 2U,
        .direction = RS_SDIO_DATA_TO_CARD,
        .dma = true,
        .block_mode = true,
    };
    uint32_t id, version, capability;
    rs_status_t initialized;
    printf("R2_P6_STAGE sdio_begin=1\n");
    for (uint32_t pin = 0U; pin < 6U; ++pin) {
        if (!rs_p6_route(pin, false)) {
            return false;
        }
    }
    if ((rs_sdio_probe(RS_SDIO_INSTANCE_1, &id, &version, &capability) != RS_ENOTSUP) ||
        (rs_sdio_controller_selftest(RS_SDIO_INSTANCE_0) != RS_OK)) {
        return false;
    }
    initialized =
        rs_sd_memory_initialize(RS_SDIO_INSTANCE_0, RS_CPU_CLOCK_HZ, &card, RS_TIMEOUT_DEFAULT);
    printf("R2_P6_STAGE sdio_init=%ld clock=%lu width=%u rca=%u\n", (long)initialized,
           (unsigned long)card.actual_clock_hz, (unsigned)card.bus_width, (unsigned)card.rca);
    if ((initialized != RS_OK) || (card.actual_clock_hz != UINT32_C(12000000)) ||
        !card.high_capacity || (card.rca != 1U) || (card.bus_width != RS_SDIO_BUS_WIDTH_4)) {
        return false;
    }
    for (uint32_t index = 0U; index < 256U; ++index) {
        rs_p6_source[index] = UINT32_C(0x13579BDF) ^ index;
        rs_p6_destination[index + 1U] = 0U;
        rs_p6_audio_tx[index] = UINT32_C(0x55AA0000) + index;
        rs_p6_audio_rx[index + 1U] = ~rs_p6_audio_tx[index];
    }
    rs_p6_destination[0] = UINT32_C(0x5A5AA5A5);
    rs_p6_destination[257] = UINT32_C(0xA5A55A5A);
    command.index = 25U;
    if (!rs_p6_sdio_step(rs_dma_session_acquire(&rs_p6_background_owner, RS_DMA_CHANNEL_DVP), 1U) ||
        !rs_p6_sdio_step(rs_dma_session_configure(&rs_p6_background_owner, &background), 2U) ||
        !rs_p6_sdio_step(
            rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT),
            3U) ||
        !rs_p6_sdio_step(rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)rs_p6_source, 1024U,
                                                    (uintptr_t)0U, true, false),
                         4U) ||
        !rs_p6_sdio_step(rs_sdio_dma_setup(RS_SDIO_INSTANCE_0, &descriptor, 1U, 1024U), 5U) ||
        !rs_p6_sdio_step(rs_sdio_data_configure(RS_SDIO_INSTANCE_0, &dma_write), 6U) ||
        !rs_p6_sdio_step(rs_sdio_data_start(RS_SDIO_INSTANCE_0), 7U) ||
        !rs_p6_sdio_step(rs_dma_session_start(&rs_p6_background_owner), 8U) ||
        !rs_p6_sdio_step(rs_sdio_data_wait(RS_SDIO_INSTANCE_0, RS_TIMEOUT_DEFAULT), 9U) ||
        !rs_p6_sdio_step(rs_sdio_dma_wait(RS_SDIO_INSTANCE_0, RS_TIMEOUT_DEFAULT), 10U)) {
        return false;
    }
    printf("R2_P6_STAGE sdio_write=1\n");
    command.index = 12U;
    command.argument = 0U;
    command.response = RS_SDIO_RESPONSE_R1B;
    if (!rs_p6_sdio_step(
            rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT),
            11U) ||
        !rs_p6_sdio_step(rs_sd_memory_read_blocks(RS_SDIO_INSTANCE_0, &card, 1U, 2U,
                                                  &rs_p6_destination[1], RS_TIMEOUT_DEFAULT),
                         12U) ||
        !rs_p6_sdio_step(rs_dma_wait(RS_DMA_CHANNEL_DVP, RS_TIMEOUT_DEFAULT), 13U) ||
        !rs_p6_sdio_step(rs_dma_session_release(&rs_p6_background_owner), 14U)) {
        return false;
    }
    printf("R2_P6_STAGE sdio_read=1\n");
    for (uint32_t index = 0U; index < 256U; ++index) {
        if ((rs_p6_destination[index + 1U] != rs_p6_source[index]) ||
            (rs_p6_audio_rx[index + 1U] != rs_p6_audio_tx[index])) {
            return false;
        }
    }
    if ((rs_p6_destination[0] != UINT32_C(0x5A5AA5A5)) ||
        (rs_p6_destination[257] != UINT32_C(0xA5A55A5A)) ||
        (rs_sdio_clock_set(RS_SDIO_INSTANCE_0, RS_CPU_CLOCK_HZ, 400000U, &clock) != RS_OK) ||
        (clock.actual_hz != 400000U)) {
        return false;
    }
    /* Select one-bit card and host consistently before the PIO read. */
    command.index = 55U;
    command.argument = (uint32_t)card.rca << 16U;
    command.response = RS_SDIO_RESPONSE_R1;
    if (rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT) !=
        RS_OK) {
        return false;
    }
    command.index = 6U;
    command.argument = 0U;
    if ((rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT) !=
         RS_OK) ||
        (rs_sdio_bus_width_set(RS_SDIO_INSTANCE_0, RS_SDIO_BUS_WIDTH_1) != RS_OK)) {
        return false;
    }
    command.index = 17U;
    command.argument = 1U;
    if (!rs_p6_sdio_step(
            rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT),
            15U) ||
        !rs_p6_sdio_step(rs_sdio_data_configure(RS_SDIO_INSTANCE_0, &pio), 16U) ||
        !rs_p6_sdio_step(rs_sdio_data_start(RS_SDIO_INSTANCE_0), 17U) ||
        !rs_p6_sdio_step(
            rs_sdio_pio_read(RS_SDIO_INSTANCE_0, &rs_p6_destination[1], 512U, RS_TIMEOUT_DEFAULT),
            18U) ||
        !rs_p6_sdio_step(rs_sdio_data_wait(RS_SDIO_INSTANCE_0, RS_TIMEOUT_DEFAULT), 19U)) {
        return false;
    }
    printf("R2_P6_STAGE sdio_pio=1\n");
    for (uint32_t index = 0U; index < 128U; ++index) {
        if (rs_p6_destination[index + 1U] != rs_p6_source[index]) {
            return false;
        }
    }
    if ((rs_sdio_irq_clear(RS_SDIO_INSTANCE_0, RS_SDIO_IRQ_ALL) != RS_OK) ||
        !rs_p6_irq_arm(RS_SOC_EXT_IRQ_SDIO) ||
        (rs_sdio_irq_enable(RS_SDIO_INSTANCE_0, RS_SDIO_IRQ_ALL) != RS_OK) ||
        (rs_sdio_irq_test(RS_SDIO_INSTANCE_0, 1U) != RS_OK) || !rs_p6_irq_received() ||
        (rs_sdio_irq_enable(RS_SDIO_INSTANCE_0, 0U) != RS_OK) ||
        (rs_sdio_irq_clear(RS_SDIO_INSTANCE_0, RS_SDIO_IRQ_ALL) != RS_OK) ||
        (rs_sdio_timeouts_set(RS_SDIO_INSTANCE_0, 24000U, 24000U, 24000U) != RS_OK)) {
        return false;
    }
    /* Verification card injects faults on these documented CMD13 arguments. */
    command.index = 13U;
    command.argument = UINT32_C(0xBADC0DE0);
    if (rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT) !=
        RS_EFORMAT) {
        return false;
    }
    command.argument = UINT32_C(0xBADC0DE1);
    if (rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT) !=
        RS_ETIMEOUT) {
        return false;
    }
    command.argument = (uint32_t)card.rca << 16U;
    if ((rs_sdio_error_clear(RS_SDIO_INSTANCE_0, RS_SDIO_ERROR_ALL) != RS_OK) ||
        (rs_sdio_command_execute(RS_SDIO_INSTANCE_0, &command, &response, RS_TIMEOUT_DEFAULT) !=
         RS_OK)) {
        return false;
    }
    printf("R2_P6_SDIO dma_bytes=2048 pio_bytes=512 width1=1 width4=1 irq=1 errors=2\n");
    return true;
}

uint8_t rs_tiny_p6_acceptance(void) {
    if (!rs_p6_uart()) {
        return 27U;
    }
    if (!rs_p6_dma_capabilities()) {
        return 19U;
    }
    if (!rs_p6_rng()) {
        return 20U;
    }
    if (!rs_p6_crc()) {
        return 21U;
    }
    if (!rs_p6_crypto()) {
        return 22U;
    }
    if (!rs_p6_audio_ws(false)) {
        return 23U;
    }
    if (!rs_p6_audio_ws(true)) {
        return 24U;
    }
    if (!rs_p6_audio_ws_recovery()) {
        return 26U;
    }
    if (!rs_p6_sdio()) {
        return 25U;
    }
    return 0U;
}
