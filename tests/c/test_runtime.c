#include <stddef.h>
#include <stdint.h>

#include <ps2_keyboard.h>
#include <ps2_mouse.h>

#include <retrosoc/core/status.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/hal/sdram.h>
#include <retrosoc/hal/sdio.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/usb2.h>
#include <retrosoc/hal/user_ip.h>
#include <retrosoc/hal/ws2812.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/lib/stdlib.h>
#include <retrosoc/lib/string.h>
#include <retrosoc/media/video_player.h>
#include <retrosoc/media/wav_audio.h>

#include "../../crt/src/hal/opipsram_math.c"

#define TEST_STORAGE_ADDRESS ((uintptr_t)0x1000U)

int __clzsi2(unsigned int value);
long long __divdi3(long long dividend, long long divisor);
int __ffssi2(unsigned int value);
unsigned long long __udivdi3(unsigned long long dividend, unsigned long long divisor);
unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor);

static uint8_t storage[32];
static uint32_t image_call_count;

void putch(char ch) {
    (void)ch;
}

void lcd_fill_image(uint16_t x_start, uint16_t y_start, uint16_t x_end, uint16_t y_end,
                    uint32_t *data) {
    (void)x_start;
    (void)y_start;
    (void)x_end;
    (void)y_end;
    (void)data;
    ++image_call_count;
}

rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address) {
    size_t offset;

    if ((buffer == NULL) || (address < TEST_STORAGE_ADDRESS)) {
        return RS_EINVAL;
    }
    offset = (size_t)(address - TEST_STORAGE_ADDRESS);
    if (byte_count > (sizeof(storage) - offset)) {
        return RS_EIO;
    }
    for (size_t index = 0U; index < byte_count; ++index) {
        ((uint8_t *)buffer)[index] = storage[offset + index];
    }
    return RS_OK;
}

static rs_status_t test_reader_read(void *context, uint32_t offset, void *buffer,
                                    size_t byte_count) {
    const uint8_t *bytes = context;

    if ((bytes == NULL) || (buffer == NULL)) {
        return RS_EINVAL;
    }
    for (size_t index = 0U; index < byte_count; ++index) {
        ((uint8_t *)buffer)[index] = bytes[offset + index];
    }
    return RS_OK;
}

static int test_string_helpers(void) {
    char buffer[8] = {'x', '\0'};
    int32_t value;

    if (strncpy(buffer, "z", 0U) != buffer || buffer[0] != 'x') {
        return 1;
    }
    if (strncmp("left", "right", 0U) != 0) {
        return 2;
    }
    if (rs_strlcpy(buffer, "abcdefghi", sizeof(buffer)) != 9U || strcmp(buffer, "abcdefg") != 0) {
        return 3;
    }
    if (rs_strlcat(buffer, "x", sizeof(buffer)) != 8U || strcmp(buffer, "abcdefg") != 0) {
        return 4;
    }
    if (rs_strtoi32("-2147483648", &value) != RS_OK || value != INT32_MIN ||
        rs_strtoi32("2147483648", &value) != RS_EFORMAT ||
        rs_strtoi32("12x", &value) != RS_EFORMAT) {
        return 5;
    }
    return 0;
}

static int test_formatter(void) {
    char buffer[32];

    if (rs_snprintf(buffer, sizeof(buffer), "%#08x:%lld:%zu", 0x2AU, -42LL, (size_t)7U) != 14 ||
        strcmp(buffer, "0x00002a:-42:7") != 0) {
        return 1;
    }
    if (rs_snprintf(buffer, 4U, "abcdef") != 6 || strcmp(buffer, "abc") != 0) {
        return 2;
    }
    if (rs_snprintf(NULL, 0U, "value=%llu", UINT64_MAX) != 26) {
        return 3;
    }
    if (rs_snprintf(buffer, sizeof(buffer), "%p", (void *)(uintptr_t)0x1234U) != 6 ||
        strcmp(buffer, "0x1234") != 0) {
        return 4;
    }
    return 0;
}

static int test_compiler_helpers(void) {
    if ((__clzsi2(0U) != 32) || (__clzsi2(1U) != 31) || (__ffssi2(0U) != 0) ||
        (__ffssi2(1U) != 1) || (__ffssi2(0x10U) != 5)) {
        return 1;
    }
    if ((__udivdi3(UINT64_MAX, 3U) != 6148914691236517205ULL) ||
        (__umoddi3(UINT64_MAX, 3U) != 0U) || (__udivdi3(UINT64_MAX, UINT64_MAX) != 1U) ||
        (__umoddi3(100U, 7U) != 2U) || (__divdi3(-100LL, 7LL) != -14LL)) {
        return 2;
    }
    return 0;
}

static int test_wait_helper(void) {
    volatile uint32_t value = 0x30U;

    if (rs_wait_mask(&value, 0x30U, 0x30U, 1U) != RS_OK ||
        rs_wait_mask(&value, 0x40U, 0x40U, 1U) != RS_ETIMEOUT ||
        rs_wait_mask(NULL, 1U, 1U, 1U) != RS_EINVAL || rs_wait_value(&value, 0x30U, 1U) != RS_OK ||
        rs_wait_not_value(&value, 0U, 1U) != RS_OK ||
        rs_wait_not_value(&value, 0x30U, 1U) != RS_ETIMEOUT) {
        return 1;
    }
    return 0;
}

