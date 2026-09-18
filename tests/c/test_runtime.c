#include <stddef.h>
#include <stdint.h>

#include <ps2_keyboard.h>
#include <ps2_mouse.h>

#include <retrosoc/core/status.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/apu.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/clock.h>
#include <retrosoc/hal/extension.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/fabric_monitor.h>
#include <retrosoc/hal/ga2d.h>
#include <retrosoc/hal/i2c.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/hal/jpeg.h>
#include <retrosoc/hal/memory.h>
#include <retrosoc/hal/npu.h>
#include <retrosoc/hal/psram.h>
#include <retrosoc/hal/resource.h>
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

#include "../../crt/src/hal/ga2d_math.h"
#include "../../crt/src/hal/opipsram_math.c"

#define TEST_STORAGE_ADDRESS ((uintptr_t)0x1000U)

int __clzsi2(unsigned int value);
long long __divdi3(long long dividend, long long divisor);
int __ffssi2(unsigned int value);
unsigned long long __udivdi3(unsigned long long dividend, unsigned long long divisor);
unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor);

static uint8_t storage[32];
static uint32_t image_call_count;
volatile uint32_t rs_apu_test_mmio[1024];
volatile uint32_t rs_ga2d_test_mmio[1024];
uint32_t rs_ga2d_test_mem_pad_mode;
volatile uint32_t rs_npu_test_mmio[1024];
volatile uint32_t rs_fabric_monitor_test_mmio[1024];
volatile uint32_t rs_resource_test_mmio[1024];

#define APU_TEST_REG(offset)            rs_apu_test_mmio[(offset) / 4U]
#define GA2D_TEST_REG(offset)           rs_ga2d_test_mmio[(offset) / 4U]
#define NPU_TEST_REG(offset)            rs_npu_test_mmio[(offset) / 4U]
#define FABRIC_MONITOR_TEST_REG(offset) rs_fabric_monitor_test_mmio[(offset) / 4U]
#define RESOURCE_TEST_REG(offset)       rs_resource_test_mmio[(offset) / 4U]

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

static int test_clock_frequency_contract(void) {
    uint32_t frequency_hz;

    if ((rs_clock_frequency_hz(RS_CLOCK_FREQ_72MHZ, &frequency_hz) != RS_OK) ||
        (frequency_hz != UINT32_C(72000000)) ||
        (rs_clock_frequency_hz(RS_CLOCK_FREQ_240MHZ, &frequency_hz) != RS_OK) ||
        (frequency_hz != UINT32_C(240000000))) {
        return 1;
    }
    if ((rs_clock_frequency_hz((rs_clock_frequency_t)8, &frequency_hz) != RS_EINVAL) ||
        (rs_clock_frequency_hz(RS_CLOCK_FREQ_72MHZ, NULL) != RS_EINVAL)) {
        return 2;
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
        (rs_user_ip_select(UINT8_MAX) != RS_ENOTSUP) ||
        (rs_user_ip_probe(UINT8_MAX, &value) != RS_ENOTSUP) ||
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

static int test_extension_validation(void) {
    const rs_extension_acl_t valid_acl = {
        .read_base = UINT32_C(0x38000000),
        .read_limit = UINT32_C(0x38000FFF),
        .write_base = UINT32_C(0x38000000),
        .write_limit = UINT32_C(0x38000FFF),
        .timeout_cycles = UINT32_C(64),
    };
    rs_extension_acl_t invalid_acl = valid_acl;
    rs_extension_capabilities_t capabilities;
    rs_extension_status_t status;
    uint32_t value;

    if ((rs_extension_probe((rs_extension_slot_t)2, &capabilities) != RS_EINVAL) ||
        (rs_extension_probe(RS_EXTENSION_SLOT_L, NULL) != RS_EINVAL) ||
        (rs_extension_get_status((rs_extension_slot_t)2, &status) != RS_EINVAL) ||
        (rs_extension_get_status(RS_EXTENSION_SLOT_H, NULL) != RS_EINVAL)) {
        return 1;
    }
    if ((rs_extension_read((rs_extension_slot_t)2, 0U, &value) != RS_EINVAL) ||
        (rs_extension_read(RS_EXTENSION_SLOT_L, 1U, &value) != RS_EINVAL) ||
        (rs_extension_read(RS_EXTENSION_SLOT_L, UINT32_C(0x1000), &value) != RS_EINVAL) ||
        (rs_extension_read(RS_EXTENSION_SLOT_L, 0U, NULL) != RS_EINVAL)) {
        return 2;
    }
    if ((rs_extension_set_owner(RS_EXTENSION_SLOT_L, (rs_extension_owner_t)2, false) !=
         RS_EINVAL) ||
        (rs_extension_configure_acl(RS_EXTENSION_SLOT_L, &valid_acl) != RS_ENOTSUP) ||
        (rs_extension_configure_acl((rs_extension_slot_t)2, &valid_acl) != RS_EINVAL) ||
        (rs_extension_configure_acl(RS_EXTENSION_SLOT_H, NULL) != RS_EINVAL)) {
        return 3;
    }
    invalid_acl.read_limit = invalid_acl.read_base - UINT32_C(1);
    if (rs_extension_configure_acl(RS_EXTENSION_SLOT_H, &invalid_acl) != RS_EINVAL) {
        return 4;
    }
    invalid_acl = valid_acl;
    invalid_acl.timeout_cycles = 0U;
    if (rs_extension_configure_acl(RS_EXTENSION_SLOT_H, &invalid_acl) != RS_EINVAL) {
        return 5;
    }
    if ((rs_extension_dma_start((uintptr_t)UINT32_C(0x30000001), (uintptr_t)UINT32_C(0x30000008),
                                UINT32_C(8)) != RS_EINVAL) ||
        (rs_extension_dma_start((uintptr_t)UINT32_C(0x30000000), (uintptr_t)UINT32_C(0x30000008),
                                0U) != RS_EINVAL) ||
        (rs_extension_dma_get_status(NULL) != RS_EINVAL)) {
        return 6;
    }
    return 0;
}

static int test_resource_validation(void) {
    rs_resource_status_t status;
    const uint32_t ga2d_base = UINT32_C(0x100) + ((uint32_t)RS_RESOURCE_GA2D * UINT32_C(0x20));

    if ((RS_RESOURCE_DMA != 0) || (RS_RESOURCE_USB2 != 1) || (RS_RESOURCE_SDIO0 != 2) ||
        (RS_RESOURCE_SDIO1 != 3) || (RS_RESOURCE_SPISD != 4) || (RS_RESOURCE_EXT_H != 5) ||
        (RS_RESOURCE_JPEG != 6) || (RS_RESOURCE_APU != 7) || (RS_RESOURCE_GA2D != 8) ||
        (RS_RESOURCE_NPU != 9) || (RS_RESOURCE_COUNT != 10)) {
        return 1;
    }
    if ((rs_resource_get_status((rs_resource_t)RS_RESOURCE_COUNT, &status) != RS_EINVAL) ||
        (rs_resource_get_status(RS_RESOURCE_DMA, NULL) != RS_EINVAL) ||
        (rs_resource_set_owner((rs_resource_t)RS_RESOURCE_COUNT, RS_RESOURCE_OWNER_LP, false) !=
         RS_EINVAL) ||
        (rs_resource_set_owner(RS_RESOURCE_DMA, (rs_resource_owner_t)2, false) != RS_EINVAL) ||
        (rs_resource_set_lifecycle((rs_resource_t)RS_RESOURCE_COUNT, false, false) != RS_EINVAL) ||
        (rs_resource_clear_fault((rs_resource_t)RS_RESOURCE_COUNT) != RS_EINVAL) ||
        (rs_resource_get_cache_status(NULL) != RS_EINVAL)) {
        return 2;
    }

    for (size_t index = 0U;
         index < (sizeof(rs_resource_test_mmio) / sizeof(rs_resource_test_mmio[0])); ++index) {
        rs_resource_test_mmio[index] = 0U;
    }
    RESOURCE_TEST_REG(ga2d_base) = (uint32_t)RS_RESOURCE_OWNER_HP;
    RESOURCE_TEST_REG(ga2d_base + UINT32_C(0x008)) = UINT32_C(0x00000011);
    RESOURCE_TEST_REG(ga2d_base + UINT32_C(0x010)) = UINT32_C(0x00001234);
    if ((rs_resource_get_status(RS_RESOURCE_GA2D, &status) != RS_OK) ||
        (status.owner != RS_RESOURCE_OWNER_HP) || (status.handoff_count != UINT16_C(0x1234)) ||
        status.owner_locked || status.blocked || !status.idle || status.quiesced ||
        status.in_reset || status.irq_pending || status.fault) {
        return 3;
    }

    RESOURCE_TEST_REG(ga2d_base) = (uint32_t)RS_RESOURCE_OWNER_LP | UINT32_C(0x00000100);
    RESOURCE_TEST_REG(ga2d_base + UINT32_C(0x008)) = UINT32_C(0x000000FC);
    RESOURCE_TEST_REG(ga2d_base + UINT32_C(0x010)) = UINT32_C(0x0000FFFF);
    if ((rs_resource_get_status(RS_RESOURCE_GA2D, &status) != RS_OK) ||
        (status.owner != RS_RESOURCE_OWNER_LP) || (status.handoff_count != UINT16_MAX) ||
        !status.owner_locked || !status.blocked || !status.idle || !status.quiesced ||
        !status.in_reset || !status.irq_pending || !status.fault) {
        return 4;
    }
    return 0;
}

static void test_fabric_monitor_mmio_reset(void) {
    for (size_t index = 0U;
         index < (sizeof(rs_fabric_monitor_test_mmio) / sizeof(rs_fabric_monitor_test_mmio[0]));
         ++index) {
        rs_fabric_monitor_test_mmio[index] = 0U;
    }
}

static int test_fabric_monitor_hal_contract(void) {
    rs_fabric_fault_t fault;

    if ((RS_FABRIC_MASTER_HP_ICACHE != 0) || (RS_FABRIC_MASTER_HP_DCACHE != 1) ||
        (RS_FABRIC_MASTER_DMA != 2) || (RS_FABRIC_MASTER_IO_A != 3) ||
        (RS_FABRIC_MASTER_IO_B != 4) || (RS_FABRIC_MASTER_LP != 5) ||
        (RS_FABRIC_MASTER_JPEG != 6) || (RS_FABRIC_MASTER_RESERVED != 6) ||
        (RS_FABRIC_MASTER_EXT_H != 7) || (RS_FABRIC_MASTER_GA2D != 8) ||
        (RS_FABRIC_MASTER_NPU != 9) || (RS_FABRIC_MASTER_COUNT != 10)) {
        return 1;
    }

    test_fabric_monitor_mmio_reset();
    FABRIC_MONITOR_TEST_REG(UINT32_C(0x004)) = UINT32_C(0x00010000);
    FABRIC_MONITOR_TEST_REG(UINT32_C(0x014)) = UINT32_C(0x00001000) | UINT32_C(0x0A00) |
                                               UINT32_C(0x0080) | UINT32_C(0x000C) |
                                               UINT32_C(0x0003);
    FABRIC_MONITOR_TEST_REG(UINT32_C(0x018)) = UINT32_C(0x12345678);
    FABRIC_MONITOR_TEST_REG(UINT32_C(0x020)) = UINT32_C(0x0000002A);
    if ((rs_fabric_monitor_read_fault(&fault) != RS_OK) || (fault.master != 3U) ||
        (fault.target != 4U) || (fault.reason != 10U) || !fault.valid || !fault.write ||
        (fault.address != UINT32_C(0x12345678)) || (fault.count != UINT32_C(0x0000002A))) {
        return 2;
    }

    FABRIC_MONITOR_TEST_REG(UINT32_C(0x004)) = UINT32_C(0x00010001);
    FABRIC_MONITOR_TEST_REG(UINT32_C(0x014)) =
        UINT32_C(0x00001000) | UINT32_C(0x0A00) | UINT32_C(0x0080) | UINT32_C(0x0003);
    if ((rs_fabric_monitor_read_fault(&fault) != RS_OK) ||
        (fault.master != RS_FABRIC_MASTER_GA2D)) {
        return 3;
    }
    if (rs_fabric_monitor_read_fault(NULL) != RS_EINVAL) {
        return 4;
    }
    return 0;
}

static int test_apu_validation(void) {
    rs_apu_job_t job = {
        .format = RS_APU_WAV,
        .output = RS_APU_MEMORY,
        .pcm = RS_APU_S16,
        .input_address = UINT32_C(0x38000000),
        .input_bytes = UINT32_C(0x1000),
        .output_address = UINT32_C(0x38002000),
        .output_capacity = UINT32_C(0x2000),
        .expected_rate = UINT32_C(48000),
        .expected_channels = 2U,
        .expected_bits = 16U,
        .output_rate = UINT32_C(48000),
        .output_channels = 2U,
        .downmix = 0U,
        .resample = 0U,
        .strict = 1U,
        .cookie = {UINT32_C(0x11223344), UINT32_C(0x55667788)},
    };

    if ((rs_apu_probe(NULL) != RS_EINVAL) || (rs_apu_validate_job(NULL) != RS_EINVAL) ||
        (rs_apu_validate_job(&job) != RS_OK)) {
        return 1;
    }
    job.format = RS_APU_MP3;
    if (rs_apu_validate_job(&job) != RS_ENOTSUP) {
        return 2;
    }
    job.format = RS_APU_FLAC;
    job.output_address = job.input_address;
    if (rs_apu_validate_job(&job) != RS_EINVAL) {
        return 3;
    }
    job.output = RS_APU_I2S;
    job.output_address = 0U;
    job.output_capacity = 0U;
    job.output_rate = UINT32_C(44100);
    if (rs_apu_validate_job(&job) != RS_ENOTSUP) {
        return 4;
    }
    job.output = (rs_apu_output_t)-1;
    if (rs_apu_validate_job(&job) != RS_EINVAL) {
        return 5;
    }
    job.output = RS_APU_MEMORY;
    job.output_address = UINT32_C(0x38002000);
    job.output_capacity = UINT32_C(0x2000);
    job.output_rate = UINT32_C(48000);
    job.expected_bits = 8U;
    if (rs_apu_validate_job(&job) != RS_ENOTSUP) {
        return 6;
    }
    job.expected_bits = 16U;
    job.expected_channels = 0U;
    job.output_channels = 1U;
    job.downmix = 1U;
    if (rs_apu_validate_job(&job) != RS_OK) {
        return 7;
    }
    return 0;
}

static void test_apu_mmio_reset(void);

static int test_apu_kws_validation(void) {
    const rs_apu_kws_job_t job = {
        .input_address = UINT32_C(0x10001000),
        .threshold = 128U,
        .debounce = 1U,
        .cookie = {UINT32_C(0x01234567), UINT32_C(0x89ABCDEF)},
    };
    const rs_apu_image_t image = {
        .address = UINT32_C(0x10000000),
        .bytes = UINT32_C(32768),
        .expected_crc = UINT32_C(0xB9034B22),
    };
    rs_apu_image_t bad_image = image;
    rs_apu_kws_completion_t completion;

    test_apu_mmio_reset();
    APU_TEST_REG(RS_APU_ABI_KWS_MODEL_ADDRESS) = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_kws_validate_job(&job) != RS_OK) ||
        (rs_apu_kws_model_load(&image, 0U) != RS_ENOTSUP) ||
        (APU_TEST_REG(RS_APU_ABI_KWS_MODEL_ADDRESS) != UINT32_C(0xA5A5A5A5))) {
        return 1;
    }
    APU_TEST_REG(RS_APU_ABI_STREAM_ROUTE) = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_stream_route(0U, 1U) != RS_ENOTSUP) ||
        (APU_TEST_REG(RS_APU_ABI_STREAM_ROUTE) != UINT32_C(0xA5A5A5A5))) {
        return 2;
    }
    APU_TEST_REG(RS_APU_ABI_IP_ID) = RS_APU_IP_ID_VALUE;
    APU_TEST_REG(RS_APU_ABI_IP_VERSION) = RS_APU_IP_VERSION_VALUE;
    APU_TEST_REG(RS_APU_ABI_CAPABILITY0) = RS_APU_CAPABILITY0_P7_IMPLEMENTED;
    APU_TEST_REG(RS_APU_ABI_STREAM_STATUS) = UINT32_C(1) << RS_APU_ABI_STREAM_STATUS_RX_ACTIVE;
    APU_TEST_REG(RS_APU_ABI_STREAM_ROUTE) = 0U;
    if ((rs_apu_stream_route(0U, 1U) != RS_EINVAL) ||
        (APU_TEST_REG(RS_APU_ABI_STREAM_ROUTE) != 0U)) {
        return 3;
    }
    APU_TEST_REG(RS_APU_ABI_STREAM_STATUS) = 0U;
    if ((rs_apu_stream_route(0U, 1U) != RS_OK) || (APU_TEST_REG(RS_APU_ABI_STREAM_ROUTE) != 4U)) {
        return 4;
    }
    bad_image.expected_crc ^= UINT32_C(1);
    APU_TEST_REG(RS_APU_ABI_KWS_MODEL_ADDRESS) = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_kws_model_load(&bad_image, 0U) != RS_EINVAL) ||
        (APU_TEST_REG(RS_APU_ABI_KWS_MODEL_ADDRESS) != UINT32_C(0xA5A5A5A5))) {
        return 5;
    }
    APU_TEST_REG(RS_APU_ABI_OWNER_STATUS) = UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_QUIESCE;
    APU_TEST_REG(RS_APU_ABI_KWS_MODEL_STATUS) = 0U;
    if ((rs_apu_kws_model_load(&image, 1U) != RS_EIO) ||
        (APU_TEST_REG(RS_APU_ABI_COMMAND) != (UINT32_C(1) << RS_APU_ABI_COMMAND_MODEL_LOAD))) {
        return 6;
    }
    APU_TEST_REG(RS_APU_ABI_OWNER_STATUS) = 0U;
    APU_TEST_REG(RS_APU_ABI_KWS_CONTROL) = UINT32_C(3);
    APU_TEST_REG(RS_APU_ABI_KWS_MODEL_STATUS) = UINT32_C(6);
    APU_TEST_REG(RS_APU_ABI_KWS_STATUS) = 0U;
    APU_TEST_REG(RS_APU_ABI_JOB_STATUS) = 0U;
    if ((rs_apu_kws_submit_direct(&job) != RS_OK) ||
        (APU_TEST_REG(RS_APU_ABI_JOB_CONTROL) != UINT32_C(1)) ||
        (APU_TEST_REG(RS_APU_ABI_JOB_FLAGS) != 0U) ||
        (APU_TEST_REG(RS_APU_ABI_KWS_CONFIG) != UINT32_C(0x0180))) {
        return 7;
    }
    completion.class_id = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_kws_wait_direct(&completion, 0U) != RS_ETIMEOUT) ||
        (completion.class_id != UINT32_C(0xA5A5A5A5))) {
        return 8;
    }
    APU_TEST_REG(RS_APU_ABI_JOB_STATUS) = UINT32_C(1) << RS_APU_ABI_JOB_STATUS_DONE;
    APU_TEST_REG(RS_APU_ABI_KWS_STATUS) = UINT32_C(1) << RS_APU_ABI_KWS_STATUS_RESULT_VALID;
    APU_TEST_REG(RS_APU_ABI_KWS_RESULT) = UINT32_C(0x00017F03);
    if ((rs_apu_kws_wait_direct(&completion, 1U) != RS_OK) || (completion.class_id != 3U) ||
        (completion.score != 127U) || (completion.hit != 1U) ||
        (completion.job.cookie[0] != job.cookie[0]) ||
        (completion.job.cookie[1] != job.cookie[1])) {
        return 9;
    }
    APU_TEST_REG(RS_APU_ABI_KWS_CONTROL) = UINT32_C(3);
    APU_TEST_REG(RS_APU_ABI_KWS_STATUS) = 0U;
    if ((rs_apu_kws_disable(0U) != RS_OK) ||
        (APU_TEST_REG(RS_APU_ABI_KWS_CONTROL) != UINT32_C(2))) {
        return 10;
    }
    return 0;
}

