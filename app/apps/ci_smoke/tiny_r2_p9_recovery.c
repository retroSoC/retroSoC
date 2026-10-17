#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/generated/irq_metadata.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/hal/rcu.h>
#include <retrosoc/hal/rcu_regs.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/xpi_psram.h>
#include <retrosoc/lib/printf.h>

#include "p9_frame.h"
#include "p9_startup.h"

#define RS_P9_RECOVERY_TIMEOUT  ((rs_timeout_t)20000U)
#define RS_P9_RECOVERY_DVP_MASK UINT32_C(0x4000)
#define RS_P9_RECOVERY_ADDRESS  UINT32_C(0x54010000)
static _Alignas(64) uint32_t rs_p9_recovery_buffer[66];
static volatile uint32_t rs_p9_recovery_irqs;
static uint32_t rs_p9_recovery_frames;
static uint32_t rs_p9_recovery_cases;

static void rs_p9_recovery_irq(uintptr_t cause, uintptr_t stack) {
    (void)cause;
    (void)stack;
    /* Preserve FRAME_DONE for the polling helper while quiescing the level. */
    (void)rs_dvp_interrupt_enable(0U);
    rs_p9_recovery_irqs++;
}

static bool rs_p9_recovery_delay(uint32_t microseconds) {
    uint64_t start;
    uint64_t now;
    rs_timeout_t budget = RS_P9_RECOVERY_TIMEOUT;
    if (rs_clint_get_time(&start) != RS_OK) {
        return false;
    }
    do {
        if (budget-- == 0U || rs_clint_get_time(&now) != RS_OK) {
            return false;
        }
    } while (now - start < microseconds);
    return true;
}

static bool rs_p9_recovery_route(bool camera) {
    const rs_gpio_config_t config = {.mode = camera ? RS_GPIO_MODE_ALT1 : RS_GPIO_MODE_ALT0,
                                     .pull = RS_GPIO_PULL_NONE,
                                     .trigger = RS_GPIO_TRIGGER_NONE};
    if (camera) {
        printf("P9_CTRL camera\n");
    } else {
        printf("P9_CTRL audio\n");
    }
    if (!rs_p9_recovery_delay(32U)) {
        return false;
    }
    for (uint32_t pin = 12U; pin <= (camera ? 23U : 17U); pin++) {
        if (rs_gpio_configure(pin, &config) != RS_OK) {
            return false;
        }
    }
    return rs_tiny_rcu_set_clkout(camera ? 1U : 0U, camera ? 1U : 0U) == RS_OK;
}

static bool rs_p9_recovery_audio(void) {
    const rs_i2s_config_t audio = {
        .preset = RS_I2S_PRESET_16B_48K, .upbound = 96U, .lowbound = 32U};
    rs_i2s_status_t status;
    uint32_t matched = 0U;
    if (!rs_p9_recovery_route(false) || rs_i2s_configure(&audio) != RS_OK ||
        rs_i2s_flush(true, true, RS_P9_RECOVERY_TIMEOUT) != RS_OK) {
        return false;
    }
    for (uint32_t index = 0U; index < 16U; index++) {
        if (rs_i2s_write(UINT32_C(0x12341234), RS_P9_RECOVERY_TIMEOUT) != RS_OK) {
            return false;
        }
    }
    if (rs_i2s_enable(true, true) != RS_OK) {
        return false;
    }
    for (uint32_t index = 0U; index < 32U && matched < 4U; index++) {
        uint32_t received;
        if (rs_i2s_read(&received, RS_P9_RECOVERY_TIMEOUT) != RS_OK) {
            printf("P9_RECOVERY_AUDIO receive_timeout matched=%u index=%u\n", matched, index);
            return false;
        }
        matched = received == UINT32_C(0x12341234) ? matched + 1U : 0U;
    }
    printf("P9_RECOVERY_AUDIO matched=%u\n", matched);
    if (matched != 4U || rs_i2s_disable() != RS_OK ||
        rs_i2s_flush(true, true, RS_P9_RECOVERY_TIMEOUT) != RS_OK ||
        rs_i2s_get_status(&status) != RS_OK || status.enable ||
        (status.status & RS_I2S_STATUS_BUSY) != 0U) {
        return false;
    }
    return true;
}

static rs_dvp_config_t rs_p9_recovery_config(bool crop, rs_dvp_format_t format) {
    const rs_dvp_config_t config = {.format = format,
                                    .frame_width = 16U,
                                    .frame_height = 8U,
                                    .crop_enable = crop,
                                    .crop_x = crop ? 2U : 0U,
                                    .crop_y = crop ? 1U : 0U,
                                    .crop_width = crop ? 8U : 16U,
                                    .crop_height = crop ? 4U : 8U,
                                    .snapshot = true,
                                    .stream_enable = true};
    return config;
}