static int test_ws2812_helpers(void) {
    const rs_ws2812_config_t config = {
        72000000U,
        RS_WS2812_DEFAULT_BIT_PERIOD_NS,
        RS_WS2812_DEFAULT_T0H_NS,
        RS_WS2812_DEFAULT_T1H_NS,
        RS_WS2812_DEFAULT_RESET_NS,
        4U,
    };
    rs_ws2812_config_t invalid = config;
    rs_ws2812_timing_t timing;

    if ((rs_ws2812_pack_grb(0x12U, 0x34U, 0x56U) != UINT32_C(0x341256)) ||
        (rs_ws2812_timing_from_ns(&config, &timing) != RS_OK) || (timing.bit_cycles != 90U) ||
        (timing.t0h_cycles != 25U) || (timing.t1h_cycles != 50U) ||
        (timing.reset_cycles != 21600U)) {
        return 1;
    }
    invalid.t0h_ns = invalid.t1h_ns;
    if ((rs_ws2812_timing_from_ns(&invalid, &timing) != RS_EINVAL) ||
        (rs_ws2812_timing_from_ns(NULL, &timing) != RS_EINVAL) ||
        (rs_ws2812_timing_from_ns(&config, NULL) != RS_EINVAL)) {
        return 2;
    }
    invalid = config;
    invalid.source_clock_hz = 1U;
    if (rs_ws2812_timing_from_ns(&invalid, &timing) != RS_EINVAL) {
        return 3;
    }
    return 0;
}