static void test_apu_mmio_reset(void) {
    for (size_t index = 0U; index < (sizeof(rs_apu_test_mmio) / sizeof(rs_apu_test_mmio[0]));
         ++index) {
        rs_apu_test_mmio[index] = 0U;
    }
    APU_TEST_REG(RS_APU_ABI_CAPABILITY0) = RS_APU_CAPABILITY0_IMPLEMENTED;
    APU_TEST_REG(RS_APU_ABI_STATUS) = UINT32_C(1) << RS_APU_ABI_STATUS_IDLE;
    APU_TEST_REG(RS_APU_ABI_MC_STATUS) = UINT32_C(1) << RS_APU_ABI_MC_STATUS_VALID;
    APU_TEST_REG(RS_APU_ABI_MC_LOCK) = UINT32_C(1) << RS_APU_ABI_MC_LOCK_LOCKED;
    APU_TEST_REG(RS_APU_ABI_READ_BASE) = UINT32_C(0x10000000);
    APU_TEST_REG(RS_APU_ABI_READ_LIMIT) = UINT32_C(0x100FFFFF);
    APU_TEST_REG(RS_APU_ABI_WRITE_BASE) = UINT32_C(0x10000000);
    APU_TEST_REG(RS_APU_ABI_WRITE_LIMIT) = UINT32_C(0x100FFFFF);
}

