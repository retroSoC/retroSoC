#include <tinylib.h>

void main()
{
    uart0_init(CPU_FREQ, UART_BPS);

    // reg_qspi0_mode = (uint32_t)0;
    // reg_qspi0_clkdiv = (uint32_t)0;
    // reg_qspi0_nss = (uint32_t)0b0001;
    // reg_qspi0_txupbound = (uint32_t)250;
    // reg_qspi0_txlowbound = (uint32_t)140;
    // reg_qspi0_cmdtyp = (uint32_t)1;
    // reg_qspi0_cmdlen = (uint32_t)1;
    // reg_qspi0_cmddat = (uint32_t)0xA4000000;
    // reg_qspi0_adrtyp = (uint32_t)1;
    // reg_qspi0_adrlen = (uint32_t)3;
    // reg_qspi0_adrdat = (uint32_t)0x12345600;
    // reg_qspi0_dumtyp = (uint32_t)0;
    // reg_qspi0_dumlen = (uint32_t)0;
    // reg_qspi0_dumdat = (uint32_t)0;
    // reg_qspi0_dattyp = (uint32_t)1;
    // reg_qspi0_datlen = (uint32_t)2;
    // reg_qspi0_hlvlen = (uint32_t)3;
    // // wr data
    // reg_qspi0_txdata = (uint32_t)0x23456789;
    // reg_qspi0_txdata = (uint32_t)0x67674545;
    // reg_qspi0_start = (uint32_t)1;
    // while((reg_qspi0_status & (uint32_t)1) == 0);

    // reg_qspi0_txdata = (uint32_t)0x57572323;
    // reg_qspi0_txdata = (uint32_t)0x87654321;
    // reg_qspi0_txdata = (uint32_t)0x12345678;
    // reg_qspi0_datlen = (uint32_t)3;
    // reg_qspi0_start = (uint32_t)1;
    // while((reg_qspi0_status & (uint32_t)1) == 0);

    // // printf("dma test\n");
    // reg_qspi0_mode = (uint32_t)1;
    // reg_qspi0_clkdiv = (uint32_t)0;
    // reg_qspi0_nss = (uint32_t)0b0001;
    // reg_qspi0_txupbound = (uint32_t)250;
    // reg_qspi0_txlowbound = (uint32_t)140;
    // reg_qspi0_cmdtyp = (uint32_t)0;
    // reg_qspi0_cmdlen = (uint32_t)1;
    // reg_qspi0_cmddat = (uint32_t)0xA4000000;
    // reg_qspi0_adrtyp = (uint32_t)0;
    // reg_qspi0_adrlen = (uint32_t)3;
    // reg_qspi0_adrdat = (uint32_t)0x12345600;
    // reg_qspi0_dumtyp = (uint32_t)0;
    // reg_qspi0_dumlen = (uint32_t)0;
    // reg_qspi0_dumdat = (uint32_t)0;
    // reg_qspi0_dattyp = (uint32_t)1;
    // reg_qspi0_datlen = (uint32_t)1;
    // reg_qspi0_hlvlen = (uint32_t)2;
    // // dma config
    // reg_dma_mode = (uint32_t)3; // qspi tx fifo
    // reg_dma_srcaddr = (uint32_t)0x40000000;
    // reg_dma_srcincr = (uint32_t)1;
    // reg_dma_dstaddr = (uint32_t)(&reg_qspi0_txdata);
    // reg_dma_dstincr = (uint32_t)0;
    // reg_dma_xferlen = (uint32_t)32;
    // reg_dma_start = (uint32_t)1;
    // while(reg_dma_status == (uint32_t)0);
    // printf("dma tx done\n");
    ip_lcd_test();
    while(1);
    i2c0_init((uint8_t)(CPU_FREQ / 2 - 1));
    app_system_boot();
    ip_archinfo_test();
    ip_1wire_test();
    ip_tim_test();
    ip_gpio_test();
    ip_pwm_test();
    ip_rtc_test();
    ip_wdg_test();
    ip_rng_test();
    ip_crc_test();
    ip_norflash_test();
    // ip_hpuart_test();
    // ip_ps2_test();
    ip_lcd_test();
    pcf8563b_test();
    // ip_spisd_read((uint32_t)0x51004000, (uint32_t)44);
    // ip_spisd_test();
    // ip_i2s_test();
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
    tinysh_register("nor", "nor flash test", ip_norflash_test);
    tinysh_register("uart1", "uart1 test", ip_hpuart_test);
    tinysh_register("ps2", "ps2 test", ip_ps2_test);
    tinysh_register("lcd", "lcd test", ip_lcd_test);
    tinysh_register("i2s", "i2s test", ip_i2s_test);
    tinysh_register("pcf", "pcf8563b test", pcf8563b_test);
    tinysh_launch();
}
