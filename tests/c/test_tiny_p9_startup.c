#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/rcu.h>

#include "app/apps/ci_smoke/p9_startup.h"

static uint32_t calls;
static uint32_t source_clock;
static uint32_t baud_rate;
static rs_status_t callback_status;
static uint32_t gpio_calls;
static uint32_t gpio_pin;
static rs_gpio_config_t gpio_config;

static rs_status_t record_uart_init(uint32_t source_clock_hz, uint32_t requested_baud_rate) {
    calls++;
    source_clock = source_clock_hz;
    baud_rate = requested_baud_rate;
    return callback_status;
}

static rs_status_t record_gpio_configure(uint32_t pin, const rs_gpio_config_t *config) {
    gpio_calls++;
    gpio_pin = pin;
    gpio_config = *config;
    return callback_status;
}

int main(void) {
    rs_tiny_rcu_snapshot_t snapshot = {0};

    snapshot.pclk_hz = UINT32_C(24000000);
    callback_status = RS_OK;
    if (!rs_p9_console_ready(&snapshot, record_uart_init) || calls != 1U ||
        source_clock != UINT32_C(24000000) || baud_rate != UINT32_C(921600)) {
        return 1;
    }
    callback_status = RS_EIO;
    if (rs_p9_console_ready(&snapshot, record_uart_init) || calls != 2U) {
        return 2;
    }
    snapshot.pclk_hz = 0U;
    if (rs_p9_console_ready(&snapshot, record_uart_init) || calls != 2U) {
        return 3;
    }
    if ((rs_p9_console_ready(NULL, record_uart_init) != false) ||
        (rs_p9_console_ready(&snapshot, NULL) != false) || (calls != 2U)) {
        return 4;
    }
    callback_status = RS_OK;
    if (!rs_p9_psram_pin_ready(record_gpio_configure) || gpio_calls != 1U || gpio_pin != 29U ||
        gpio_config.mode != RS_GPIO_MODE_ALT0 || !gpio_config.output_high) {
        return 5;
    }
    callback_status = RS_EIO;
    if (rs_p9_psram_pin_ready(record_gpio_configure) || gpio_calls != 2U) {
        return 6;
    }
    if (rs_p9_psram_pin_ready(NULL) || gpio_calls != 2U) {
        return 7;
    }
    return 0;
}
