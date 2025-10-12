#include <tinylib.h>

void main()
{
    reg_uart0_clkdiv = (uint32_t)(CPU_FREQ * 1000000 / UART_BPS);
    app_system_boot();
    // while(1);
    ip_archinfo_test();
    ip_1wire_test();
    ip_tim_test();
    ip_gpio_test();
    ip_pwm_test();
    ip_rtc_test();
    ip_wdg_test();
    ip_rng_test();
    ip_crc_test();
    // ip_hpuart_test();
    // ip_ps2_test();
    // i2c0_init((uint8_t)(35));
    ip_lcd_test();
    i2c0_init((uint8_t)(CPU_FREQ / 2 - 1));
    pcf8563b_test();
    es8388_init();
    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    ip_i2s_test();
    // ip_dma_test();
    // tinybench(true, 0);
    tinysh_init();
    tinysh_register("arch", "archinfo test", ip_archinfo_test);
    tinysh_register("1wire", "1wire test", ip_1wire_test);
    tinysh_register("tim", "timer test", ip_tim_test);
    tinysh_register("gpio", "gpio test", ip_gpio_test);
    tinysh_register("pwm", "pwm test", ip_pwm_test);
    tinysh_register("rtc", "rtc test", ip_rtc_test);
    tinysh_register("wdg", "wdg test", ip_wdg_test);
    tinysh_register("rng", "rng test", ip_rng_test);
    tinysh_register("crc", "crc test", ip_crc_test);
    tinysh_register("uart1", "uart1 test", ip_hpuart_test);
    tinysh_register("ps2", "ps2 test", ip_ps2_test);
    tinysh_register("lcd", "lcd test", ip_lcd_test);

    tinysh();
}
