#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#include "p9_startup.h"
#include "p9_frame.h"

#ifdef RS_TINY_P9_QUICK
#define RS_P9_QVGA_WIDTH  UINT32_C(16)
#define RS_P9_QVGA_HEIGHT UINT32_C(8)
#elif defined(RS_TINY_P9_VGA_YUV422)
#define RS_P9_QVGA_WIDTH  UINT32_C(640)
#define RS_P9_QVGA_HEIGHT UINT32_C(480)
#else
#define RS_P9_QVGA_WIDTH  UINT32_C(320)
#define RS_P9_QVGA_HEIGHT UINT32_C(240)
#endif
#ifdef RS_TINY_P9_VGA_YUV422
#define RS_P9_FORMAT RS_DVP_FORMAT_YUV422
#else
#define RS_P9_FORMAT RS_DVP_FORMAT_RGB565
#endif
#define RS_P9_QVGA_BYTES (RS_P9_QVGA_WIDTH * RS_P9_QVGA_HEIGHT * 2U)
#define RS_P9_QVGA_WORDS (RS_P9_QVGA_BYTES / sizeof(uint32_t))
#ifndef RS_TINY_P9_QUICK
#define RS_P9_FRAME_ADDR UINT32_C(0x54010000)
#endif

static _Alignas(64) uint32_t rs_p9_pio_words[32];
static uint32_t rs_p9_dma_bytes;
static uint32_t rs_p9_word_count;
static uint32_t rs_p9_pixel_count;
static uint32_t rs_p9_xpi_error;
static bool rs_p9_readback;
#ifdef RS_TINY_P9_QUICK
static _Alignas(64) uint32_t rs_p9_frame[RS_P9_QVGA_WORDS + 2U];
#endif

static void rs_p9_boot_fail(uint8_t code) {
    rs_sysctrl_write_test_status(false, code);
    for (;;) {
    }
}

static void rs_p9_finish(bool pass, uint8_t code) {
    printf("Tiny P9 %s code=%u\n", pass ? "passed" : "failed", code);
    rs_sysctrl_write_test_status(pass, code);
    for (;;) {
    }
}