static int test_apu_hal_contract(void) {
    static _Alignas(RS_APU_ABI_DESCRIPTOR_BYTES) rs_apu_descriptor_t descriptors[4];
    rs_apu_job_t job = {
        .format = RS_APU_WAV,
        .output = RS_APU_MEMORY,
        .pcm = RS_APU_S16,
        .input_address = UINT32_C(0x10001000),
        .input_bytes = UINT32_C(0x100),
        .output_address = UINT32_C(0x10002000),
        .output_capacity = UINT32_C(0x400),
        .expected_rate = UINT32_C(48000),
        .expected_channels = 2U,
        .expected_bits = 16U,
        .output_rate = UINT32_C(48000),
        .output_channels = 2U,
        .strict = 1U,
    };
    const rs_apu_image_t image = {
        .address = UINT32_C(0x10000000),
        .bytes = UINT32_C(0x1000),
        .expected_crc = UINT32_C(0x12345678),
    };
    rs_apu_ring_t ring = {
        .descriptors = descriptors,
        .dma_address = UINT32_C(0x10004000),
        .entries = 4U,
        .tail = 0U,
    };
    rs_apu_result_t result;
    uint32_t slot;

    test_apu_mmio_reset();
    APU_TEST_REG(RS_APU_ABI_OWNER_STATUS) = UINT32_C(1) << RS_APU_ABI_OWNER_STATUS_QUIESCE;
    APU_TEST_REG(RS_APU_ABI_MC_IMAGE_ADDRESS) = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_microcode_load(&image, 0U) != RS_EINVAL) ||
        (APU_TEST_REG(RS_APU_ABI_MC_IMAGE_ADDRESS) != UINT32_C(0xA5A5A5A5))) {
        return 1;
    }
    if (rs_apu_set_acl(UINT32_C(0x10000000), UINT32_C(0x100FFFFF), UINT32_C(0x10000000),
                       UINT32_C(0x100FFFFF)) != RS_OK) {
        return 2;
    }

    APU_TEST_REG(RS_APU_ABI_OWNER_STATUS) = 0U;
    APU_TEST_REG(RS_APU_ABI_STATUS) = 0U;
    if (rs_apu_submit_direct(&job) != RS_OK ||
        APU_TEST_REG(RS_APU_ABI_JOB_INPUT_ADDRESS) != job.input_address ||
        APU_TEST_REG(RS_APU_ABI_COMMAND) != (UINT32_C(1) << RS_APU_ABI_COMMAND_START_DIRECT)) {
        return 3;
    }
    APU_TEST_REG(RS_APU_ABI_STATUS) = UINT32_C(1) << RS_APU_ABI_STATUS_IDLE;
    APU_TEST_REG(RS_APU_ABI_RING_CONTROL) = 1U;
    APU_TEST_REG(RS_APU_ABI_JOB_INPUT_ADDRESS) = UINT32_C(0xA5A5A5A5);
    if ((rs_apu_submit_direct(&job) != RS_EINVAL) ||
        (APU_TEST_REG(RS_APU_ABI_JOB_INPUT_ADDRESS) != UINT32_C(0xA5A5A5A5))) {
        return 4;
    }

    (void)memset(descriptors, 0, sizeof(descriptors));
    APU_TEST_REG(RS_APU_ABI_RING_CONTROL) = 0U;
    if (rs_apu_ring_configure(&ring, 0U, 1U, 1U) != RS_OK) {
        return 5;
    }
    if ((rs_apu_ring_submit(&ring, &job, 1U, &slot) != RS_OK) || (slot != 0U) ||
        ((descriptors[0].control & (UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN)) == 0U)) {
        return 6;
    }
    descriptors[0].control &= ~(UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
    descriptors[0].result_status = UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_STATUS_DONE;
    if (rs_apu_ring_result(&ring, 0U, &result, 0U) != RS_OK) {
        return 7;
    }

    APU_TEST_REG(RS_APU_ABI_RING_HEAD) = 1U;
    if ((rs_apu_ring_submit(&ring, &job, 0U, &slot) != RS_OK) || (slot != 1U)) {
        return 8;
    }
    descriptors[1].control &= ~(UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
    descriptors[1].result_status = UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_STATUS_DONE;
    APU_TEST_REG(RS_APU_ABI_RING_HEAD) = 2U;
    if ((rs_apu_ring_submit(&ring, &job, 0U, &slot) != RS_OK) || (slot != 2U)) {
        return 9;
    }
    descriptors[2].control &= ~(UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
    descriptors[2].result_status = UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_STATUS_DONE;
    if (rs_apu_ring_result(&ring, 2U, &result, 0U) != RS_OK) {
        return 10;
    }
    APU_TEST_REG(RS_APU_ABI_RING_HEAD) = 3U;
    if ((rs_apu_ring_submit(&ring, &job, 0U, &slot) != RS_OK) || (slot != 3U)) {
        return 11;
    }
    descriptors[3].control &= ~(UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
    descriptors[3].result_status = UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_STATUS_DONE;
    if (rs_apu_ring_result(&ring, 3U, &result, 0U) != RS_OK) {
        return 12;
    }
    APU_TEST_REG(RS_APU_ABI_RING_HEAD) = 0U;
    if ((rs_apu_ring_submit(&ring, &job, 0U, &slot) != RS_OK) || (slot != 0U)) {
        return 13;
    }
    descriptors[0].control &= ~(UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_CONTROL_OWN);
    descriptors[0].result_status = UINT32_C(1) << RS_APU_ABI_DESCRIPTOR_STATUS_DONE;
    APU_TEST_REG(RS_APU_ABI_RING_HEAD) = 1U;
    if (rs_apu_ring_submit(&ring, &job, 0U, &slot) != RS_ENOSPC) {
        return 14;
    }
    return 0;
}

static void test_ga2d_mmio_reset(void) {
    for (size_t index = 0U; index < (sizeof(rs_ga2d_test_mmio) / sizeof(rs_ga2d_test_mmio[0]));
         ++index) {
        rs_ga2d_test_mmio[index] = 0U;
    }
    GA2D_TEST_REG(RS_GA2D_REG_IP_ID) = RS_GA2D_IP_ID_VALUE;
    GA2D_TEST_REG(RS_GA2D_REG_IP_VERSION) = RS_GA2D_IP_VERSION_VALUE;
    GA2D_TEST_REG(RS_GA2D_REG_CAPABILITY) = RS_GA2D_CAPABILITY_P5;
    GA2D_TEST_REG(RS_GA2D_REG_LIMITS) = RS_GA2D_LIMITS_P5;
    GA2D_TEST_REG(RS_GA2D_REG_FORMAT_CAPABILITY) = RS_GA2D_FORMAT_CAPABILITY_P5;
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DATA_READY;
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_QPI;
}

static int check_ga2d_validation_result(const rs_ga2d_job_t *job,
                                        const rs_ga2d_capability_t *capability,
                                        rs_status_t expected_status,
                                        rs_ga2d_validation_category_t expected_category,
                                        rs_ga2d_plane_t expected_plane) {
    const rs_ga2d_validation_result_t result =
        rs_ga2d_job_validate_capability_result(job, capability);

    return ((result.status == expected_status) && (result.category == expected_category) &&
            (result.plane == expected_plane) &&
            (rs_ga2d_job_validate_capability(job, capability) == expected_status))
               ? 0
               : 1;
}

static int test_ga2d_pixel_math(void) {
    uint8_t source[4] = {UINT8_C(0), UINT8_C(0), UINT8_C(0), UINT8_C(0)};
    uint8_t destination[4] = {UINT8_C(0), UINT8_C(0), UINT8_C(0), UINT8_C(0)};
    rs_ga2d_pixel_t pixel;

    for (uint32_t encoded = 0U; encoded < UINT32_C(65536); ++encoded) {
        source[0] = (uint8_t)encoded;
        source[1] = (uint8_t)(encoded >> 8U);
        if ((rs_ga2d_unpack_pixel(source, RS_GA2D_FORMAT_RGB565, &pixel) != RS_OK) ||
            (pixel.alpha != UINT8_C(0xFF)) ||
            (rs_ga2d_pack_pixel(destination, RS_GA2D_FORMAT_RGB565, &pixel) != RS_OK) ||
            (destination[0] != source[0]) || (destination[1] != source[1])) {
            return 1;
        }
    }

    source[0] = UINT8_C(0x03);
    source[1] = UINT8_C(0x02);
    source[2] = UINT8_C(0x01);
    source[3] = UINT8_C(0x00);
    if ((rs_ga2d_unpack_pixel(source, RS_GA2D_FORMAT_XRGB8888, &pixel) != RS_OK) ||
        (pixel.red != UINT8_C(0x01)) || (pixel.green != UINT8_C(0x02)) ||
        (pixel.blue != UINT8_C(0x03)) || (pixel.alpha != UINT8_C(0xFF))) {
        return 2;
    }
    pixel.alpha = UINT8_C(0x11);
    if ((rs_ga2d_pack_pixel(destination, RS_GA2D_FORMAT_XRGB8888, &pixel) != RS_OK) ||
        (destination[0] != UINT8_C(0x03)) || (destination[1] != UINT8_C(0x02)) ||
        (destination[2] != UINT8_C(0x01)) || (destination[3] != UINT8_C(0xFF))) {
        return 3;
    }

    source[0] = UINT8_C(0x03);
    source[1] = UINT8_C(0x02);
    source[2] = UINT8_C(0x01);
    source[3] = UINT8_C(0x44);
    if ((rs_ga2d_convert_pixel(source, RS_GA2D_FORMAT_ARGB8888, destination,
                               RS_GA2D_FORMAT_ARGB8888) != RS_OK) ||
        (destination[0] != UINT8_C(0x03)) || (destination[1] != UINT8_C(0x02)) ||
        (destination[2] != UINT8_C(0x01)) || (destination[3] != UINT8_C(0x44)) ||
        (rs_ga2d_convert_pixel(source, RS_GA2D_FORMAT_ARGB8888, destination,
                               RS_GA2D_FORMAT_XRGB8888) != RS_OK) ||
        (destination[3] != UINT8_C(0xFF))) {
        return 4;
    }
    if ((rs_ga2d_convert_pixel(source, RS_GA2D_FORMAT_XRGB8888, destination,
                               RS_GA2D_FORMAT_ARGB8888) != RS_OK) ||
        (destination[3] != UINT8_C(0xFF)) ||
        (rs_ga2d_convert_pixel(source, RS_GA2D_FORMAT_A8, destination, RS_GA2D_FORMAT_RGB888) !=
         RS_EINVAL) ||
        (rs_ga2d_pack_pixel(destination, RS_GA2D_FORMAT_A8, &pixel) != RS_EINVAL)) {
        return 5;
    }

    for (uint32_t pixel_alpha = 0U; pixel_alpha < UINT32_C(256); ++pixel_alpha) {
        for (uint32_t global_alpha = 0U; global_alpha < UINT32_C(256); ++global_alpha) {
            const uint8_t expected =
                (uint8_t)((pixel_alpha * global_alpha + UINT32_C(127)) / UINT32_C(255));

            if (rs_ga2d_alpha_round((uint8_t)pixel_alpha, (uint8_t)global_alpha) != expected) {
                return 6;
            }
        }
    }

    source[0] = UINT8_C(127);
    destination[0] = UINT8_C(0x20);
    destination[1] = UINT8_C(0x40);
    destination[2] = UINT8_C(0x80);
    if ((rs_ga2d_blend_pixel(source, RS_GA2D_FORMAT_A8, destination, RS_GA2D_FORMAT_RGB888,
                             destination, RS_GA2D_FORMAT_RGB888, UINT32_C(0x12102030),
                             UINT8_C(128)) != RS_OK) ||
        (destination[0] != UINT8_C(0x1C)) || (destination[1] != UINT8_C(0x38)) ||
        (destination[2] != UINT8_C(0x6C))) {
        return 7;
    }
    destination[0] = UINT8_C(0x20);
    destination[1] = UINT8_C(0x40);
    destination[2] = UINT8_C(0x80);
    if ((rs_ga2d_blend_pixel(source, RS_GA2D_FORMAT_A8, destination, RS_GA2D_FORMAT_RGB888,
                             destination, RS_GA2D_FORMAT_RGB888, UINT32_C(0xFF102030),
                             UINT8_C(128)) != RS_OK) ||
        (destination[0] != UINT8_C(0x1C)) || (destination[1] != UINT8_C(0x38)) ||
        (destination[2] != UINT8_C(0x6C))) {
        return 8;
    }
    source[0] = UINT8_C(0xC0);
    source[1] = UINT8_C(0x80);
    source[2] = UINT8_C(0x40);
    source[3] = UINT8_C(0xFF);
    destination[0] = UINT8_C(0x30);
    destination[1] = UINT8_C(0x20);
    destination[2] = UINT8_C(0x10);
    destination[3] = UINT8_C(0x00);
    if ((rs_ga2d_blend_pixel(source, RS_GA2D_FORMAT_ARGB8888, destination, RS_GA2D_FORMAT_XRGB8888,
                             destination, RS_GA2D_FORMAT_XRGB8888, UINT32_C(0),
                             UINT8_C(128)) != RS_OK) ||
        (destination[0] != UINT8_C(0x78)) || (destination[1] != UINT8_C(0x50)) ||
        (destination[2] != UINT8_C(0x28)) || (destination[3] != UINT8_C(0xFF))) {
        return 9;
    }
    return 0;
}

static int test_ga2d_p5_validation(void) {
    static const uint32_t color_pitches[4] = {10U, 15U, 20U, 20U};
    rs_ga2d_job_t fill = {
        .operation = RS_GA2D_OP_FILL,
        .foreground = {0U, 0U, RS_GA2D_FORMAT_A8},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)UINT32_C(0x38001000), 10U, RS_GA2D_FORMAT_RGB565},
        .width = 5U,
        .height = 3U,
        .global_alpha = UINT8_C(0),
        .color = UINT32_C(0x80123456),
    };
    rs_ga2d_job_t copy = {
        .operation = RS_GA2D_OP_COPY,
        .foreground = {(uintptr_t)UINT32_C(0x38002000), 10U, RS_GA2D_FORMAT_RGB565},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)UINT32_C(0x38003000), 10U, RS_GA2D_FORMAT_RGB565},
        .width = 5U,
        .height = 3U,
        .global_alpha = UINT8_C(0),
        .color = UINT32_C(0),
    };
    rs_ga2d_job_t convert = {
        .operation = RS_GA2D_OP_CONVERT,
        .foreground = {(uintptr_t)UINT32_C(0x38004000), 10U, RS_GA2D_FORMAT_RGB565},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)UINT32_C(0x38005000), 10U, RS_GA2D_FORMAT_RGB565},
        .width = 5U,
        .height = 3U,
        .global_alpha = UINT8_C(0),
        .color = UINT32_C(0),
    };
    rs_ga2d_job_t blend = {
        .operation = RS_GA2D_OP_BLEND,
        .foreground = {(uintptr_t)UINT32_C(0x38006000), 5U, RS_GA2D_FORMAT_A8},
        .background = {(uintptr_t)UINT32_C(0x38007000), 15U, RS_GA2D_FORMAT_RGB888},
        .destination = {(uintptr_t)UINT32_C(0x38008000), 15U, RS_GA2D_FORMAT_RGB888},
        .width = 5U,
        .height = 3U,
        .global_alpha = UINT8_C(128),
        .color = UINT32_C(0x12102030),
    };

    test_ga2d_mmio_reset();
    for (uint32_t destination_format = 0U; destination_format < 4U; ++destination_format) {
        fill.destination.format = (rs_ga2d_format_t)destination_format;
        fill.destination.pitch = color_pitches[destination_format];
        if (rs_ga2d_job_validate(&fill) != RS_OK) {
            return 1;
        }
    }
    fill.foreground.format = (rs_ga2d_format_t)7;
    fill.background.format = (rs_ga2d_format_t)7;
    if (rs_ga2d_job_validate(&fill) != RS_OK) {
        return 2;
    }
    fill.foreground.format = RS_GA2D_FORMAT_A8;
    fill.background.format = RS_GA2D_FORMAT_A8;
    fill.destination.format = RS_GA2D_FORMAT_A8;
    fill.destination.pitch = 5U;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 3;
    }
    fill.destination.format = RS_GA2D_FORMAT_RGB565;
    fill.destination.pitch = color_pitches[RS_GA2D_FORMAT_RGB565];
    fill.operation = (rs_ga2d_operation_t)4;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 4;
    }
    fill.operation = RS_GA2D_OP_FILL;

    for (uint32_t format = 0U; format < 4U; ++format) {
        copy.foreground.format = (rs_ga2d_format_t)format;
        copy.foreground.pitch = color_pitches[format];
        copy.destination.format = (rs_ga2d_format_t)format;
        copy.destination.pitch = color_pitches[format];
        if (rs_ga2d_job_validate(&copy) != RS_OK) {
            return 5;
        }
    }
    copy.foreground.format = RS_GA2D_FORMAT_RGB565;
    copy.foreground.pitch = color_pitches[RS_GA2D_FORMAT_RGB565];
    copy.destination.format = RS_GA2D_FORMAT_RGB888;
    copy.destination.pitch = color_pitches[RS_GA2D_FORMAT_RGB888];
    if (rs_ga2d_job_validate(&copy) != RS_EINVAL) {
        return 6;
    }
    copy.foreground.format = RS_GA2D_FORMAT_A8;
    copy.foreground.pitch = 5U;
    if (rs_ga2d_job_validate(&copy) != RS_EINVAL) {
        return 7;
    }

    for (uint32_t foreground_format = 0U; foreground_format < 4U; ++foreground_format) {
        convert.foreground.format = (rs_ga2d_format_t)foreground_format;
        convert.foreground.pitch = color_pitches[foreground_format];
        for (uint32_t destination_format = 0U; destination_format < 4U; ++destination_format) {
            convert.destination.format = (rs_ga2d_format_t)destination_format;
            convert.destination.pitch = color_pitches[destination_format];
            if (rs_ga2d_job_validate(&convert) != RS_OK) {
                return 8;
            }
        }
    }
    convert.foreground.format = RS_GA2D_FORMAT_A8;
    convert.foreground.pitch = 5U;
    if (rs_ga2d_job_validate(&convert) != RS_EINVAL) {
        return 9;
    }
    convert.foreground.format = RS_GA2D_FORMAT_RGB565;
    convert.foreground.pitch = color_pitches[RS_GA2D_FORMAT_RGB565];
    convert.destination.format = RS_GA2D_FORMAT_RGB565;
    convert.destination.pitch = color_pitches[RS_GA2D_FORMAT_RGB565];
    GA2D_TEST_REG(RS_GA2D_REG_CAPABILITY) = RS_GA2D_CAPABILITY_P5 & ~RS_GA2D_CAPABILITY_CONVERT;
    if (rs_ga2d_job_validate(&convert) != RS_ENOTSUP) {
        return 10;
    }
    test_ga2d_mmio_reset();
    GA2D_TEST_REG(RS_GA2D_REG_FORMAT_CAPABILITY) =
        RS_GA2D_FORMAT_CAPABILITY_P5 &
        ~(UINT32_C(1) << (RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT +
                          (uint32_t)RS_GA2D_FORMAT_RGB565));
    if (rs_ga2d_job_validate(&convert) != RS_ENOTSUP) {
        return 11;
    }
    test_ga2d_mmio_reset();

    for (uint32_t foreground_format = 0U; foreground_format < 5U; ++foreground_format) {
        blend.foreground.format = (rs_ga2d_format_t)foreground_format;
        blend.foreground.pitch = (foreground_format == (uint32_t)RS_GA2D_FORMAT_A8)
                                     ? 5U
                                     : color_pitches[foreground_format];
        for (uint32_t background_format = 0U; background_format < 4U; ++background_format) {
            blend.background.format = (rs_ga2d_format_t)background_format;
            blend.background.pitch = color_pitches[background_format];
            for (uint32_t destination_format = 0U; destination_format < 4U; ++destination_format) {
                blend.destination.format = (rs_ga2d_format_t)destination_format;
                blend.destination.pitch = color_pitches[destination_format];
                if (rs_ga2d_job_validate(&blend) != RS_OK) {
                    return 12;
                }
            }
        }
    }
    blend.foreground.format = RS_GA2D_FORMAT_A8;
    blend.foreground.pitch = 5U;
    blend.background.format = RS_GA2D_FORMAT_RGB888;
    blend.background.pitch = 15U;
    blend.destination.format = RS_GA2D_FORMAT_RGB888;
    blend.destination.pitch = 15U;
    GA2D_TEST_REG(RS_GA2D_REG_CAPABILITY) = RS_GA2D_CAPABILITY_P5 & ~RS_GA2D_CAPABILITY_A8_MASK;
    if (rs_ga2d_job_validate(&blend) != RS_ENOTSUP) {
        return 13;
    }
    test_ga2d_mmio_reset();

    blend.background.address = blend.destination.address;
    if (rs_ga2d_job_validate(&blend) != RS_OK) {
        return 14;
    }
    GA2D_TEST_REG(RS_GA2D_REG_CAPABILITY) =
        RS_GA2D_CAPABILITY_P5 & ~RS_GA2D_CAPABILITY_INPLACE_BACKGROUND;
    if (rs_ga2d_job_validate(&blend) != RS_ENOTSUP) {
        return 15;
    }
    test_ga2d_mmio_reset();
    blend.background.pitch = 16U;
    if (rs_ga2d_job_validate(&blend) != RS_EINVAL) {
        return 16;
    }
    blend.background.pitch = 15U;
    blend.foreground.address = blend.destination.address;
    if (rs_ga2d_job_validate(&blend) != RS_EINVAL) {
        return 17;
    }
    blend.foreground.format = RS_GA2D_FORMAT_RGB888;
    blend.foreground.pitch = 15U;
    blend.destination.address = (uintptr_t)UINT32_C(0x38008000);
    blend.background.address = (uintptr_t)UINT32_C(0x38007000);
    blend.foreground.address = blend.background.address;
    if (rs_ga2d_job_validate(&blend) != RS_OK) {
        return 18;
    }

    blend.foreground.format = RS_GA2D_FORMAT_A8;
    blend.foreground.pitch = 5U;
    blend.foreground.address = (uintptr_t)UINT32_C(0x40001000);
    blend.background.address = (uintptr_t)UINT32_C(0x48001000);
    blend.destination.address = (uintptr_t)UINT32_C(0x38008000);
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_QPI;
    if (rs_ga2d_job_validate(&blend) != RS_EINVAL) {
        return 19;
    }
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_OPI;
    if (rs_ga2d_job_validate(&blend) != RS_EINVAL) {
        return 20;
    }
    blend.foreground.address = (uintptr_t)UINT32_C(0x38006000);
    if (rs_ga2d_job_validate(&blend) != RS_OK) {
        return 21;
    }
    blend.background.address = (uintptr_t)UINT32_C(0x38007000);
    blend.destination.address = (uintptr_t)UINT32_C(0x40002000);
    if (rs_ga2d_job_validate(&blend) != RS_EINVAL) {
        return 22;
    }
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_QPI;
    if (rs_ga2d_job_validate(&blend) != RS_OK) {
        return 23;
    }

    convert.foreground.format = RS_GA2D_FORMAT_RGB565;
    convert.foreground.pitch = 10U;
    convert.destination.format = RS_GA2D_FORMAT_ARGB8888;
    convert.destination.pitch = 20U;
    if ((rs_ga2d_configure(&convert) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_ADDRESS) != convert.foreground.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_PITCH) != convert.foreground.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_FORMAT) != convert.foreground.format) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_ADDRESS) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_PITCH) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_FORMAT) != 0U)) {
        return 24;
    }

    blend.foreground.address = (uintptr_t)UINT32_C(0x38006000);
    blend.foreground.format = RS_GA2D_FORMAT_A8;
    blend.foreground.pitch = 5U;
    blend.background.address = (uintptr_t)UINT32_C(0x38007000);
    blend.background.format = RS_GA2D_FORMAT_RGB888;
    blend.background.pitch = 15U;
    blend.destination.address = (uintptr_t)UINT32_C(0x38008000);
    blend.destination.format = RS_GA2D_FORMAT_RGB888;
    blend.destination.pitch = 15U;
    if ((rs_ga2d_configure(&blend) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_ADDRESS) != blend.foreground.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_PITCH) != blend.foreground.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_FORMAT) != blend.foreground.format) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_ADDRESS) != blend.background.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_PITCH) != blend.background.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_FORMAT) != blend.background.format)) {
        return 25;
    }
    return 0;
}