static bool rs_p9_recovery_capture(uintptr_t destination, bool crop, rs_dvp_format_t format) {
    const rs_dvp_config_t config = rs_p9_recovery_config(crop, format);
    const uint32_t width = config.crop_width;
    const uint32_t words = width * config.crop_height / 2U;
    volatile uint32_t *const buffer = (volatile uint32_t *)destination;
    volatile uint32_t *const prefix = (volatile uint32_t *)(destination - sizeof(uint32_t));
    rs_dvp_status_t status;
    rs_xpi_error_t error;
    const uint32_t previous_irqs = rs_p9_recovery_irqs;
    if (rs_dvp_configure(&config) != RS_OK ||
        rs_dvp_interrupt_enable(RS_DVP_INTERRUPT_FRAME_DONE) != RS_OK) {
        return false;
    }
    *prefix = UINT32_C(0x13579BDF);
    buffer[words] = UINT32_C(0x2468ACE0);
    const rs_status_t capture = rs_dvp_capture_dma(destination, words, RS_P9_RECOVERY_TIMEOUT);
    if (rs_dvp_get_status(&status) != RS_OK) {
        return false;
    }
    printf("P9_RECOVERY_CAPTURE format=%u crop=%u code=%u words=%u pixels=%u dvp_error=%u "
           "irq_delta=%u\n",
           (unsigned int)format, crop ? 1U : 0U, (unsigned int)capture, status.word_count,
           status.pixel_count, status.error_status, rs_p9_recovery_irqs - previous_irqs);
    if (capture != RS_OK || status.error_status != 0U || status.word_count != words ||
        status.pixel_count != words * 2U || rs_p9_recovery_irqs != previous_irqs + 1U) {
        return false;
    }
    for (uint32_t index = 0U; index < words; index++) {
        const uint32_t row = index / (width / 2U) + config.crop_y;
        const uint32_t column = index % (width / 2U) + config.crop_x / 2U;
        if (buffer[index] != rs_p9_frame_word(row, column, false)) {
            return false;
        }
    }
    if (*prefix != UINT32_C(0x13579BDF) || buffer[words] != UINT32_C(0x2468ACE0) ||
        rs_xpi_error_get(&error) != RS_OK || error.valid) {
        return false;
    }
    rs_p9_recovery_frames++;
    return true;
}

static bool rs_p9_recovery_rejections(void) {
    rs_dvp_config_t config = rs_p9_recovery_config(false, RS_DVP_FORMAT_RGB565);
    rs_dma_status_t before, after;
    if (rs_dvp_configure(&config) != RS_OK ||
        rs_dma_get_status(RS_DMA_CHANNEL_DVP, &before) != RS_OK ||
        rs_dvp_capture_dma(RS_P9_RECOVERY_ADDRESS, 63U, 100U) != RS_ENOSPC) {
        return false;
    }
    config.frame_width = 15U;
    if (rs_dvp_configure(&config) != RS_OK ||
        rs_dvp_capture_dma(RS_P9_RECOVERY_ADDRESS, 64U, 100U) != RS_EINVAL ||
        rs_dma_get_status(RS_DMA_CHANNEL_DVP, &after) != RS_OK || after.busy ||
        after.bytes_done != before.bytes_done) {
        return false;
    }
    config.crop_enable = true;
    config.crop_x = 15U;
    config.crop_width = 2U;
    return rs_dvp_configure(&config) == RS_EINVAL;
}

