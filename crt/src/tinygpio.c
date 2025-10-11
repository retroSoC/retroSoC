#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
#include <tinygpio.h>

void ip_gpio_test() {
    printf("[IP] gpio test\n");

    printf("[GPIO ENB] %x\n", reg_gpio_oen);
    reg_gpio_oen = (uint32_t)0b0000;
    printf("[GPIO ENB] %x\n", reg_gpio_oen);

    printf("[GPIO DATA] %x\n", reg_gpio_data);
    reg_gpio_data = (uint32_t)0xffff;
    printf("[GPIO DATA] %x\n", reg_gpio_data);

    reg_gpio_data = (uint32_t)0x0000;
    printf("[GPIO DATA] %x\n", reg_gpio_data);

    printf("led output test\n");

    for (int i = 0; i < 50; ++i)
    {
        delay_ms(300);
        if (reg_gpio_data == 0b00)
            reg_gpio_data = (uint32_t)0b01;
        else
            reg_gpio_data = (uint32_t)0b00;
    }

    reg_gpio_data = (uint32_t)0b00;
    printf("key input test\n"); // need extn board
    reg_gpio_oen = (uint32_t)0b0010;
    printf("[GPIO ENB] %x\n", reg_gpio_oen);
    printf("[GPIO DATA] %x\n", reg_gpio_data);
    for (int i = 0; i < 60; ++i)
    {
        uint32_t led_val = 0b00;
        if (((reg_gpio_data & 0b10) >> 1) == 0b0)
        {
            delay_ms(100); // debouncing
            if (((reg_gpio_data & 0b10) >> 1) == 0b0)
            {
                printf("key detect\n");
                if (led_val == 0b00)
                {
                    led_val = 0b01;
                    reg_gpio_data = led_val;
                }
                else
                {
                    led_val = 0b00;
                    reg_gpio_data = led_val;
                }
            }
        }
    }
}