static int test_ga2d_validation_precedence(void) {
    const rs_ga2d_capability_t capability = {
        .version = RS_GA2D_IP_VERSION_VALUE,
        .features = RS_GA2D_CAPABILITY_P5,
        .limits = RS_GA2D_LIMITS_P5,
        .formats = RS_GA2D_FORMAT_CAPABILITY_P5,
    };
    rs_ga2d_job_t job = {
        .operation = RS_GA2D_OP_BLEND,
        .foreground = {(uintptr_t)UINT32_C(0x38001000), 2U, RS_GA2D_FORMAT_RGB565},
        .background = {(uintptr_t)UINT32_C(0x38002000), 2U, RS_GA2D_FORMAT_RGB565},
        .destination = {(uintptr_t)UINT32_C(0x38003000), 2U, RS_GA2D_FORMAT_RGB565},
        .width = 1U,
        .height = 1U,
        .global_alpha = UINT8_C(0xFF),
        .color = UINT32_C(0),
    };

    job.width = 0U;
    job.foreground.format = RS_GA2D_FORMAT_A8;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL, RS_GA2D_VALIDATION_CATEGORY_SIZE,
                                     RS_GA2D_PLANE_NONE) != 0) {
        return 1;
    }

    job.width = 1U;
    job.operation = RS_GA2D_OP_CONVERT;
    job.foreground.address = (uintptr_t)UINT32_C(0x38001001);
    job.foreground.pitch = 1U;
    job.foreground.format = RS_GA2D_FORMAT_A8;
    job.destination.address = 0U;
    job.destination.pitch = 2U;
    job.destination.format = RS_GA2D_FORMAT_RGB565;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_FORMAT,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 2;
    }

    job.foreground.address = (uintptr_t)UINT32_C(0x38001001);
    job.foreground.pitch = 2U;
    job.foreground.format = RS_GA2D_FORMAT_RGB565;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_ALIGNMENT,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 3;
    }

    job.operation = RS_GA2D_OP_BLEND;
    job.destination.address = (uintptr_t)UINT32_C(0x38003001);
    job.destination.pitch = 2U;
    job.foreground.address = (uintptr_t)UINT32_C(0x38001003);
    job.foreground.pitch = 2U;
    job.background.address = (uintptr_t)UINT32_C(0x38002005);
    job.background.pitch = 2U;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_ALIGNMENT,
                                     RS_GA2D_PLANE_DESTINATION) != 0) {
        return 4;
    }

    job.destination.address = (uintptr_t)UINT32_C(0x38003000);
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_ALIGNMENT,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 5;
    }

    job.destination.address = 0U;
    job.foreground.address = (uintptr_t)UINT32_C(0x38001000);
    job.foreground.pitch = 0U;
    job.background.address = (uintptr_t)UINT32_C(0x38002000);
    job.background.pitch = 0U;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_PITCH,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 6;
    }

    job.destination.address = (uintptr_t)UINT32_C(0x38003000);
    job.destination.pitch = 2U;
    job.foreground.address = (uintptr_t)UINT32_C(0xFFFFFFFE);
    job.foreground.pitch = 2U;
    job.background.address = (uintptr_t)UINT32_C(0xFFFFFFFE);
    job.background.pitch = 2U;
    job.height = 2U;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_OVERFLOW,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 7;
    }

    job.height = 1U;
    job.foreground.address = job.destination.address;
    job.foreground.pitch = 2U;
    job.background.address = 0U;
    job.background.pitch = 2U;
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_RANGE,
                                     RS_GA2D_PLANE_BACKGROUND) != 0) {
        return 8;
    }

    job.foreground.address = 0U;
    job.background.address = (uintptr_t)UINT32_C(0x00001000);
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_RANGE,
                                     RS_GA2D_PLANE_FOREGROUND) != 0) {
        return 9;
    }

    job.foreground.address = job.destination.address;
    job.background.address = (uintptr_t)UINT32_C(0x38002000);
    if (check_ga2d_validation_result(&job, &capability, RS_EINVAL,
                                     RS_GA2D_VALIDATION_CATEGORY_OVERLAP,
                                     RS_GA2D_PLANE_DESTINATION) != 0) {
        return 10;
    }
    return 0;
}