static bool rs_p9_camera_pins(void) {
    const rs_gpio_config_t camera = {
        .mode = RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    printf("P9_STAGE CAMERA_PINS_START\n");
    for (uint32_t pin = 12U; pin <= 23U; pin++) {
        if (rs_gpio_configure(pin, &camera) != RS_OK) {
            printf("P9_STAGE CAMERA_PIN_FAIL pin=%u\n", pin);
            return false;
        }
        if ((pin & 3U) == 3U) {
            printf("P9_STAGE CAMERA_PIN pin=%u\n", pin);
        }
    }
    printf("P9_STAGE CAMERA_PINS_DONE\n");
    return true;
}

static bool rs_p9_dma_frame(uintptr_t destination) {
    const rs_dvp_config_t config = {
        .format = RS_P9_FORMAT,
        .frame_width = RS_P9_QVGA_WIDTH,
        .frame_height = RS_P9_QVGA_HEIGHT,
        .crop_width = RS_P9_QVGA_WIDTH,
        .crop_height = RS_P9_QVGA_HEIGHT,
        .snapshot = true,
        .stream_enable = true,
    };
    volatile uint32_t *const frame = (volatile uint32_t *)destination;
    volatile uint32_t *prefix_guard;
    rs_dvp_status_t status;
    rs_dma_status_t dma_status;
    uint32_t expected_words = 0U;
    if (rs_p9_frame_words(RS_P9_QVGA_WIDTH, RS_P9_QVGA_HEIGHT, &expected_words) != RS_OK ||
        expected_words != RS_P9_QVGA_WORDS) {
        return false;
    }
    if (destination < sizeof(uint32_t)) {
        return false;
    }
    prefix_guard = (volatile uint32_t *)(destination - sizeof(uint32_t));
    if (rs_dvp_configure(&config) != RS_OK) {
        printf("P9_STAGE DVP_CONFIG_FAIL\n");
        return false;
    }
    printf("P9_STAGE DMA_CAPTURE_START\n");
    *prefix_guard = UINT32_C(0x13579bdf);
    frame[RS_P9_QVGA_WORDS] = UINT32_C(0x2468ace0);
    if (rs_dvp_capture_dma(destination, RS_P9_QVGA_WORDS, RS_TIMEOUT_DEFAULT) != RS_OK ||
        rs_dvp_get_status(&status) != RS_OK || status.error_status != 0U ||
        status.pixel_count != RS_P9_QVGA_WIDTH * RS_P9_QVGA_HEIGHT ||
        *prefix_guard != UINT32_C(0x13579bdf) || frame[RS_P9_QVGA_WORDS] != UINT32_C(0x2468ace0)) {
        printf("P9_STAGE DMA_CAPTURE_FAIL\n");
        return false;
    }
    if (rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma_status) != RS_OK) {
        return false;
    }
    rs_p9_dma_bytes = dma_status.bytes_done;
    rs_p9_word_count = status.word_count;
    rs_p9_pixel_count = status.pixel_count;
    for (uint32_t index = 0U; index < RS_P9_QVGA_WORDS; index++) {
        const uint32_t row = index / (RS_P9_QVGA_WIDTH / 2U);
        const uint32_t column = index % (RS_P9_QVGA_WIDTH / 2U);
        const uint32_t expected = rs_p9_frame_word(row, column, false);
        if (frame[index] != expected) {
            printf("P9_STAGE READBACK_FAIL word=%u\n", index);
            return false;
        }
    }
#ifndef RS_TINY_P9_QUICK
    rs_xpi_error_t xpi_error;
    if (rs_xpi_error_get(&xpi_error) != RS_OK) {
        return false;
    }
    rs_p9_xpi_error = xpi_error.valid ? (uint32_t)xpi_error.code + 1U : 0U;
    if (rs_p9_xpi_error != 0U) {
        return false;
    }
#endif
    rs_p9_readback = true;
    printf("P9_STAGE DMA_CAPTURE_DONE\n");
    return true;
}

static bool rs_p9_pio_odd(void) {
    const rs_dvp_config_t config = {
        .format = RS_DVP_FORMAT_RGB565,
        .frame_width = RS_P9_QVGA_WIDTH,
        .frame_height = RS_P9_QVGA_HEIGHT,
        .crop_width = 7U,
        .crop_height = 3U,
        .crop_enable = true,
        .snapshot = true,
        .stream_enable = false,
    };
    for (uint32_t index = 0U; index < 32U; index++) {
        rs_p9_pio_words[index] = UINT32_C(0xdeadbeef);
    }
    if (rs_dvp_configure(&config) != RS_OK) {
        printf("P9_STAGE PIO_CONFIG_FAIL\n");
        return false;
    }
    if (rs_dvp_capture_pio((uintptr_t)&rs_p9_pio_words[1], 30U, 12U, RS_TIMEOUT_DEFAULT) != RS_OK) {
        printf("P9_STAGE PIO_CAPTURE_FAIL\n");
        return false;
    }
    if (rs_p9_pio_words[0] != UINT32_C(0xDEADBEEF) || rs_p9_pio_words[13] != UINT32_C(0xDEADBEEF)) {
        return false;
    }
    for (uint32_t index = 0U; index < 12U; index++) {
        const uint32_t first = ((index % 4U) * 4U + (index / 4U) * 3U) & UINT32_C(0xFF);
        uint32_t expected = (first << 8) | ((first + 1U) & UINT32_C(0xFF));
        if ((index % 4U) != 3U) {
            expected |=
                (((first + 2U) & UINT32_C(0xFF)) << 24) | (((first + 3U) & UINT32_C(0xFF)) << 16);
        }
        if (rs_p9_pio_words[index + 1U] != expected)
            return false;
    }
    printf("P9_PIO width=7 height=3 valid_bytes=42 storage_bytes=48 readback=1 guards=1\n");
    printf("P9_STAGE PIO_CAPTURE_DONE\n");
    return true;
}