static bool rs_p9_recovery_stop(bool high) {
    rs_dvp_config_t config = rs_p9_recovery_config(false, RS_DVP_FORMAT_RGB565);
    rs_dvp_status_t status;
    rs_tiny_rcu_snapshot_t snapshot;
    rs_timeout_t budget = RS_P9_RECOVERY_TIMEOUT;
    config.stream_enable = false;
    if (rs_dvp_configure(&config) != RS_OK || rs_dvp_start() != RS_OK) {
        return false;
    }
    do {
        if (budget-- == 0U || rs_dvp_get_status(&status) != RS_OK) {
            return false;
        }
    } while (!status.active);
    if (high) {
        printf("P9_CTRL stop_high\n");
    } else {
        printf("P9_CTRL stop_low\n");
    }
    if (!rs_p9_recovery_delay(32U)) {
        return false;
    }
    const uint32_t old_timeout = RS_SOC_REG32(RS_SOC_APB4_SYSCTRL_BASE, RS_TINY_RCU_TIMEOUT_OFFSET);
    RS_SOC_REG32(RS_SOC_APB4_SYSCTRL_BASE, RS_TINY_RCU_TIMEOUT_OFFSET) = 1024U;
    const rs_status_t reset =
        rs_tiny_rcu_apply_reset(RS_P9_RECOVERY_DVP_MASK, RS_P9_RECOVERY_TIMEOUT);
    if (rs_tiny_rcu_get_snapshot(&snapshot) != RS_OK || rs_dvp_get_status(&status) != RS_OK) {
        return false;
    }
    printf("P9_RECOVERY_DIAG high=%u reset_status=%u fault=%u dvp_error=%u words=%u\n",
           high ? 1U : 0U, (unsigned int)reset, snapshot.fault, status.error_status,
           status.word_count);
    if (reset != RS_ETIMEOUT || snapshot.fault == 0U || snapshot.gate_status != 0U) {
        return false;
    }
    printf("P9_CTRL resume\n");
    if (!rs_p9_recovery_delay(100U) || rs_dvp_abort() != RS_OK ||
        rs_tiny_rcu_clear_fault(RS_TINY_RCU_FAULT_MASK) != RS_OK ||
        rs_tiny_rcu_apply_reset(RS_P9_RECOVERY_DVP_MASK, RS_P9_RECOVERY_TIMEOUT) != RS_OK) {
        return false;
    }
    RS_SOC_REG32(RS_SOC_APB4_SYSCTRL_BASE, RS_TINY_RCU_TIMEOUT_OFFSET) = old_timeout;
    return rs_p9_recovery_capture(RS_P9_RECOVERY_ADDRESS, false, RS_DVP_FORMAT_RGB565);
}

static bool rs_p9_recovery_record(uint32_t id, bool pass) {
    printf("P9_RECOVERY_CASE id=%u pass=%u\n", id, pass ? 1U : 0U);
    if (pass) {
        rs_p9_recovery_cases++;
    }
    return pass;
}

int main(void) {
    rs_tiny_rcu_snapshot_t snapshot;
    rs_xpi_psram_t psram;
    __disable_irq();
    bool pass = rs_tiny_rcu_get_snapshot(&snapshot) == RS_OK &&
                rs_p9_console_ready(&snapshot, rs_uart_init) &&
                rs_p9_psram_pin_ready(rs_gpio_configure);
    pass = pass && rs_p9_recovery_record(1U, rs_p9_recovery_audio());
    pass = pass && rs_p9_recovery_route(true) &&
           rs_xpi_psram_initialize(snapshot.mem_hz, RS_TIMEOUT_DEFAULT, &psram) == RS_OK &&
           rs_xpi_psram_validate_dma(&psram, RS_P9_RECOVERY_ADDRESS, 256U, 4U) == RS_OK &&
           rs_irq_enable_external(RS_SOC_EXT_IRQ_DVP, rs_p9_recovery_irq) == RS_OK;
    __enable_irq();
    pass = pass &&
           rs_p9_recovery_record(
               2U, rs_p9_recovery_capture(RS_P9_RECOVERY_ADDRESS, false, RS_DVP_FORMAT_RGB565) &&
                       rs_p9_recovery_capture(RS_P9_RECOVERY_ADDRESS, true, RS_DVP_FORMAT_YUV422));
    pass = pass && rs_p9_recovery_record(3U, rs_p9_recovery_rejections());
    pass = pass &&
           rs_p9_recovery_record(4U, rs_p9_recovery_capture((uintptr_t)&rs_p9_recovery_buffer[1],
                                                            true, RS_DVP_FORMAT_RGB565));
    pass = pass && rs_p9_recovery_record(5U, rs_p9_recovery_stop(false));
    pass = pass && rs_p9_recovery_record(6U, rs_p9_recovery_stop(true));
    pass = pass && rs_dvp_abort() == RS_OK &&
           rs_p9_recovery_record(
               7U, rs_p9_recovery_audio() && rs_p9_recovery_route(true) &&
                       rs_p9_recovery_capture(RS_P9_RECOVERY_ADDRESS, false, RS_DVP_FORMAT_YUV422));
    __disable_irq();
    printf("P9_RECOVERY_RESULT code=%u cases=%u frames=%u irqs=%u\n", pass ? 0U : 1U,
           rs_p9_recovery_cases, rs_p9_recovery_frames, rs_p9_recovery_irqs);
    /* Drain the last serial record before the testbench's terminal marker. */
    pass = pass && rs_p9_recovery_delay(1000U);
    rs_sysctrl_write_test_status(pass, pass ? 0U : 9U);
    for (;;) {
    }
}