static int test_ga2d_hal_contract(void) {
    rs_ga2d_capability_t capability;
    rs_ga2d_status_t status;
    rs_ga2d_error_t error;
    rs_ga2d_stats_t stats;
    rs_ga2d_job_t fill = {
        .operation = RS_GA2D_OP_FILL,
        .foreground = {0U, 0U, RS_GA2D_FORMAT_A8},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)UINT32_C(0x38001000), 15U, RS_GA2D_FORMAT_RGB888},
        .width = 5U,
        .height = 3U,
        .global_alpha = UINT8_C(0xA5),
        .color = UINT32_C(0x80123456),
    };
    rs_ga2d_job_t copy = {
        .operation = RS_GA2D_OP_COPY,
        .foreground = {(uintptr_t)UINT32_C(0x38002000), 32U, RS_GA2D_FORMAT_ARGB8888},
        .background = {0U, 0U, RS_GA2D_FORMAT_A8},
        .destination = {(uintptr_t)UINT32_C(0x38003000), 32U, RS_GA2D_FORMAT_ARGB8888},
        .width = 4U,
        .height = 3U,
        .global_alpha = UINT8_C(0),
        .color = UINT32_C(0),
    };

    test_ga2d_mmio_reset();
    if ((rs_ga2d_get_capability(NULL) != RS_EINVAL) ||
        (rs_ga2d_get_capability(&capability) != RS_OK) ||
        (capability.version != RS_GA2D_IP_VERSION_VALUE) ||
        (capability.features != RS_GA2D_CAPABILITY_P5) ||
        (capability.limits != RS_GA2D_LIMITS_P5) ||
        (capability.formats != RS_GA2D_FORMAT_CAPABILITY_P5)) {
        return 1;
    }
    GA2D_TEST_REG(RS_GA2D_REG_IP_VERSION) = UINT32_C(0x00020000);
    if (rs_ga2d_get_capability(&capability) != RS_ENOTSUP) {
        return 2;
    }
    test_ga2d_mmio_reset();
    GA2D_TEST_REG(RS_GA2D_REG_CAPABILITY) = RS_GA2D_CAPABILITY_IRQ;
    GA2D_TEST_REG(RS_GA2D_REG_COMMAND) = UINT32_C(0xA5A5A5A5);
    if ((rs_ga2d_job_validate(NULL) != RS_EINVAL) || (rs_ga2d_job_validate(&fill) != RS_ENOTSUP) ||
        (rs_ga2d_configure(NULL) != RS_EINVAL) || (rs_ga2d_configure(&fill) != RS_ENOTSUP) ||
        (rs_ga2d_start() != RS_ENOTSUP) || (rs_ga2d_wait(1U) != RS_ENOTSUP) ||
        (rs_ga2d_get_stats(NULL) != RS_EINVAL) || (rs_ga2d_get_stats(&stats) != RS_ENOTSUP) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COMMAND) != UINT32_C(0xA5A5A5A5))) {
        return 3;
    }

    test_ga2d_mmio_reset();
    if ((rs_ga2d_job_validate(&fill) != RS_OK) || (rs_ga2d_configure(&fill) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_JOB_CONFIG) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_GLOBAL_ALPHA) != fill.global_alpha) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COLOR) != fill.color) ||
        (GA2D_TEST_REG(RS_GA2D_REG_SIZE) != UINT32_C(0x00030005)) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_ADDRESS) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_PITCH) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_FORMAT) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_ADDRESS) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_PITCH) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_FORMAT) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_ADDRESS) != fill.destination.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_PITCH) != fill.destination.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_FORMAT) != fill.destination.format)) {
        return 4;
    }
    if ((rs_ga2d_configure(&copy) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_JOB_CONFIG) != RS_GA2D_OP_COPY) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_ADDRESS) != copy.foreground.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_PITCH) != copy.foreground.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_FG_FORMAT) != copy.foreground.format) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_ADDRESS) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_PITCH) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_BG_FORMAT) != 0U) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_ADDRESS) != copy.destination.address) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_PITCH) != copy.destination.pitch) ||
        (GA2D_TEST_REG(RS_GA2D_REG_DST_FORMAT) != copy.destination.format)) {
        return 5;
    }

    fill.width = 0U;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 6;
    }
    fill.width = 5U;
    fill.destination.format = RS_GA2D_FORMAT_A8;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 7;
    }
    fill.destination.format = (rs_ga2d_format_t)5;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 8;
    }
    fill.destination.format = RS_GA2D_FORMAT_RGB888;
    fill.destination.pitch = 14U;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 9;
    }
    fill.destination.address = (uintptr_t)UINT32_C(0x38001001);
    fill.destination.pitch = 16U;
    if (rs_ga2d_job_validate(&fill) != RS_OK) {
        return 10;
    }
    fill.destination.format = RS_GA2D_FORMAT_RGB565;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 11;
    }
    fill.destination.address = (uintptr_t)UINT32_C(0xFFFFFFFC);
    fill.destination.pitch = 4U;
    fill.destination.format = RS_GA2D_FORMAT_XRGB8888;
    fill.width = 1U;
    fill.height = 2U;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 12;
    }
    fill.destination.address = (uintptr_t)UINT32_C(0x10000000);
    fill.destination.pitch = 4U;
    fill.destination.format = RS_GA2D_FORMAT_XRGB8888;
    fill.width = 1U;
    fill.height = 1U;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 13;
    }
