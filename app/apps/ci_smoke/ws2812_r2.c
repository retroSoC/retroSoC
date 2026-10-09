/* Option A: Mini PIO compatibility only. DMA/MMIO is a separate unsupported
 * product path; its failure evidence and production-crossbar test are retained. */
#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/arch/riscv/system_base.h>
#include <retrosoc/core/irq.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/generated/irq_metadata.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/sysctrl.h>
#include <retrosoc/hal/uart.h>
#include <retrosoc/hal/ws2812.h>
#include <retrosoc/lib/printf.h>

_Static_assert(RS_PCLK_CLOCK_HZ == 24000000U, "Mini PIO acceptance requires PCLK24");

static uint32_t rs_ws_pixels[65];
static volatile bool rs_ws_event;
static volatile uint32_t rs_ws_irqs;
static volatile bool rs_ws_irq_error;
static const rs_ws2812_config_t rs_ws_timing = {
    .source_clock_hz = RS_PCLK_CLOCK_HZ,
    .bit_period_ns = RS_WS2812_DEFAULT_BIT_PERIOD_NS,
    .t0h_ns = RS_WS2812_DEFAULT_T0H_NS,
    .t1h_ns = RS_WS2812_DEFAULT_T1H_NS,
    .reset_ns = RS_WS2812_DEFAULT_RESET_NS,
    .fifo_watermark = 8U,
};

static void rs_ws_interrupt(uintptr_t cause, uintptr_t stack) {
    (void)cause;
    (void)stack;
    ++rs_ws_irqs;
    rs_ws_event = true;
    /* Leave sticky status for the foreground HAL to consume. */
    if (rs_ws2812_irq_enable(0U) != RS_OK) {
        rs_ws_irq_error = true;
    }
}

static void rs_ws_finish(bool pass, uint8_t code) {
    rs_uart_status_t uart;
    bool drained = false;
    __disable_irq();
    printf("WS2812_P3_MINI_PIO %s code=%u irqs=%u dma_mmio=UNSUPPORTED\n", pass ? "PASS" : "FAIL",
           code, rs_ws_irqs);
    for (uint32_t remaining = RS_TIMEOUT_DEFAULT; remaining != 0U; --remaining) {
        if ((rs_uart_get_status(&uart) == RS_OK) && (uart.tx_level == 0U) &&
            ((uart.flags & 4U) == 0U)) {
            drained = true;
            break;
        }
    }
    rs_sysctrl_write_test_status(pass && drained, code);
    for (;;) {
    }
}

static bool rs_ws_idle(bool expect_underflow) {
    rs_ws2812_status_t status;
    if (rs_ws2812_get_status(&status) != RS_OK) {
        return false;
    }
    return !status.busy && !status.reset_active && status.fifo_empty &&
           (expect_underflow ? ((status.error_status & RS_WS2812_ERROR_UNDERFLOW) != 0U)
                             : (status.error_status == 0U));
}

static bool rs_ws_pio_frame(uint32_t words, bool check_interrupt) {
    rs_ws_event = false;
    if ((rs_ws2812_init(&rs_ws_timing) != RS_OK) ||
        (rs_ws2812_irq_enable(RS_WS2812_INTR_DONE | RS_WS2812_INTR_ERROR) != RS_OK)) {
        return false;
    }
    if (check_interrupt) {
        /* This short frame fits entirely in the FIFO. Wait for a real DONE IRQ
         * before consuming its status so polling cannot acknowledge it first. */
        for (uint32_t index = 0U; index < words; ++index) {
            if (rs_ws2812_push(rs_ws_pixels[index], RS_TIMEOUT_DEFAULT) != RS_OK) {
                return false;
            }
        }
        if (rs_ws2812_start(words) != RS_OK) {
            return false;
        }
        uint32_t remaining = RS_TIMEOUT_DEFAULT;
        while (!rs_ws_event && (remaining != 0U)) {
            --remaining;
        }
        if (!rs_ws_event || (rs_ws2812_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
            return false;
        }
    } else if (rs_ws2812_write(rs_ws_pixels, words, RS_TIMEOUT_DEFAULT) != RS_OK) {
        return false;
    }
    if (rs_ws_irq_error || !rs_ws_idle(false)) {
        return false;
    }
    printf("WS2812_P3_MINI_PIO_FRAME words=%u\n", words);
    return true;
}

static bool rs_ws_pio_underflow(void) {
    if ((rs_ws2812_init(&rs_ws_timing) != RS_OK) ||
        (rs_ws2812_irq_enable(RS_WS2812_INTR_ERROR | RS_WS2812_INTR_ABORTED) != RS_OK) ||
        (rs_ws2812_push(rs_ws_pixels[0], RS_TIMEOUT_DEFAULT) != RS_OK) ||
        (rs_ws2812_start(2U) != RS_OK) || (rs_ws2812_wait(RS_TIMEOUT_DEFAULT) != RS_EIO) ||
        (rs_ws2812_abort(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        return false;
    }
    return rs_ws_idle(true);
}

static bool rs_ws_pio_abort(void) {
    if (rs_ws2812_init(&rs_ws_timing) != RS_OK) {
        return false;
    }
    for (uint32_t index = 0U; index < 16U; ++index) {
        if (rs_ws2812_push(rs_ws_pixels[index], RS_TIMEOUT_DEFAULT) != RS_OK) {
            return false;
        }
    }
    return (rs_ws2812_start(65U) == RS_OK) && (rs_ws2812_abort(RS_TIMEOUT_DEFAULT) == RS_OK) &&
           rs_ws_idle(false);
}

int main(void) {
    const rs_gpio_config_t gpio = {
        .mode = RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .input_cmos = false,
    };
    for (uint32_t index = 0U; index < 65U; ++index) {
        rs_ws_pixels[index] = (index * UINT32_C(0x010203)) & UINT32_C(0xffffff);
    }
    if ((rs_uart_init(RS_CPU_CLOCK_HZ, UART_BPS) != RS_OK) ||
        (rs_gpio_configure(2U, &gpio) != RS_OK) ||
        (rs_irq_enable_external(RS_SOC_EXT_IRQ_WS2812, rs_ws_interrupt) != RS_OK)) {
        rs_ws_finish(false, 1U);
    }
    __enable_irq();
    if (!rs_ws_pio_frame(4U, true) || !rs_ws_pio_frame(16U, false) ||
        !rs_ws_pio_frame(33U, false) || !rs_ws_pio_frame(65U, false)) {
        rs_ws_finish(false, 2U);
    }
    if (!rs_ws_pio_underflow() || !rs_ws_pio_abort()) {
        rs_ws_finish(false, 3U);
    }
    rs_ws_finish((rs_ws_irqs != 0U) && !rs_ws_irq_error, 0U);
    return 0;
}