static int test_timer_helpers(void) {
    rs_timer_period_t period;

    if ((rs_timer_period_from_ms(72000000U, 1U, &period) != RS_OK) || (period.prescale != 0U) ||
        (period.load != 71999U)) {
        return 1;
    }

    if ((rs_timer_period_from_ms(72000000U, 1000U, &period) != RS_OK) || (period.prescale != 0U) ||
        (period.load != 71999999U)) {
        return 2;
    }
    if ((rs_timer_period_from_ms(0U, 1U, &period) != RS_EINVAL) ||
        (rs_timer_period_from_ms(72000000U, 0U, &period) != RS_EINVAL) ||
        (rs_timer_period_from_ms(72000000U, 1U, NULL) != RS_EINVAL) ||
        (rs_timer_period_from_ms(UINT32_MAX, UINT32_MAX, &period) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_i2s_helpers(void) {
    uint8_t sclk_div;
    uint8_t lrck_div;
    uint16_t first;
    uint16_t second;

    if (rs_i2s_pack_stereo16(0x1111U, 0x2222U) != UINT32_C(0x22221111))
        return 1;
    rs_i2s_unpack_stereo16(UINT32_C(0x22221111), &first, &second);
    if ((first != 0x1111U) || (second != 0x2222U))
        return 2;
    if ((rs_i2s_div_from_hz(18432000U, 48000U, 16U, &sclk_div, &lrck_div) != RS_OK) ||
        (sclk_div != 5U) || (lrck_div != 15U))
        return 3;
    if ((rs_i2s_div_from_hz(18432000U, 96000U, 24U, &sclk_div, &lrck_div) != RS_OK) ||
        (sclk_div != 1U) || (lrck_div != 23U))
        return 4;
    if ((rs_i2s_rxdata_address() - rs_i2s_txdata_address()) != (uintptr_t)4U)
        return 6;
    if ((rs_i2s_div_from_hz(0U, 48000U, 16U, &sclk_div, &lrck_div) != RS_EINVAL) ||
        (rs_i2s_div_from_hz(18432000U, 48000U, 20U, &sclk_div, &lrck_div) != RS_EINVAL) ||
        (rs_i2s_div_from_hz(18432000U, 48000U, 16U, NULL, &lrck_div) != RS_EINVAL))
        return 5;
    return 0;
}

static int test_sdram_helpers(void) {
    rs_sdram_timing_t timing;

    if ((rs_sdram_timing_from_hz(72000000U, 0U, &timing) != RS_OK) || (timing.trp_cycles != 1U) ||
        (timing.trcd_cycles != 1U) || (timing.tras_cycles != 2U) || (timing.trc_cycles != 3U) ||
        (timing.twr_cycles != 1U) || (timing.trfc_cycles != 3U) || (timing.trrd_cycles != 2U) ||
        (timing.twtr_cycles != 2U) || (timing.trtp_cycles != 1U) || (timing.tmrd_cycles != 2U) ||
        (timing.txsr_cycles != 3U) || (timing.trefi_cycles != 281U) ||
        (timing.powerup_cycles != 3600U) || (timing.actual_sdram_hz != 36000000U)) {
        return 1;
    }
    if ((rs_sdram_timing_from_hz(0U, 0U, &timing) != RS_EINVAL) ||
        (rs_sdram_timing_from_hz(72000000U, 4U, &timing) != RS_EINVAL) ||
        (rs_sdram_timing_from_hz(72000000U, 0U, NULL) != RS_EINVAL)) {
        return 2;
    }
    return 0;
}

static int test_psram_helpers(void) {
    rs_psram_timing_t timing;

    if ((rs_psram_timing_from_hz(72000000U, 36000000U, &timing) != RS_OK) ||
        (timing.half_period_cycles != 1U) || (timing.cs_setup_cycles != 1U) ||
        (timing.cs_high_cycles != 4U) || (timing.cs_hold_cycles != 3U) ||
        (timing.powerup_cycles != 10800U) || (timing.cs_max_low_cycles != 576U) ||
        (timing.actual_sclk_hz != 36000000U) || timing.above_84mhz) {
        return 1;
    }
    if ((rs_psram_timing_from_hz(192000000U, 133000000U, &timing) != RS_OK) ||
        (timing.half_period_cycles != 1U) || (timing.actual_sclk_hz != 96000000U) ||
        !timing.above_84mhz) {
        return 2;
    }
    if ((rs_psram_timing_from_hz(0U, 36000000U, &timing) != RS_EINVAL) ||
        (rs_psram_timing_from_hz(72000000U, 0U, &timing) != RS_EINVAL) ||
        (rs_psram_timing_from_hz(72000000U, 134000000U, &timing) != RS_EINVAL) ||
        (rs_psram_timing_from_hz(72000000U, 36000000U, NULL) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_opipsram_helpers(void) {
    rs_opipsram_config_t config = {
        .profile = RS_OPIPSRAM_PROFILE_OPI,
        .device_size = UINT32_C(0x00800000),
        .timing =
            {
                .divider = 1U,
                .phy_ratio = 2U,
                .source_clock_hz = 72000000U,
                .requested_ck_hz = 36000000U,
                .actual_phy_hz = 72000000U,
                .actual_ck_hz = 36000000U,
                .cs_setup_cycles = 1U,
                .cs_hold_cycles = 2U,
                .cs_high_cycles = 4U,
                .powerup_cycles = 10800U,
                .timeout_cycles = 720000U,
            },
        .opi =
            {
                .read_command = UINT16_C(0xEE11),
                .write_command = UINT16_C(0x12ED),
                .register_read_command = UINT16_C(0),
                .register_write_command = UINT16_C(0),
                .command_width = RS_OPIPSRAM_COMMAND_WIDTH_16,
                .address_width = RS_OPIPSRAM_ADDRESS_WIDTH_32,
                .dummy_cycles = 8U,
                .latency_cycles = 6U,
                .dqs_policy = RS_OPIPSRAM_DQS_READ_WRITE,
                .burst_boundary = 32U,
            },
        .hyperbus =
            {
                .initial_latency = 6U,
                .additional_latency = 2U,
                .read_recovery_cycles = 4U,
                .write_recovery_cycles = 4U,
                .rwds_additional_latency = true,
            },
        .enable = true,
        .memory_enable = true,
        .auto_initialize = false,
        .line_buffer = true,
    };
    rs_opipsram_timing_t timing;
    rs_opipsram_training_window_t window;
    rs_dma_config_t dma_config;
    rs_opipsram_indirect_t indirect = {
        .write = false,
        .register_space = false,
        .length = 8U,
        .address = UINT32_C(0x007FFFF8),
        .write_data = UINT64_C(0),
    };

    if ((RS_OPIPSRAM_CMD_WIDTH_SHIFT != UINT32_C(16)) ||
        (RS_OPIPSRAM_CMD_WIDTH_MASK != UINT32_C(0x00010000)) ||
        (RS_OPIPSRAM_OPI_TIMING_ADDR_BYTES_MASK != UINT32_C(0x00000003)) ||
        (RS_OPIPSRAM_OPI_TIMING_DUMMY_SHIFT != UINT32_C(2)) ||
        (RS_OPIPSRAM_OPI_TIMING_DUMMY_MASK != UINT32_C(0x000003FC)) ||
        (RS_OPIPSRAM_OPI_TIMING_LATENCY_SHIFT != UINT32_C(10)) ||
        (RS_OPIPSRAM_OPI_TIMING_LATENCY_MASK != UINT32_C(0x00007C00)) ||
        (RS_OPIPSRAM_OPI_TIMING_DQS_READ != UINT32_C(0x00008000)) ||
        (RS_OPIPSRAM_OPI_TIMING_DQS_WRITE != UINT32_C(0x00010000)) ||
        (RS_OPIPSRAM_HYPER_TIMING_RWDS_LATENCY_ENABLE != UINT32_C(0x80000000)) ||
        (RS_OPIPSRAM_CLK_PHY_RATIO_MASK != UINT32_C(0x00010000)) ||
        (RS_OPIPSRAM_CLK_PHY_RATIO_2X != UINT32_C(0x00010000)) ||
        (RS_OPIPSRAM_PROFILE_STATUS_LOCKED != UINT32_C(0x00000002)) ||
        (RS_OPIPSRAM_PROFILE_STATUS_VALID != UINT32_C(0x00000004)) ||
        (RS_OPIPSRAM_PROFILE_STATUS_ERROR_MASK != UINT32_C(0x00000008))) {
        return 1;
    }
    if ((rs_opipsram_timing_from_hz(72000000U, 36000000U, &timing) != RS_OK) ||
        (timing.divider != 1U) || (timing.phy_ratio != 2U) || (timing.actual_phy_hz != 72000000U) ||
        (timing.actual_ck_hz != 36000000U) || (timing.powerup_cycles != 10800U)) {
        return 2;
    }
    if ((rs_opipsram_timing_from_hz(144000000U, 72000000U, &timing) != RS_OK) ||
        (timing.actual_ck_hz != 72000000U) ||
        (rs_opipsram_timing_from_hz(200000000U, 100000000U, &timing) != RS_OK) ||
        (timing.actual_ck_hz != 100000000U)) {
        return 3;
    }
    if ((rs_opipsram_timing_from_hz(192000000U, 48000000U, &timing) != RS_OK) ||
        (timing.divider != 2U) || (timing.actual_phy_hz != 96000000U) ||
        (timing.actual_ck_hz != 48000000U) ||
        (rs_opipsram_timing_from_hz(UINT32_MAX, 36000000U, &timing) != RS_EINVAL)) {
        return 4;
    }
    if ((rs_opipsram_timing_from_hz(0U, 36000000U, &timing) != RS_EINVAL) ||
        (rs_opipsram_timing_from_hz(72000000U, 0U, &timing) != RS_EINVAL) ||
        (rs_opipsram_timing_from_hz(72000000U, 35999999U, &timing) != RS_EINVAL) ||
        (rs_opipsram_timing_from_hz(72000000U, 100000001U, &timing) != RS_EINVAL) ||
        (rs_opipsram_timing_from_hz(72000000U, 36000000U, NULL) != RS_EINVAL)) {
        return 5;
    }
    if (rs_opipsram_config_validate(&config) != RS_OK) {
        return 6;
    }
    config.device_size = UINT32_C(0x00600000);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 7;
    }
    config.device_size = RS_OPIPSRAM_MAX_DEVICE_SIZE + UINT32_C(1);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 8;
    }
    config.device_size = UINT32_C(0x00800000);
    config.opi.address_width = (rs_opipsram_address_width_t)5U;
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 9;
    }
    config.opi.address_width = RS_OPIPSRAM_ADDRESS_WIDTH_32;
    config.opi.dummy_cycles = RS_OPIPSRAM_MAX_DUMMY_CYCLES + UINT8_C(1);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 10;
    }
    config.opi.dummy_cycles = 8U;
    config.opi.latency_cycles = RS_OPIPSRAM_MAX_LATENCY_CYCLES + UINT8_C(1);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 11;
    }
    config.opi.latency_cycles = 6U;
    config.profile = RS_OPIPSRAM_PROFILE_HYPERBUS;
    config.hyperbus.initial_latency = RS_OPIPSRAM_MAX_LATENCY_CYCLES + UINT8_C(1);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 12;
    }
    config.hyperbus.initial_latency = 6U;
    config.hyperbus.write_recovery_cycles = UINT8_C(128);
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 13;
    }
    config.hyperbus.write_recovery_cycles = 4U;
    config.profile = RS_OPIPSRAM_PROFILE_OPI;
    config.timing.timeout_cycles = config.timing.powerup_cycles;
    if (rs_opipsram_config_validate(&config) != RS_EINVAL) {
        return 14;
    }
    if ((rs_opipsram_training_window_from_mask(UINT32_C(0xC3), 8U, &window) != RS_OK) ||
        !window.valid || !window.wrapped || (window.first != 6U) || (window.last != 1U) ||
        (window.width != 4U) || (window.center != 0U)) {
        return 15;
    }
    if ((rs_opipsram_training_window_from_mask(UINT32_C(0), 8U, &window) != RS_OK) ||
        window.valid || (window.width != 0U)) {
        return 16;
    }
    if ((rs_opipsram_training_window_from_mask(UINT32_C(0x0E), 8U, &window) != RS_OK) ||
        !window.valid || window.wrapped || (window.first != 1U) || (window.last != 3U) ||
        (window.width != 3U) || (window.center != 2U)) {
        return 17;
    }
    if ((rs_opipsram_training_window_from_mask(UINT32_C(0x01), 0U, &window) != RS_EINVAL) ||
        (rs_opipsram_training_window_from_mask(UINT32_C(0x01), 33U, &window) != RS_EINVAL)) {
        return 18;
    }
    if ((rs_opipsram_dma_copy_validate(RS_DMA_CHANNEL_BULK, (uintptr_t)0x40001000U,
                                       (uintptr_t)RS_SOC_OPIPSRAM_BASE, 64U, 1U, 8U,
                                       &dma_config) != RS_OK) ||
        (dma_config.kind != RS_DMA_KIND_MM_TO_MM) ||
        (dma_config.request != RS_DMA_REQUEST_SOFTWARE)) {
        return 19;
    }
    if (rs_opipsram_dma_copy_validate(RS_DMA_CHANNEL_BULK, (uintptr_t)0x40001002U,
                                      (uintptr_t)RS_SOC_OPIPSRAM_BASE, 64U, 1U, 8U,
                                      &dma_config) != RS_EINVAL) {
        return 20;
    }
    if (rs_opipsram_indirect_validate(&indirect, UINT32_C(0x00800000)) != RS_OK) {
        return 21;
    }
    indirect.address = UINT32_C(0x007FFFF9);
    if (rs_opipsram_indirect_validate(&indirect, UINT32_C(0x00800000)) != RS_EINVAL) {
        return 22;
    }
    indirect.register_space = true;
    indirect.address = UINT32_MAX;
    if (rs_opipsram_indirect_validate(&indirect, UINT32_C(0)) != RS_EINVAL) {
        return 23;
    }
    indirect.address = UINT32_C(0x00FFFFFF);
    if (rs_opipsram_indirect_validate(&indirect, UINT32_C(0)) != RS_OK) {
        return 24;
    }
    return 0;
}