int main(void) {
    uint32_t version;
    uint32_t capability;
    rs_tiny_rcu_snapshot_t snapshot;
#ifndef RS_TINY_P9_QUICK
    rs_xpi_psram_t psram;
#endif
    uintptr_t frame_destination;
    bool pass = true;
    uint8_t code = 0U;
    rs_tiny_rcu_snapshot_t startup_snapshot;

    __disable_irq();
    if ((rs_tiny_rcu_get_snapshot(&startup_snapshot) != RS_OK) ||
        !rs_p9_console_ready(&startup_snapshot, rs_uart_init)) {
        rs_p9_boot_fail(4U);
    } else if (!rs_p9_psram_pin_ready(rs_gpio_configure)) {
        rs_p9_boot_fail(2U);
    } else if (!rs_p9_camera_pins()) {
        printf("P9_STAGE CAMERA_PINS_FAIL\n");
        code = 1U;
    } else if (rs_tiny_rcu_set_clkout(1U, 1U) != RS_OK ||
               rs_tiny_rcu_get_snapshot(&snapshot) != RS_OK ||
               (snapshot.target_capability & (UINT32_C(1) << 14U)) == 0U ||
               rs_dvp_probe(&version, &capability) != RS_OK || version != UINT32_C(0x00020000)) {
        printf("P9_STAGE RCU_OR_DVP_PROBE_FAIL\n");
        code = 1U;
#ifdef RS_TINY_P9_QUICK
    } else {
        printf("P9_STAGE QUICK_BUFFER_READY\n");
        frame_destination = (uintptr_t)&rs_p9_frame[1];
        pass = rs_p9_dma_frame(frame_destination);
        if (pass) {
            pass = rs_p9_pio_odd();
        }
        if (!pass) {
            code = 3U;
        }
    }
#else
    } else {
        printf("P9_STAGE PSRAM_INIT_START\n");
        if (rs_xpi_psram_initialize(snapshot.mem_hz, RS_TIMEOUT_DEFAULT, &psram) != RS_OK ||
            rs_xpi_psram_validate_dma(&psram, RS_P9_FRAME_ADDR, RS_P9_QVGA_BYTES, 4U) != RS_OK) {
            printf("P9_STAGE PSRAM_INIT_FAIL\n");
            code = 2U;
        } else {
            printf("P9_STAGE PSRAM_INIT_DONE\n");
            frame_destination = RS_P9_FRAME_ADDR;
            pass = rs_p9_dma_frame(frame_destination);
            if (pass) {
                pass = rs_p9_pio_odd();
            }
            if (!pass) {
                code = 3U;
            }
        }
    }
#endif
    pass = pass && code == 0U;
    printf("P9_FRAME format=%u width=%u height=%u bytes=%u dma_bytes=%u dma_channel=2 request=11 "
           "guards=%u readback=%u\n",
           (unsigned int)RS_P9_FORMAT, RS_P9_QVGA_WIDTH, RS_P9_QVGA_HEIGHT, RS_P9_QVGA_BYTES,
           rs_p9_dma_bytes, pass ? 1U : 0U, rs_p9_readback ? 1U : 0U);
    printf("P9_COUNTS words=%u pixels=%u xpi_error=%u\n", rs_p9_word_count, rs_p9_pixel_count,
           rs_p9_xpi_error);
    printf("P9_RESULT code=%u frames=%u bytes=%u\n", code, pass ? 1U : 0U,
           pass ? RS_P9_QVGA_BYTES : 0U);
    (void)rs_tiny_rcu_set_clkout(0U, 0U);
    rs_p9_finish(pass && code == 0U, code);
}
