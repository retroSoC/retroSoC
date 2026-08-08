#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/gpio.h>

void ip_gpio_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("[RIB IP] gpio test\n");

    printf("[GPIO OE] %x\n", reg_gpio_oe);
    reg_gpio_oe = (uint32_t)0b1111;
    printf("[GPIO OE] %x\n", reg_gpio_oe);

    printf("[GPIO DATA] %x\n", reg_gpio_do);
    reg_gpio_do = (uint32_t)0xffff;
    printf("[GPIO DATA] %x\n", reg_gpio_do);

    reg_gpio_do = (uint32_t)0x0000;
    printf("[GPIO DATA] %x\n", reg_gpio_do);

    printf("led output test\n");
    for (int i = 0; i < 50; ++i) {
        if (rs_timer_delay_ms(RS_TIMER_0, 300U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
            printf("timer delay failed\n");
            return;
        }
        if (reg_gpio_do == 0b00)
            reg_gpio_do = (uint32_t)0b01;
        else
            reg_gpio_do = (uint32_t)0b00;
    }

    reg_gpio_do = (uint32_t)0b00;
    printf("key input test\n"); // need extn board
    reg_gpio_oe = (uint32_t)0b1101;
    printf("[GPIO OE] %x\n", reg_gpio_oe);
    printf("[GPIO DATA] %x\n", reg_gpio_do);
    return;
    for (int i = 0; i < 60; ++i) {
        uint32_t led_val = 0b00;
        if (((reg_gpio_do & 0b10) >> 1) == 0b0) {
            if (rs_timer_delay_ms(RS_TIMER_0, 100U, RS_TIMER_DELAY_TIMEOUT) != RS_OK) {
                printf("timer delay failed\n");
                return;
            }
            if (((reg_gpio_do & 0b10) >> 1) == 0b0) {
                printf("key detect\n");
                if (led_val == 0b00) {
                    led_val = 0b01;
                    reg_gpio_do = led_val;
                } else {
                    led_val = 0b00;
                    reg_gpio_do = led_val;
                }
            }
        }
    }
}