#if UINTPTR_MAX > UINT32_MAX
    fill.destination.address = (uintptr_t)UINT64_C(0x100000000);
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 14;
    }
#endif
    fill.destination.address = (uintptr_t)UINT32_C(0x38001000);
    fill.destination.pitch = 15U;
    fill.destination.format = RS_GA2D_FORMAT_RGB888;
    fill.width = 5U;
    fill.height = 3U;
    fill.destination.address = (uintptr_t)UINT32_C(0x40001001);
    fill.destination.pitch = 16U;
    if (rs_ga2d_job_validate(&fill) != RS_OK) {
        return 15;
    }
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_OPI;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 16;
    }
    fill.destination.address = (uintptr_t)UINT32_C(0x48001001);
    if (rs_ga2d_job_validate(&fill) != RS_OK) {
        return 17;
    }
    rs_ga2d_test_mem_pad_mode = (uint32_t)RS_MEMORY_PAD_QPI;
    if (rs_ga2d_job_validate(&fill) != RS_EINVAL) {
        return 18;
    }
    fill.destination.address = (uintptr_t)UINT32_C(0x38001000);
    fill.destination.pitch = 15U;
    copy.destination.address = copy.foreground.address;
    if (rs_ga2d_job_validate(&copy) != RS_EINVAL) {
        return 19;
    }
    copy.destination.address = (uintptr_t)UINT32_C(0x38003000);
    copy.operation = RS_GA2D_OP_CONVERT;
    if (rs_ga2d_job_validate(&copy) != RS_OK) {
        return 20;
    }
    copy.operation = RS_GA2D_OP_COPY;

    GA2D_TEST_REG(RS_GA2D_REG_IRQ_STATE) = RS_GA2D_IRQ_ALL;
    GA2D_TEST_REG(RS_GA2D_REG_ERROR_STATUS) = RS_GA2D_ERROR_STATUS_VALID;
    if ((rs_ga2d_start() != RS_OK) || (GA2D_TEST_REG(RS_GA2D_REG_IRQ_STATE) != RS_GA2D_IRQ_ALL) ||
        (GA2D_TEST_REG(RS_GA2D_REG_ERROR_STATUS) != RS_GA2D_ERROR_STATUS_VALID) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COMMAND) != RS_GA2D_COMMAND_START)) {
        return 21;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DATA_READY;
    GA2D_TEST_REG(RS_GA2D_REG_IRQ_STATE) = RS_GA2D_IRQ_DONE;
    if (rs_ga2d_wait(1U) != RS_ETIMEOUT) {
        return 22;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DONE;
    if (rs_ga2d_wait(0U) != RS_OK) {
        return 23;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DONE | RS_GA2D_STATUS_ERROR;
    if (rs_ga2d_wait(1U) != RS_EIO) {
        return 24;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DONE | RS_GA2D_STATUS_BUSY;
    if (rs_ga2d_wait(1U) != RS_ETIMEOUT) {
        return 25;
    }

    GA2D_TEST_REG(RS_GA2D_REG_STATUS) =
        RS_GA2D_STATUS_BUSY | RS_GA2D_STATUS_DATA_READY | RS_GA2D_STATUS_ERROR;
    GA2D_TEST_REG(RS_GA2D_REG_IRQ_STATE) = RS_GA2D_IRQ_DONE | RS_GA2D_IRQ_ABORT_DONE;
    if ((rs_ga2d_get_status(NULL) != RS_EINVAL) || (rs_ga2d_get_status(&status) != RS_OK) ||
        !status.busy || !status.data_ready || !status.error ||
        (status.irq_state != (RS_GA2D_IRQ_DONE | RS_GA2D_IRQ_ABORT_DONE))) {
        return 26;
    }
    GA2D_TEST_REG(RS_GA2D_REG_ERROR_STATUS) =
        RS_GA2D_ERROR_STATUS_VALID | (UINT32_C(11) << RS_GA2D_ERROR_STATUS_CODE_SHIFT) |
        (UINT32_C(5) << RS_GA2D_ERROR_STATUS_STAGE_SHIFT) |
        (UINT32_C(2) << RS_GA2D_ERROR_STATUS_AXI_RESPONSE_SHIFT);
    GA2D_TEST_REG(RS_GA2D_REG_ERROR_ADDRESS) = UINT32_C(0x30000040);
    if ((rs_ga2d_get_error(NULL) != RS_EINVAL) || (rs_ga2d_get_error(&error) != RS_OK) ||
        !error.valid || (error.code != 11U) || (error.stage != 5U) || (error.axi_response != 2U) ||
        (error.address != (uintptr_t)UINT32_C(0x30000040))) {
        return 27;
    }

    if ((rs_ga2d_irq_enable(RS_GA2D_IRQ_ALL) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_IRQ_ENABLE) != RS_GA2D_IRQ_ALL) ||
        (rs_ga2d_irq_pending(NULL) != RS_EINVAL) ||
        (rs_ga2d_irq_pending(&capability.features) != RS_OK) ||
        (capability.features != (RS_GA2D_IRQ_DONE | RS_GA2D_IRQ_ABORT_DONE)) ||
        (rs_ga2d_irq_clear(RS_GA2D_IRQ_ERROR) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_IRQ_STATE) != RS_GA2D_IRQ_ERROR) ||
        (rs_ga2d_irq_enable(UINT32_C(0x8)) != RS_EINVAL)) {
        return 28;
    }

    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DATA_READY;
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_CYCLES_LO) = UINT32_C(0x89ABCDEF);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_CYCLES_HI) = UINT32_C(0x01234567);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_READ_BYTES_LO) = UINT32_C(0x11111111);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_READ_BYTES_HI) = UINT32_C(0x22222222);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_WRITE_BYTES_LO) = UINT32_C(0x33333333);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_WRITE_BYTES_HI) = UINT32_C(0x44444444);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_READ_STALL_LO) = UINT32_C(0x55555555);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_READ_STALL_HI) = UINT32_C(0x66666666);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_WRITE_STALL_LO) = UINT32_C(0x77777777);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_WRITE_STALL_HI) = UINT32_C(0x88888888);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_PIPE_STALL_LO) = UINT32_C(0x99999999);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_PIPE_STALL_HI) = UINT32_C(0xAAAAAAAA);
    GA2D_TEST_REG(RS_GA2D_REG_SNAP_LINES_DONE) = UINT32_C(0x0000FEDC);
    if ((rs_ga2d_get_stats(&stats) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_PERF_SNAPSHOT) != UINT32_C(1)) ||
        (stats.cycles != UINT64_C(0x0123456789ABCDEF)) ||
        (stats.read_bytes != UINT64_C(0x2222222211111111)) ||
        (stats.write_bytes != UINT64_C(0x4444444433333333)) ||
        (stats.read_stalls != UINT64_C(0x6666666655555555)) ||
        (stats.write_stalls != UINT64_C(0x8888888877777777)) ||
        (stats.pipe_stalls != UINT64_C(0xAAAAAAAA99999999)) ||
        (stats.lines_done != UINT16_C(0xFEDC))) {
        return 29;
    }
    if ((rs_ga2d_reset() != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COMMAND) != RS_GA2D_COMMAND_SOFT_RESET)) {
        return 30;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_RECOVERY_REQUIRED;
    GA2D_TEST_REG(RS_GA2D_REG_COMMAND) = UINT32_C(0x5A5A5A5A);
    if ((rs_ga2d_reset() != RS_EIO) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COMMAND) != UINT32_C(0x5A5A5A5A))) {
        return 31;
    }

    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_DATA_READY;
    if ((rs_ga2d_abort_wait(0U) != RS_OK) ||
        (GA2D_TEST_REG(RS_GA2D_REG_COMMAND) != RS_GA2D_COMMAND_ABORT)) {
        return 32;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = 0U;
    if (rs_ga2d_abort_wait(1U) != RS_EIO) {
        return 33;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_BUSY;
    if (rs_ga2d_abort_wait(1U) != RS_ETIMEOUT) {
        return 34;
    }
    GA2D_TEST_REG(RS_GA2D_REG_STATUS) = RS_GA2D_STATUS_RECOVERY_REQUIRED;
    if (rs_ga2d_abort_wait(1U) != RS_EIO) {
        return 35;
    }
    return 0;
}

static int test_jpeg_validation(void) {
    static _Alignas(RS_JPEG_DESCRIPTOR_ALIGNMENT) rs_jpeg_descriptor_t ring[2];
    rs_jpeg_descriptor_t descriptor;
    rs_jpeg_job_t job = {
        .mode = RS_JPEG_MODE_ENCODE,
        .input_format = RS_JPEG_FORMAT_RGB565,
        .output_format = RS_JPEG_FORMAT_RGB565,
        .sampling = RS_JPEG_SAMPLING_420,
        .width = 1920U,
        .height = 1080U,
        .quality = 75U,
        .table_context = 0U,
        .restart_interval = 64U,
        .bitstream = (uintptr_t)UINT32_C(0x38000000),
        .bitstream_size = UINT32_C(0x00100000),
        .planes = {(uintptr_t)UINT32_C(0x38100000), (uintptr_t)0U, (uintptr_t)0U},
        .strides = {3840U, 0U, 0U},
        .metadata = (uintptr_t)0U,
        .metadata_length = 0U,
        .auto_header = true,
        .strict = true,
    };

    if ((rs_jpeg_job_validate(&job) != RS_OK) ||
        (rs_jpeg_descriptor_build(&descriptor, &job, UINT64_C(0x123456789ABCDEF0), true) !=
         RS_OK) ||
        (descriptor.image_size != UINT32_C(0x04380780)) ||
        (descriptor.cookie_lo != UINT32_C(0x9ABCDEF0)) ||
        (descriptor.cookie_hi != UINT32_C(0x12345678)) ||
        ((descriptor.control &
          (RS_JPEG_DESCRIPTOR_OWN | RS_JPEG_DESCRIPTOR_IOC | RS_JPEG_DESCRIPTOR_ENCODE)) !=
         (RS_JPEG_DESCRIPTOR_OWN | RS_JPEG_DESCRIPTOR_IOC | RS_JPEG_DESCRIPTOR_ENCODE))) {
        return 1;
    }
    if ((rs_jpeg_ring_validate(ring, 2U) != RS_OK) ||
        (rs_jpeg_ring_validate(ring, 3U) != RS_EINVAL) ||
        (rs_jpeg_ring_validate(NULL, 2U) != RS_EINVAL)) {
        return 2;
    }
    job.quality = 0U;
    if (rs_jpeg_job_validate(&job) != RS_EINVAL) {
        return 3;
    }
    job.quality = 75U;
    job.strides[0] = 3839U;
    if (rs_jpeg_job_validate(&job) != RS_EINVAL) {
        return 4;
    }
    job.strides[0] = 3840U;
    job.bitstream += 1U;
    if (rs_jpeg_job_validate(&job) != RS_EINVAL) {
        return 5;
    }
    job.bitstream -= 1U;
    job.metadata = (uintptr_t)UINT32_C(0x38200000);
    job.metadata_length = 8U;
    if (rs_jpeg_job_validate(&job) != RS_EINVAL) {
        return 6;
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

static void test_npu_mmio_reset(void) {
    for (size_t index = 0U; index < (sizeof(rs_npu_test_mmio) / sizeof(rs_npu_test_mmio[0]));
         ++index) {
        rs_npu_test_mmio[index] = 0U;
    }
    NPU_TEST_REG(RS_NPU_REG_IP_ID) = RS_NPU_IP_ID_VALUE;
    NPU_TEST_REG(RS_NPU_REG_IP_VERSION) = RS_NPU_IP_VERSION_VALUE;
    NPU_TEST_REG(RS_NPU_REG_CAPABILITY) = RS_NPU_CAPABILITY_P2;
    NPU_TEST_REG(RS_NPU_REG_NUMERIC_PROFILE) = RS_NPU_NUMERIC_PROFILE_VALUE;
    NPU_TEST_REG(RS_NPU_REG_DESCRIPTOR_BYTES) = RS_NPU_DESCRIPTOR_BYTES;
    NPU_TEST_REG(RS_NPU_REG_TIMEOUT_CYCLES) = RS_NPU_TIMEOUT_CYCLES_RESET;
    NPU_TEST_REG(RS_NPU_REG_FAULT_DESCRIPTOR) = RS_NPU_FAULT_DESCRIPTOR_RESET;
}

static int test_npu_capability_contract(void) {
    rs_npu_capability_t capability;

    test_npu_mmio_reset();
    if (rs_npu_get_capability(NULL) != RS_EINVAL) {
        return 1;
    }
    if ((rs_npu_get_capability(&capability) != RS_OK) || (capability.ip_id != RS_NPU_IP_ID_VALUE) ||
        (capability.ip_version != RS_NPU_IP_VERSION_VALUE) ||
        (capability.flags != RS_NPU_CAPABILITY_P2) ||
        (capability.numeric_profile != RS_NPU_NUMERIC_PROFILE_VALUE) ||
        (capability.local_bytes != 0U) || (capability.dense_macs != 0U) ||
        (capability.depthwise_macs != 0U) || (capability.max_k_slice != 0U) ||
        (capability.max_dimension != 0U) || (capability.op_mask != 0U)) {
        return 2;
    }
    NPU_TEST_REG(RS_NPU_REG_MAC_CONFIG) = RS_NPU_MAC_CONFIG_VALUE;
    NPU_TEST_REG(RS_NPU_REG_LOCAL_BYTES) = RS_NPU_LOCAL_BYTES_VALUE;
    NPU_TEST_REG(RS_NPU_REG_MAX_K_SLICE) = RS_NPU_MAX_K_SLICE;
    NPU_TEST_REG(RS_NPU_REG_MAX_DIMENSION) = RS_NPU_MAX_DIMENSION;
    NPU_TEST_REG(RS_NPU_REG_OP_CAPABILITY) = RS_NPU_OP_CAPABILITY_MVP;
    if ((rs_npu_get_capability(&capability) != RS_OK) ||
        (capability.local_bytes != RS_NPU_LOCAL_BYTES_VALUE) || (capability.dense_macs != 64U) ||
        (capability.depthwise_macs != 8U) || (capability.max_k_slice != RS_NPU_MAX_K_SLICE) ||
        (capability.max_dimension != RS_NPU_MAX_DIMENSION) ||
        (capability.op_mask != RS_NPU_OP_CAPABILITY_MVP)) {
        return 3;
    }
    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_IP_ID) = 0U;
    if (rs_npu_get_capability(&capability) != RS_ENOTSUP) {
        return 4;
    }
    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_IP_VERSION) = UINT32_C(0x00020000);
    if (rs_npu_get_capability(&capability) != RS_ENOTSUP) {
        return 5;
    }
    return 0;
}

static int test_npu_irq_contract(void) {
    uint32_t events = 0U;

    test_npu_mmio_reset();
    if (rs_npu_irq_pending(NULL) != RS_EINVAL) {
        return 1;
    }
    if ((rs_npu_irq_enable(RS_NPU_IRQ_ALL | UINT32_C(0x8)) != RS_EINVAL) ||
        (rs_npu_irq_ack(UINT32_C(0x80000000)) != RS_EINVAL)) {
        return 2;
    }
    if ((rs_npu_irq_enable(RS_NPU_IRQ_DONE | RS_NPU_IRQ_ERROR) != RS_OK) ||
        (NPU_TEST_REG(RS_NPU_REG_IRQ_ENABLE) != (RS_NPU_IRQ_DONE | RS_NPU_IRQ_ERROR))) {
        return 3;
    }
    if ((rs_npu_irq_enable(RS_NPU_IRQ_ABORTED) != RS_OK) ||
        (NPU_TEST_REG(RS_NPU_REG_IRQ_ENABLE) != RS_NPU_IRQ_ABORTED)) {
        return 4;
    }
    NPU_TEST_REG(RS_NPU_REG_IRQ_STATE) = RS_NPU_IRQ_DONE | RS_NPU_IRQ_ABORTED;
    if ((rs_npu_irq_pending(&events) != RS_OK) ||
        (events != (RS_NPU_IRQ_DONE | RS_NPU_IRQ_ABORTED))) {
        return 5;
    }
    /* The MMIO array is plain memory: the HAL writes the W1C mask and the test
       then models the hardware clear that the write requests. */
    if ((rs_npu_irq_ack(RS_NPU_IRQ_DONE) != RS_OK) ||
        (NPU_TEST_REG(RS_NPU_REG_IRQ_STATE) != RS_NPU_IRQ_DONE)) {
        return 6;
    }
    NPU_TEST_REG(RS_NPU_REG_IRQ_STATE) = (RS_NPU_IRQ_DONE | RS_NPU_IRQ_ABORTED) & ~RS_NPU_IRQ_DONE;
    if ((rs_npu_irq_pending(&events) != RS_OK) || (events != RS_NPU_IRQ_ABORTED)) {
        return 7;
    }
    NPU_TEST_REG(RS_NPU_REG_CAPABILITY) = RS_NPU_CAPABILITY_PRESENT;
    if ((rs_npu_irq_enable(RS_NPU_IRQ_DONE) != RS_ENOTSUP) ||
        (rs_npu_irq_pending(&events) != RS_ENOTSUP) ||
        (rs_npu_irq_ack(RS_NPU_IRQ_DONE) != RS_ENOTSUP)) {
        return 8;
    }
    return 0;
}

static int test_npu_submit_p2(void) {
    const rs_npu_job_t job = {
        .descriptor_address = UINT32_C(0x10000000),
        .descriptor_count = 2U,
        .job_id = UINT32_C(0xA5),
        .timeout_cycles = UINT32_C(72000000),
    };
    rs_npu_job_t malformed = job;

    test_npu_mmio_reset();
    if (rs_npu_submit(NULL) != RS_EINVAL) {
        return 1;
    }
    malformed.descriptor_address = UINT32_C(0x10000001);
    if (rs_npu_submit(&malformed) != RS_EINVAL) {
        return 2;
    }
    malformed.descriptor_address = job.descriptor_address;
    malformed.descriptor_count = 0U;
    if (rs_npu_submit(&malformed) != RS_EINVAL) {
        return 3;
    }
    malformed.descriptor_count = RS_NPU_JOB_COUNT_VALUE_MASK + 1U;
    if (rs_npu_submit(&malformed) != RS_EINVAL) {
        return 4;
    }
    malformed.descriptor_count = job.descriptor_count;
    malformed.timeout_cycles = 0U;
    if (rs_npu_submit(&malformed) != RS_EINVAL) {
        return 5;
    }
    malformed.timeout_cycles = job.timeout_cycles;
    malformed.descriptor_address = UINT32_C(0xFFFFFFC0);
    malformed.descriptor_count = 2U;
    if (rs_npu_submit(&malformed) != RS_EINVAL) {
        return 6;
    }
    /* P2 advertises no EXECUTION_READY: a valid job is refused without writes. */
    if ((rs_npu_submit(&job) != RS_ENOTSUP) || (NPU_TEST_REG(RS_NPU_REG_CONTROL) != 0U) ||
        (NPU_TEST_REG(RS_NPU_REG_JOB_BASE) != 0U) || (NPU_TEST_REG(RS_NPU_REG_JOB_COUNT) != 0U) ||
        (NPU_TEST_REG(RS_NPU_REG_JOB_ID) != 0U)) {
        return 7;
    }
    NPU_TEST_REG(RS_NPU_REG_CAPABILITY) = 0U;
    if (rs_npu_submit(&job) != RS_ENOTSUP) {
        return 8;
    }
    return 0;
}

static int test_npu_wait_abort_contract(void) {
    rs_npu_status_t status;

    test_npu_mmio_reset();
    if ((rs_npu_wait(0U, 0U, NULL) != RS_EINVAL) ||
        (rs_npu_abort_wait(0U, 0U, NULL) != RS_EINVAL)) {
        return 1;
    }
    /* P2 retains no active or terminal job: no token is known. */
    if ((rs_npu_wait(UINT32_C(0xA5), 0U, &status) != RS_EINVAL) ||
        (rs_npu_abort_wait(UINT32_C(0xA5), 0U, &status) != RS_EINVAL)) {
        return 2;
    }
    NPU_TEST_REG(RS_NPU_REG_IP_ID) = 0U;
    if ((rs_npu_wait(UINT32_C(0xA5), 0U, &status) != RS_ENOTSUP) ||
        (rs_npu_abort_wait(UINT32_C(0xA5), 0U, &status) != RS_ENOTSUP)) {
        return 3;
    }

    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_RESULT_VALID;
    NPU_TEST_REG(RS_NPU_REG_RESULT_JOB_ID) = UINT32_C(0xA5);
    NPU_TEST_REG(RS_NPU_REG_RESULT_CODE) = RS_NPU_RESULT_DONE;
    NPU_TEST_REG(RS_NPU_REG_COMPLETED_DESCRIPTORS) = 7U;
    NPU_TEST_REG(RS_NPU_REG_RECOVERY_GENERATION) = 3U;
    if ((rs_npu_wait(UINT32_C(0xA5), 0U, &status) != RS_OK) ||
        (status.flags != RS_NPU_STATUS_RESULT_VALID) || (status.job_id != UINT32_C(0xA5)) ||
        (status.result_code != RS_NPU_RESULT_DONE) || (status.completed_descriptors != 7U) ||
        (status.recovery_generation != 3U)) {
        return 4;
    }
    /* abort on an already terminal token is a no-op that reports the result */
    if ((rs_npu_abort_wait(UINT32_C(0xA5), 0U, &status) != RS_OK) ||
        (NPU_TEST_REG(RS_NPU_REG_CONTROL) != 0U)) {
        return 5;
    }
    if (rs_npu_wait(UINT32_C(0x5A), 0U, &status) != RS_EINVAL) {
        return 6;
    }
    NPU_TEST_REG(RS_NPU_REG_RESULT_CODE) = RS_NPU_RESULT_ERROR;
    if (rs_npu_wait(UINT32_C(0xA5), 0U, &status) != RS_EIO) {
        return 7;
    }
    NPU_TEST_REG(RS_NPU_REG_RESULT_CODE) = RS_NPU_RESULT_ABORTED;
    if (rs_npu_abort_wait(UINT32_C(0xA5), 0U, &status) != RS_EIO) {
        return 8;
    }
    NPU_TEST_REG(RS_NPU_REG_RESULT_CODE) = RS_NPU_RESULT_RESET_CANCELLED;
    if (rs_npu_wait(UINT32_C(0xA5), 0U, &status) != RS_EIO) {
        return 9;
    }

    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_BUSY;
    NPU_TEST_REG(RS_NPU_REG_JOB_ID) = UINT32_C(0xA5);
    if ((rs_npu_wait(UINT32_C(0xA5), 4U, &status) != RS_ETIMEOUT) ||
        (status.flags != RS_NPU_STATUS_BUSY)) {
        return 10;
    }
    /* abort writes CONTROL.ABORT once for the active token, then expires */
    if ((rs_npu_abort_wait(UINT32_C(0xA5), 4U, &status) != RS_ETIMEOUT) ||
        (NPU_TEST_REG(RS_NPU_REG_CONTROL) != RS_NPU_CONTROL_ABORT)) {
        return 11;
    }
    return 0;
}

static int test_npu_status_error_contract(void) {
    rs_npu_status_t status;
    rs_npu_error_t error;

    test_npu_mmio_reset();
    if ((rs_npu_get_status(NULL) != RS_EINVAL) || (rs_npu_get_error(NULL) != RS_EINVAL)) {
        return 1;
    }
    /* P2 reset state: not READY, no retained result, fault index all ones */
    if ((rs_npu_get_status(&status) != RS_OK) || (status.flags != 0U) || (status.job_id != 0U) ||
        (status.result_code != RS_NPU_RESULT_NONE) || (status.completed_descriptors != 0U) ||
        (status.recovery_generation != 0U)) {
        return 2;
    }
    if ((rs_npu_get_error(&error) != RS_OK) || (error.code != RS_NPU_FAULT_NONE) ||
        (error.address != 0U) || (error.descriptor_index != RS_NPU_FAULT_DESCRIPTOR_RESET) ||
        (error.info != 0U)) {
        return 3;
    }
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_BUSY | RS_NPU_STATUS_DRAINING |
                                      RS_NPU_STATUS_CLOCK_PAUSED | RS_NPU_STATUS_RECOVERING |
                                      RS_NPU_STATUS_RESULT_VALID;
    NPU_TEST_REG(RS_NPU_REG_RESULT_JOB_ID) = UINT32_C(0x55);
    NPU_TEST_REG(RS_NPU_REG_RESULT_CODE) = RS_NPU_RESULT_ERROR;
    NPU_TEST_REG(RS_NPU_REG_COMPLETED_DESCRIPTORS) = 5U;
    NPU_TEST_REG(RS_NPU_REG_RECOVERY_GENERATION) = 9U;
    NPU_TEST_REG(RS_NPU_REG_FAULT_CODE) = RS_NPU_FAULT_AXI_READ;
    NPU_TEST_REG(RS_NPU_REG_FAULT_ADDRESS) = UINT32_C(0x10000040);
    NPU_TEST_REG(RS_NPU_REG_FAULT_DESCRIPTOR) = 2U;
    NPU_TEST_REG(RS_NPU_REG_FAULT_INFO) =
        (UINT32_C(2) << RS_NPU_FAULT_INFO_AXI_RESPONSE_SHIFT) |
        (RS_NPU_FAULT_INFO_DIRECTION_READ << RS_NPU_FAULT_INFO_DIRECTION_SHIFT) |
        (UINT32_C(12) << RS_NPU_FAULT_INFO_LANE_SHIFT);
    if ((rs_npu_get_status(&status) != RS_OK) ||
        (status.flags != NPU_TEST_REG(RS_NPU_REG_STATUS)) || (status.job_id != UINT32_C(0x55)) ||
        (status.result_code != RS_NPU_RESULT_ERROR) || (status.completed_descriptors != 5U) ||
        (status.recovery_generation != 9U)) {
        return 4;
    }
    if ((rs_npu_get_error(&error) != RS_OK) || (error.code != RS_NPU_FAULT_AXI_READ) ||
        (error.address != UINT32_C(0x10000040)) || (error.descriptor_index != 2U) ||
        (error.info != NPU_TEST_REG(RS_NPU_REG_FAULT_INFO))) {
        return 5;
    }
    NPU_TEST_REG(RS_NPU_REG_IP_VERSION) = 0U;
    if ((rs_npu_get_status(&status) != RS_ENOTSUP) || (rs_npu_get_error(&error) != RS_ENOTSUP)) {
        return 6;
    }
    return 0;
}

static int test_npu_snapshot_contract(void) {
    rs_npu_counters_t counters;

    test_npu_mmio_reset();
    if (rs_npu_snapshot_counters(0U, NULL) != RS_EINVAL) {
        return 1;
    }
    NPU_TEST_REG(RS_NPU_REG_PERF_STATUS) = RS_NPU_PERF_STATUS_SNAP_BUSY;
    if (rs_npu_snapshot_counters(0U, &counters) != RS_EINVAL) {
        return 2;
    }
    test_npu_mmio_reset();
    if ((rs_npu_snapshot_counters(4U, &counters) != RS_ETIMEOUT) ||
        (NPU_TEST_REG(RS_NPU_REG_PERF_CONTROL) != RS_NPU_PERF_CONTROL_SNAPSHOT)) {
        return 3;
    }
    /* idle zero-bank snapshot: valid without any job execution evidence */
    NPU_TEST_REG(RS_NPU_REG_PERF_STATUS) = RS_NPU_PERF_STATUS_SNAP_VALID;
    if ((rs_npu_snapshot_counters(0U, &counters) != RS_OK) || (counters.job_id != 0U) ||
        (counters.recovery_generation != 0U) || (counters.active_cycles != 0U) ||
        (counters.clock_pause_cycles != 0U) || (counters.useful_macs != 0U) ||
        (counters.pack_cycles != 0U) || (counters.local_bank_stall_cycles != 0U) ||
        (counters.dma_read_bytes != 0U) || (counters.dma_write_bytes != 0U) ||
        (counters.dma_stall_cycles != 0U) || (counters.requant_stall_cycles != 0U) ||
        (counters.retired_descriptors != 0U)) {
        return 4;
    }
    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_PERF_STATUS) = RS_NPU_PERF_STATUS_SNAP_VALID;
    NPU_TEST_REG(RS_NPU_REG_PERF_JOB_ID) = UINT32_C(0x5A);
    NPU_TEST_REG(RS_NPU_REG_PERF_GENERATION) = 2U;
    for (uint32_t index = 0U; index < 10U; ++index) {
        NPU_TEST_REG(RS_NPU_REG_PERF_ACTIVE_CYCLES_LO + (index * 8U)) = index + 1U;
        NPU_TEST_REG(RS_NPU_REG_PERF_ACTIVE_CYCLES_HI + (index * 8U)) = index + 101U;
    }
    if (rs_npu_snapshot_counters(0U, &counters) != RS_OK) {
        return 5;
    }
    {
        const uint64_t values[10] = {
            counters.active_cycles,
            counters.clock_pause_cycles,
            counters.useful_macs,
            counters.pack_cycles,
            counters.local_bank_stall_cycles,
            counters.dma_read_bytes,
            counters.dma_write_bytes,
            counters.dma_stall_cycles,
            counters.requant_stall_cycles,
            counters.retired_descriptors,
        };
        for (uint32_t index = 0U; index < 10U; ++index) {
            const uint64_t expected = ((uint64_t)(index + 101U) << 32U) | (uint64_t)(index + 1U);

            if (values[index] != expected) {
                return 6;
            }
        }
    }
    if ((counters.job_id != UINT32_C(0x5A)) || (counters.recovery_generation != 2U)) {
        return 7;
    }
    NPU_TEST_REG(RS_NPU_REG_IP_ID) = 0U;
    if (rs_npu_snapshot_counters(0U, &counters) != RS_ENOTSUP) {
        return 8;
    }
    return 0;
}

