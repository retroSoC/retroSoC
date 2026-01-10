#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
#include <tinygpio.h>

void ip_gpio_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("[NATV IP] gpio test\n");

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
        delay_ms(300);
        if (reg_gpio_do == 0b00) reg_gpio_do = (uint32_t)0b01;
        else reg_gpio_do = (uint32_t)0b00;
    }

    reg_gpio_do = (uint32_t)0b00;
    printf("key input test\n"); // need extn board
    reg_gpio_oe = (uint32_t)0b1101;
    printf("[GPIO OE] %x\n", reg_gpio_oe);
    printf("[GPIO DATA] %x\n", reg_gpio_do);
    for (int i = 0; i < 60; ++i) {
        uint32_t led_val = 0b00;
        if (((reg_gpio_do & 0b10) >> 1) == 0b0) {
            delay_ms(100); // debouncing
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