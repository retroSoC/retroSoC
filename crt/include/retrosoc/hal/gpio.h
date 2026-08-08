#ifndef RETROSOC_HAL_GPIO_H
#define RETROSOC_HAL_GPIO_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_GPIO_PIN_COUNT          32U
#define RS_GPIO_IRQ                18U

#define RS_GPIO_CAP_OPEN_DRAIN     (UINT32_C(1) << 16U)
#define RS_GPIO_CAP_FILTER         (UINT32_C(1) << 17U)
#define RS_GPIO_CAP_USER_HANDOFF   (UINT32_C(1) << 18U)
#define RS_GPIO_CAP_CONFIG_LOCK    (UINT32_C(1) << 19U)
#define RS_GPIO_CAP_ATOMIC_OUT     (UINT32_C(1) << 20U)
#define RS_GPIO_CAP_ATOMIC_OE      (UINT32_C(1) << 21U)
#define RS_GPIO_CAP_BOTH_EDGE_IRQ  (UINT32_C(1) << 22U)

#define RS_GPIO_PAD_CAP_INPUT_CMOS (UINT32_C(1) << 0U)
#define RS_GPIO_PAD_CAP_PULL_UP    (UINT32_C(1) << 1U)
#define RS_GPIO_PAD_CAP_PULL_DOWN  (UINT32_C(1) << 2U)

typedef enum {
    RS_GPIO_MODE_INPUT = 0,
    RS_GPIO_MODE_OUTPUT = 1,
    RS_GPIO_MODE_ALT0 = 2,
    RS_GPIO_MODE_ALT1 = 3,
    RS_GPIO_MODE_USER_IP = 4,
} rs_gpio_mode_t;

typedef enum {
    RS_GPIO_PULL_NONE = 0,
    RS_GPIO_PULL_UP = 1,
    RS_GPIO_PULL_DOWN = 2,
} rs_gpio_pull_t;

typedef enum {
    RS_GPIO_TRIGGER_NONE = 0,
    RS_GPIO_TRIGGER_RISING = 1,
    RS_GPIO_TRIGGER_FALLING = 2,
    RS_GPIO_TRIGGER_BOTH = 3,
    RS_GPIO_TRIGGER_HIGH = 4,
    RS_GPIO_TRIGGER_LOW = 5,
} rs_gpio_trigger_t;

typedef struct {
    rs_gpio_mode_t mode;
    rs_gpio_pull_t pull;
    rs_gpio_trigger_t trigger;
    bool output_high;
    bool open_drain;
    bool input_cmos;
    bool filter_enable;
    bool interrupt_enable;
} rs_gpio_config_t;

typedef struct {
    uint16_t divider;
    uint8_t stable_samples;
} rs_gpio_filter_timing_t;

typedef struct {
    uint32_t version;
    uint32_t features;
    uint32_t pad_features;
} rs_gpio_capabilities_t;

rs_status_t rs_gpio_filter_timing_from_us(uint32_t source_clock_hz, uint32_t sample_period_us,
                                          uint8_t stable_samples, rs_gpio_filter_timing_t *timing);
rs_status_t rs_gpio_get_capabilities(rs_gpio_capabilities_t *capabilities);
rs_status_t rs_gpio_configure(uint32_t pin, const rs_gpio_config_t *config);
rs_status_t rs_gpio_read(uint32_t pin, bool *high);
rs_status_t rs_gpio_write(uint32_t pin, bool high);
rs_status_t rs_gpio_toggle(uint32_t pin);
rs_status_t rs_gpio_port_read(uint32_t *value);
rs_status_t rs_gpio_port_set(uint32_t mask);
rs_status_t rs_gpio_port_clear(uint32_t mask);
rs_status_t rs_gpio_port_toggle(uint32_t mask);
rs_status_t rs_gpio_interrupt_state(uint32_t *state);
rs_status_t rs_gpio_interrupt_enable(uint32_t mask, bool enable);
rs_status_t rs_gpio_interrupt_clear(uint32_t mask);
rs_status_t rs_gpio_interrupt_test(uint32_t mask);
rs_status_t rs_gpio_filter_configure(uint32_t enable_mask, const rs_gpio_filter_timing_t *timing);
rs_status_t rs_gpio_user_access_set(uint32_t mask);
rs_status_t rs_gpio_user_ip_select(uint32_t mask, bool enable);
rs_status_t rs_gpio_user_ip_lock(uint32_t mask);
rs_status_t rs_gpio_configuration_lock(uint32_t mask);
void rs_gpio_shell_test(int argc, char **argv);

#endif
