#ifndef RETROSOC_P9_STARTUP_H
#define RETROSOC_P9_STARTUP_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/rcu.h>

typedef rs_status_t (*rs_p9_uart_init_fn)(uint32_t source_clock_hz, uint32_t baud_rate);
typedef rs_status_t (*rs_p9_gpio_configure_fn)(uint32_t pin, const rs_gpio_config_t *config);

static inline bool rs_p9_console_ready(const rs_tiny_rcu_snapshot_t *snapshot,
                                       rs_p9_uart_init_fn uart_init) {
    if ((snapshot == NULL) || (uart_init == NULL) || (snapshot->pclk_hz == 0U)) {
        return false;
    }
    return uart_init(snapshot->pclk_hz, UINT32_C(921600)) == RS_OK;
}

static inline bool rs_p9_psram_pin_ready(rs_p9_gpio_configure_fn gpio_configure) {
    const rs_gpio_config_t pin = {
        .mode = RS_GPIO_MODE_ALT0,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = true,
    };
    return (gpio_configure != NULL) && (gpio_configure(29U, &pin) == RS_OK);
}

#endif