static int test_npu_reset_contract(void) {
    test_npu_mmio_reset();
    /* the idle P2 shell accepts SOFT_RESET; READY stays low by design */
    if ((rs_npu_reset(0U) != RS_OK) ||
        (NPU_TEST_REG(RS_NPU_REG_CONTROL) != RS_NPU_CONTROL_SOFT_RESET)) {
        return 1;
    }
    NPU_TEST_REG(RS_NPU_REG_CONTROL) = 0U;
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_BUSY;
    if ((rs_npu_reset(0U) != RS_EINVAL) || (NPU_TEST_REG(RS_NPU_REG_CONTROL) != 0U)) {
        return 2;
    }
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_DRAINING;
    if (rs_npu_reset(0U) != RS_EINVAL) {
        return 3;
    }
    NPU_TEST_REG(RS_NPU_REG_STATUS) = RS_NPU_STATUS_RECOVERING;
    if (rs_npu_reset(0U) != RS_EINVAL) {
        return 4;
    }
    /* a snapshot transfer in flight also rejects reset */
    test_npu_mmio_reset();
    NPU_TEST_REG(RS_NPU_REG_PERF_STATUS) = RS_NPU_PERF_STATUS_SNAP_BUSY;
    if ((rs_npu_reset(0U) != RS_EINVAL) || (NPU_TEST_REG(RS_NPU_REG_CONTROL) != 0U)) {
        return 5;
    }
    NPU_TEST_REG(RS_NPU_REG_PERF_STATUS) = 0U;
    NPU_TEST_REG(RS_NPU_REG_IP_ID) = 0U;
    if (rs_npu_reset(0U) != RS_ENOTSUP) {
        return 6;
    }
    return 0;
}