static int test_uart_helpers(void) {
    rs_uart_timing_t timing;

    if ((rs_uart_timing_calculate(72000000U, 921600U, &timing) != RS_OK) ||
        (timing.baud_integer != 78U) || (timing.baud_fraction != 32U)) {
        return 1;
    }
    if ((rs_uart_timing_calculate(16000000U, 1000000U, &timing) != RS_OK) ||
        (timing.baud_integer != 16U) || (timing.baud_fraction != 0U)) {
        return 2;
    }
    if ((rs_uart_timing_calculate(0U, 115200U, &timing) != RS_EINVAL) ||
        (rs_uart_timing_calculate(72000000U, 0U, &timing) != RS_EINVAL) ||
        (rs_uart_timing_calculate(1000000U, 1000000U, &timing) != RS_EINVAL) ||
        (rs_uart_timing_calculate(72000000U, 115200U, NULL) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_i2c_helpers(void) {
    rs_i2c_timing_t timing;

    if ((rs_i2c_timing_calculate(72000000U, 400000U, &timing) != RS_OK) ||
        (timing.scl_low_cycles != 136U) || (timing.scl_high_cycles != 44U) ||
        (timing.start_hold_cycles != 44U) || (timing.start_setup_cycles != 44U) ||
        (timing.data_setup_cycles != 8U) || (timing.stop_setup_cycles != 44U) ||
        (timing.bus_free_cycles != 94U)) {
        return 1;
    }
    if ((rs_i2c_timing_calculate(72000000U, 1000000U, &timing) != RS_OK) ||
        (timing.scl_low_cycles != 53U) || (timing.scl_high_cycles != 19U) ||
        (timing.data_setup_cycles != 4U)) {
        return 2;
    }
    if ((rs_i2c_timing_calculate(0U, 400000U, &timing) != RS_EINVAL) ||
        (rs_i2c_timing_calculate(72000000U, 0U, &timing) != RS_EINVAL) ||
        (rs_i2c_timing_calculate(72000000U, 1000001U, &timing) != RS_EINVAL) ||
        (rs_i2c_timing_calculate(72000000U, 400000U, NULL) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_sdio_helpers(void) {
    rs_sdio_clock_t clock;
    rs_sdio_response_t csd = {{0U, 0U, 0U, 0U, 0U}};
    rs_sdio_cmd52_t cmd52 = {
        .function = 2U,
        .address = UINT32_C(0x123),
        .write = true,
        .raw = false,
        .data = UINT8_C(0xA5),
    };
    rs_sdio_cmd53_t cmd53 = {
        .function = 1U,
        .address = UINT32_C(0x100),
        .count = UINT16_C(512),
        .write = true,
        .block_mode = true,
        .fixed_address = false,
    };
    rs_sdio_descriptor_t descriptor;
    rs_sd_memory_info_t info = {0};
    uint32_t value;

    if ((rs_sdio_clock_calculate(72000000U, 400000U, &clock) != RS_OK) ||
        (clock.half_period != 90U) || (clock.actual_hz != 400000U) ||
        (rs_sdio_clock_calculate(100000000U, 50000000U, &clock) != RS_OK) ||
        (clock.half_period != 1U) || (clock.actual_hz != 50000000U)) {
        return 1;
    }
    if ((rs_sdio_clock_calculate(0U, 400000U, &clock) != RS_EINVAL) ||
        (rs_sdio_clock_calculate(72000000U, 0U, &clock) != RS_EINVAL) ||
        (rs_sdio_clock_calculate(72000000U, 40000001U, &clock) != RS_EINVAL) ||
        (rs_sdio_clock_calculate(72000000U, 400000U, NULL) != RS_EINVAL)) {
        return 2;
    }
    if ((rs_sd_memory_address(RS_SD_MEMORY_SDSC, 2U, &value) != RS_OK) || (value != 1024U) ||
        (rs_sd_memory_address(RS_SD_MEMORY_SDHC, 2U, &value) != RS_OK) || (value != 2U) ||
        (rs_sdio_cmd52_argument(&cmd52, &value) != RS_OK) || (value != UINT32_C(0xA00246A5)) ||
        (rs_sdio_cmd53_argument(&cmd53, &value) != RS_OK) || (value != UINT32_C(0x9C020000))) {
        return 3;
    }
    if ((rs_sdio_validate_dma_buffer((const void *)(uintptr_t)UINT32_C(0x40000000), 4U) != RS_OK) ||
        (rs_sdio_validate_dma_buffer((const void *)(uintptr_t)UINT32_C(0x40000002), 4U) !=
         RS_EINVAL) ||
        (rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)UINT32_C(0x40000000), 64U,
                                    (uintptr_t)0U, true, true) != RS_OK) ||
        (rs_sdio_descriptor_validate(&descriptor) != RS_OK) ||
        (rs_sdio_descriptor_publish(&descriptor) != RS_OK) ||
        ((descriptor.control_status & (UINT32_C(1) << RS_SDIO_DESC_OWN_BIT)) == 0U)) {
        return 4;
    }
    if (rs_sdio_descriptor_prepare(&descriptor, (uintptr_t)UINT32_C(0x40000000), 64U,
                                   (uintptr_t)UINT32_C(0x40000FF0), false, false) != RS_EINVAL) {
        return 5;
    }
    descriptor.buffer_addr = UINT32_C(0x40000000);
    descriptor.byte_count = 64U;
    descriptor.next_addr = UINT32_C(0x40000FF0);
    descriptor.control_status = UINT32_C(0x00000003);
    if (rs_sdio_descriptor_validate(&descriptor) != RS_EINVAL) {
        return 6;
    }
    for (uint32_t bit = 48U; bit <= 69U; bit++) {
        if (((UINT32_C(0x3FF) >> (bit - 48U)) & 1U) != 0U) {
            csd.words[bit / 32U] |= UINT32_C(1) << (bit % 32U);
        }
    }
    csd.words[3] |= UINT32_C(1) << (126U - 96U);
    if ((rs_sd_memory_parse_csd(&csd, &info) != RS_OK) || (info.card_type != RS_SD_MEMORY_SDHC) ||
        (info.capacity_blocks != UINT32_C(0x100000)) ||
        (info.block_length != RS_SD_MEMORY_BLOCK_SIZE)) {
        return 5;
    }
    return 0;
}

static int test_usb2_helpers(void) {
    _Alignas(32) rs_usb2_descriptor_t descriptors[2];

    if ((rs_usb2_validate_dma_buffer((const void *)(uintptr_t)UINT32_C(0x40000000), 4U) != RS_OK) ||
        (rs_usb2_validate_dma_buffer((const void *)(uintptr_t)UINT32_C(0x40000002), 4U) !=
         RS_EINVAL) ||
        (rs_usb2_descriptor_prepare(&descriptors[0], (uintptr_t)UINT32_C(0x40000000), 64U,
                                    (uintptr_t)UINT32_C(0x40000020), false, false, true, false,
                                    UINT32_C(0x1234)) != RS_OK) ||
        (rs_usb2_descriptor_prepare(&descriptors[1], (uintptr_t)UINT32_C(0x40000100), 64U,
                                    (uintptr_t)0U, true, true, false, false,
                                    UINT32_C(0x1235)) != RS_OK) ||
        (rs_usb2_descriptor_chain_validate(descriptors, 2U, 128U) != RS_OK) ||
        (rs_usb2_descriptor_publish_chain(descriptors, 2U) != RS_OK) ||
        ((descriptors[0].control & RS_USB2_DESC_OWN) == 0U) ||
        ((descriptors[1].control & RS_USB2_DESC_OWN) == 0U)) {
        return 1;
    }
    if ((rs_usb2_descriptor_prepare(&descriptors[0], (uintptr_t)UINT32_C(0xFFFFFFFC), 8U,
                                    (uintptr_t)0U, true, false, false, false, 0U) != RS_EINVAL) ||
        (rs_usb2_descriptor_prepare(&descriptors[0], (uintptr_t)UINT32_C(0x40000000), 64U,
                                    (uintptr_t)UINT32_C(0x40000FE4), false, false, false, false,
                                    0U) != RS_EINVAL) ||
        (rs_usb2_descriptor_prepare(NULL, (uintptr_t)UINT32_C(0x40000000), 64U, (uintptr_t)0U, true,
                                    false, false, false, 0U) != RS_EINVAL)) {
        return 2;
    }
    return 0;
}

static int test_spisd_helpers(void) {
    rs_spisd_clock_t clock;
    rs_spisd_card_info_t info = {0};
    rs_spisd_descriptor_t descriptor;
    uint8_t csd_v2[16] = {0};
    uint8_t csd_v1[16] = {0};
    uint32_t argument;

    if ((rs_spisd_clock_calculate(72000000U, 400000U, &clock) != RS_OK) ||
        (clock.half_period != 90U) || (clock.actual_hz != 400000U) ||
        (rs_spisd_clock_calculate(72000000U, 36000000U, &clock) != RS_OK) ||
        (clock.half_period != 1U) || (clock.actual_hz != 36000000U)) {
        return 1;
    }
    if ((rs_spisd_clock_calculate(0U, 400000U, &clock) != RS_EINVAL) ||
        (rs_spisd_clock_calculate(72000000U, 36000001U, &clock) != RS_EINVAL) ||
        (rs_spisd_clock_calculate(72000000U, 400000U, NULL) != RS_EINVAL)) {
        return 2;
    }
    if ((rs_spisd_card_address(RS_SPISD_CARD_SDSC, 2U, &argument) != RS_OK) ||
        (argument != 1024U) ||
        (rs_spisd_card_address(RS_SPISD_CARD_SDHC, 2U, &argument) != RS_OK) || (argument != 2U) ||
        (rs_spisd_card_address((rs_spisd_card_type_t)2U, 0U, &argument) != RS_EINVAL)) {
        return 3;
    }
    csd_v2[0] = UINT8_C(0x40);
    csd_v2[8] = UINT8_C(0x03);
    csd_v2[9] = UINT8_C(0xFF);
    if ((rs_spisd_parse_csd(csd_v2, &info) != RS_OK) || !info.high_capacity ||
        (info.card_type != RS_SPISD_CARD_SDHC) || (info.capacity_blocks != UINT32_C(0x00100000))) {
        return 4;
    }
    csd_v1[5] = UINT8_C(9);
    csd_v1[7] = UINT8_C(0xFF);
    csd_v1[8] = UINT8_C(0xC0);
    csd_v1[9] = UINT8_C(0x03);
    csd_v1[10] = UINT8_C(0x80);
    if ((rs_spisd_parse_csd(csd_v1, &info) != RS_OK) || info.high_capacity ||
        (info.card_type != RS_SPISD_CARD_SDSC) || (info.capacity_blocks != UINT32_C(0x00080000))) {
        return 5;
    }
    if ((rs_spisd_descriptor_prepare(&descriptor, (uintptr_t)UINT32_C(0x40000000), 64U,
                                     (uintptr_t)0U, true, true) != RS_OK) ||
        (rs_spisd_descriptor_validate(&descriptor) != RS_OK) ||
        (rs_spisd_descriptor_publish(&descriptor) != RS_OK) ||
        ((descriptor.control_status & RS_SPISD_DESC_OWN) == 0U)) {
        return 6;
    }
    if ((rs_spisd_descriptor_prepare(&descriptor, (uintptr_t)UINT32_C(0x40000002), 64U,
                                     (uintptr_t)0U, true, false) != RS_EINVAL) ||
        (rs_spisd_descriptor_prepare(&descriptor, (uintptr_t)UINT32_C(0x40000000), 64U,
                                     (uintptr_t)UINT32_C(0x40000FF0), false, false) != RS_EINVAL)) {
        return 7;
    }
    return 0;
}

static int test_gpio_helpers(void) {
    rs_gpio_filter_timing_t timing;

    if ((rs_gpio_filter_timing_from_us(72000000U, 2U, 3U, &timing) != RS_OK) ||
        (timing.divider != 143U) || (timing.stable_samples != 3U)) {
        return 1;
    }

    if ((rs_gpio_filter_timing_from_us(1U, 1U, 1U, &timing) != RS_OK) || (timing.divider != 0U)) {
        return 2;
    }
    if ((rs_gpio_filter_timing_from_us(0U, 1U, 1U, &timing) != RS_EINVAL) ||
        (rs_gpio_filter_timing_from_us(72000000U, 0U, 1U, &timing) != RS_EINVAL) ||
        (rs_gpio_filter_timing_from_us(72000000U, 2U, 0U, &timing) != RS_EINVAL) ||
        (rs_gpio_filter_timing_from_us(72000000U, 2U, 16U, &timing) != RS_EINVAL) ||
        (rs_gpio_filter_timing_from_us(72000000U, 1000U, 3U, &timing) != RS_EINVAL) ||
        (rs_gpio_filter_timing_from_us(72000000U, 2U, 3U, NULL) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_dma_config_validation(void) {
    static rs_dma_tcd_t tcd __attribute__((aligned(64)));
    rs_dma_config_t config = {
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = RS_DMA_REQUEST_SOFTWARE,
        .source = (uintptr_t)UINT32_C(0x40000000),
        .destination = (uintptr_t)UINT32_C(0x41000000),
        .byte_count = 64U,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = true,
        .priority = 1U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };

    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_OK) {
        return 1;
    }
    config.width = RS_DMA_WIDTH_16;
    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_EINVAL) {
        return 2;
    }
    config.width = RS_DMA_WIDTH_32;
    config.byte_count = 6U;
    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_OK) {
        return 3;
    }
    config.byte_count = 64U;
    config.kind = RS_DMA_KIND_MM_TO_STREAM;
    config.request = RS_DMA_REQUEST_I2S_TX;
    config.destination = (uintptr_t)0U;
    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_OK) {
        return 4;
    }
    config.byte_count = 6U;
    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_EINVAL) {
        return 6;
    }
    config.source_increment = false;
    if (rs_dma_config_validate(RS_DMA_CHANNEL_BULK, &config) != RS_EINVAL) {
        return 5;
    }
    tcd.next_ptr = 0U;
    tcd.source = UINT32_C(0x40000000);
    tcd.destination = UINT32_C(0x41000000);
    tcd.byte_count = 6U;
    tcd.source_stride = 0;
    tcd.destination_stride = 0;
    tcd.y_count = 1U;
    tcd.control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC | RS_DMA_TCD_DST_INC |
                  ((uint32_t)RS_DMA_KIND_MM_TO_MM << RS_DMA_TCD_KIND_SHIFT) |
                  ((uint32_t)RS_DMA_REQUEST_SOFTWARE << RS_DMA_TCD_REQUEST_SHIFT) |
                  (UINT32_C(1) << RS_DMA_TCD_PRIORITY_SHIFT) |
                  (UINT32_C(16) << RS_DMA_TCD_BURST_SHIFT);
    if (rs_dma_tcd_validate(RS_DMA_CHANNEL_BULK, &tcd) != RS_OK) {
        return 7;
    }
    tcd.control = RS_DMA_TCD_VALID | RS_DMA_TCD_SRC_INC |
                  ((uint32_t)RS_DMA_KIND_MM_TO_STREAM << RS_DMA_TCD_KIND_SHIFT) |
                  ((uint32_t)RS_DMA_REQUEST_I2S_TX << RS_DMA_TCD_REQUEST_SHIFT) |
                  (UINT32_C(1) << RS_DMA_TCD_PRIORITY_SHIFT);
    if (rs_dma_tcd_validate(RS_DMA_CHANNEL_BULK, &tcd) != RS_EINVAL) {
        return 8;
    }
    return 0;
}

static int test_user_ip_validation(void) {
    uint32_t value;

    if ((rs_user_ip_get_selected(NULL) != RS_EINVAL) ||
        (rs_user_ip_select(UINT8_MAX) != RS_EINVAL) ||
        (rs_user_ip_probe(UINT8_MAX, &value) != RS_EINVAL) ||
        (rs_user_ip_probe(0U, NULL) != RS_EINVAL)) {
        return 1;
    }
    if ((rs_user_ip_read(0U, NULL) != RS_EINVAL) || (rs_user_ip_read(1U, &value) != RS_EINVAL) ||
        (rs_user_ip_read(UINT32_C(0x1000), &value) != RS_EINVAL)) {
        return 2;
    }
    if ((rs_user_ip_write(2U, 0U) != RS_EINVAL) ||
        (rs_user_ip_write(UINT32_C(0x1000), 0U) != RS_EINVAL)) {
        return 3;
    }
    return 0;
}

static int test_ps2_decoders(void) {
    ps2_keyboard_decoder_t keyboard;
    ps2_mouse_decoder_t mouse;
    ps2_key_event_t key_event;
    ps2_mouse_event_t mouse_event;

    ps2_keyboard_decoder_init(&keyboard);
    if (!ps2_keyboard_decode_byte(&keyboard, UINT8_C(0x1C), &key_event) || !key_event.pressed ||
        key_event.extended || (key_event.scan_code != UINT16_C(0x001C))) {
        return 1;
    }
    if (ps2_keyboard_decode_byte(&keyboard, UINT8_C(0xE0), &key_event) ||
        ps2_keyboard_decode_byte(&keyboard, UINT8_C(0xF0), &key_event) ||
        !ps2_keyboard_decode_byte(&keyboard, UINT8_C(0x75), &key_event) || key_event.pressed ||
        !key_event.extended || (key_event.scan_code != UINT16_C(0xE075))) {
        return 2;
    }

    ps2_mouse_decoder_init(&mouse, UINT8_C(4));
    if (ps2_mouse_decode_byte(&mouse, UINT8_C(0x08), &mouse_event) ||
        ps2_mouse_decode_byte(&mouse, UINT8_C(0x02), &mouse_event) ||
        ps2_mouse_decode_byte(&mouse, UINT8_C(0x01), &mouse_event) ||
        !ps2_mouse_decode_byte(&mouse, UINT8_C(0x3F), &mouse_event) || (mouse_event.dx != 2) ||
        (mouse_event.dy != 1) || (mouse_event.wheel != -1) ||
        ((mouse_event.buttons & UINT8_C(0x18)) != UINT8_C(0x18))) {
        return 3;
    }
    return 0;
}

static int test_wav_parser(void) {
    static const uint8_t wav[] = {
        'R', 'I', 'F', 'F', 40U, 0U,  0U,  0U,  'W',   'A',   'V', 'E', 'f',   'm',   't', ' ',
        16U, 0U,  0U,  0U,  1U,  0U,  1U,  0U,  0x40U, 0x1FU, 0U,  0U,  0x80U, 0x3EU, 0U,  0U,
        2U,  0U,  16U, 0U,  'd', 'a', 't', 'a', 4U,    0U,    0U,  0U,  0U,    1U,    2U,  3U,
    };
    rs_wav_info_t info;
    const rs_wav_reader_t reader = {test_reader_read, (void *)wav, sizeof(wav)};

    if (rs_wav_parse(&reader, &info) != RS_OK || info.sample_rate != 8000U ||
        info.block_align != 2U || info.data_offset != 44U || info.data_size != 4U) {
        return 1;
    }
    if (rs_wav_parse(&(rs_wav_reader_t){test_reader_read, (void *)wav, 12U}, &info) != RS_EFORMAT) {
        return 2;
    }
    return 0;
}

static int test_video_parser(void) {
    rs_video_info_t info;

    (void)memset(storage, 0, sizeof(storage));
    storage[0] = 2U;
    storage[4] = 2U;
    storage[8] = 1U;
    if (rs_video_parse(storage, 24U, &info) != RS_OK || info.frame_size != 8U ||
        rs_video_parse(storage, 16U, &info) != RS_EFORMAT) {
        return 1;
    }
    image_call_count = 0U;
    if (rs_video_show_spisd(TEST_STORAGE_ADDRESS, 24U) != RS_OK || image_call_count != 1U) {
        return 2;
    }
    return 0;
}

int main(void) {
    const int results[] = {
        test_string_helpers(),        test_formatter(),        test_compiler_helpers(),
        test_wait_helper(),           test_ws2812_helpers(),   test_timer_helpers(),
        test_psram_helpers(),         test_sdram_helpers(),    test_uart_helpers(),
        test_i2s_helpers(),           test_i2c_helpers(),      test_sdio_helpers(),
        test_usb2_helpers(),          test_spisd_helpers(),    test_gpio_helpers(),
        test_dma_config_validation(), test_opipsram_helpers(), test_user_ip_validation(),
        test_ps2_decoders(),          test_wav_parser(),       test_video_parser(),
    };

    for (size_t index = 0U; index < (sizeof(results) / sizeof(results[0])); ++index) {
        if (results[index] != 0) {
            return (int)(index + 1U);
        }
    }
    return 0;
}
