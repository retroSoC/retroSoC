#include <libdef.h>

void main() {
    uart0_init(CPU_FREQ, UART_BPS);
    i2c0_init((uint8_t)(CPU_FREQ / 2 - 1));
    qspi_dev_init();
    lcd_init();

    tinysh_init();
    tinysh_register("boot", "system boot", (uint8_t)1, app_system_boot);
    tinysh_register("arch", "archinfo test", (uint8_t)1, ip_archinfo_test);
    tinysh_register("1wire", "1wire test", (uint8_t)1, ip_1wire_test);
    tinysh_register("tim", "timer test", (uint8_t)1, ip_tim_test);
    tinysh_register("gpio", "gpio test", (uint8_t)1, ip_gpio_test);
    tinysh_register("pwm", "pwm test", (uint8_t)1, ip_pwm_test);
    tinysh_register("rtc", "rtc test", (uint8_t)1, ip_rtc_test);
    tinysh_register("wdg", "wdg test", (uint8_t)1, ip_wdg_test);
    tinysh_register("rng", "rng test", (uint8_t)1, ip_rng_test);
    tinysh_register("crc", "crc test", (uint8_t)1, ip_crc_test);
    tinysh_register("ps2", "ps2 test", (uint8_t)0, ip_ps2_test);
    tinysh_register("lcd", "lcd test", (uint8_t)1, ip_lcd_test);
    tinysh_register("i2s", "i2s test", (uint8_t)0, ip_i2s_test);
    tinysh_register("nor", "nor flash test", (uint8_t)0, ip_norflash_test);
    tinysh_register("uart1", "uart1 test", (uint8_t)0, ip_hpuart_test);
    tinysh_register("pcf", "pcf8563b test", (uint8_t)1, pcf8563b_test);
    tinysh_register("donut", "dount test", (uint8_t)0, donut_test);
    tinysh_batch_run();
    tinysh_launch();
    // ip_norflash_test();
    // ip_lcd_test(0, NULL);
    video_show(0x679D1000);

    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    // ip_dma_test(0, NULL);
    // tinybench(true, 0);
}