int main(void) {
    const int results[] = {
        test_string_helpers(),
        test_formatter(),
        test_compiler_helpers(),
        test_wait_helper(),
        test_clock_frequency_contract(),
        test_ws2812_helpers(),
        test_timer_helpers(),
        test_psram_helpers(),
        test_sdram_helpers(),
        test_uart_helpers(),
        test_i2s_helpers(),
        test_i2c_helpers(),
        test_sdio_helpers(),
        test_usb2_helpers(),
        test_spisd_helpers(),
        test_gpio_helpers(),
        test_dma_config_validation(),
        test_opipsram_helpers(),
        test_user_ip_validation(),
        test_extension_validation(),
        test_resource_validation(),
        test_fabric_monitor_hal_contract(),
        test_apu_validation(),
        test_apu_kws_validation(),
        test_apu_hal_contract(),
        test_ga2d_pixel_math(),
        test_ga2d_p5_validation(),
        test_ga2d_validation_precedence(),
        test_ga2d_hal_contract(),
        test_npu_capability_contract(),
        test_npu_irq_contract(),
        test_npu_submit_p2(),
        test_npu_wait_abort_contract(),
        test_npu_status_error_contract(),
        test_npu_snapshot_contract(),
        test_npu_reset_contract(),
        test_jpeg_validation(),
        test_ps2_decoders(),
        test_wav_parser(),
        test_video_parser(),
    };

    for (size_t index = 0U; index < (sizeof(results) / sizeof(results[0])); ++index) {
        if (results[index] != 0) {
            return (int)(index + 1U);
        }
    }
    return 0;
}
