#include <tinylib.h>

void main()
{
    reg_uart0_clkdiv = (uint32_t)(CPU_FREQ * 1000000 / UART_BPS);
    // app_system_boot();
    // while(1);
    // ip_archinfo_test();
    // i2c0_init((uint8_t)35);
    // pcf8563b_test();
    // es8388_init();
    // ip_1wire_test();
    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    // ip_i2s_test();
    ip_dma_test();
    // wav_file_decoder((uint32_t)0x51004000);
    // wav_file_decoder((uint32_t)0x54737000);

    // ip_tim_test();
    // ip_rng_test();
    
    // ip_gpio_test();
    // ip_hpuart_test();
    // ip_pwm_test();
    // ip_ps2_test();
    // ip_lcd_test();
    // tinybench(true, 0);
    // tinysh();
}
