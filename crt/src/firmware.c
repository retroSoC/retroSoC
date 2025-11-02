#include <tinylib.h>
#include <ff.h> // app/fat32

void main()
{
    uart0_init(CPU_FREQ, UART_BPS);
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
    tinysh_register("nor", "nor flash test", ip_norflash_test);
    tinysh_register("uart1", "uart1 test", ip_hpuart_test);
    tinysh_register("ps2", "ps2 test", ip_ps2_test);
    tinysh_register("lcd", "lcd test", ip_lcd_test);
    tinysh_register("i2s", "i2s test", ip_i2s_test);
    tinysh_register("pcf", "pcf8563b test", pcf8563b_test);
    while(1);

    FATFS fs;
    // FIL fnew;
    FRESULT ff_res;
    // BYTE buffer[1024]= {0};

    ff_res = f_mount(&fs, "0:", 1);
    if (ff_res == FR_NO_FILESYSTEM) {
        printf("[fatfs] no filesystem");
    } else if (ff_res != FR_OK) {
        printf("[fatfs] filesystem mount fail\n");
    } else {
        printf("[fatfs] mount done\n");
        FILINFO ff_info;
        ff_res = f_stat("silkroad.wav", &ff_info);
        if(ff_res == FR_OK) {
        printf("Size: %lu\n", ff_info.fsize);
        printf("Timestamp: %u-%02u-%02u, %02u:%02u\n",
               (ff_info.fdate >> 9) + 1980, ff_info.fdate >> 5 & 15, ff_info.fdate & 31,
               ff_info.ftime >> 11, ff_info.ftime >> 5 & 63);
        printf("Attributes: %c%c%c%c%c\n",
               (ff_info.fattrib & AM_DIR) ? 'D' : '-',
               (ff_info.fattrib & AM_RDO) ? 'R' : '-',
               (ff_info.fattrib & AM_HID) ? 'H' : '-',
               (ff_info.fattrib & AM_SYS) ? 'S' : '-',
               (ff_info.fattrib & AM_ARC) ? 'A' : '-');
        }

        f_mount(NULL, "0:", 1);
    }


    // ip_norflash_test();
    while(1);
    ip_lcd_test();
    video_show(0x679D1000);
    while(1);
    i2c0_init((uint8_t)(CPU_FREQ / 2 - 1));
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
    // ip_norflash_test();
    // ip_hpuart_test();
    // ip_ps2_test();
    ip_lcd_test();
    pcf8563b_test();
    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    // ip_i2s_test();
    // ip_dma_test();
    // tinybench(true, 0);
    tinysh_launch();
}
