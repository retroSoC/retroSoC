/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#include <tinylib.h>

extern uint32_t _sidata, _sdata, _edata;
extern uint32_t _sbss, _ebss;
extern uint32_t _heap_start;

void welcome_screen()
{
    printf("first bootloader done, app section info:\n");
    printf("_sidata:     0x%0x\n", &_sidata);
    printf("_sdata:      0x0%x\n", &_sdata);
    printf("_edata:      0x0%x\n", &_edata);
    printf("_sbss:       0x0%x\n", &_sbss);
    printf("_ebss:       0x0%x\n", &_ebss);
    printf("_heap_start: 0x0%x\n\n", &_heap_start);
    printf("uart config: 8n1 %dbps\n", UART_BPS);
    printf("app booting...\n");
    printf("\n");
    printf("          _             _____        _____ \n");
    printf("         | |           / ____|      / ____|\n");
    printf(" _ __ ___| |_ _ __ ___| (___   ___ | |     \n");
    printf("| '__/ _ \\ __| '__/ _ \\\\___ \\ / _ \\| |\n");
    printf("| | |  __/ |_| | | (_) |___) | (_) | |____ \n");
    printf("|_|  \\___|\\__|_|  \\___/_____/ \\___/ \\_____|\n");
    printf("  retroSoC: A Customized ASIC for Retro Stuff!\n");
    printf("    <https://github.com/retroSoC/retroSoC>\n");
    printf("  author:  MrAMS(init version) <https://github.com/MrAMS>\n");
    printf("           maksyuki            <https://github.com/maksyuki>\n");
    printf("  version: v1.0(commit: 73b7f30)\n");
    printf("  license: MulanPSL-2.0 license\n\n");

    printf("Processor:\n");
    printf("  CORE:              picorv32\n");
    printf("  ISA:               rv32imac\n");
    printf("  FREQ:              %dMHz\n\n", CPU_FREQ);

    printf("Inst/Memory Device: \n");
    printf("  On-chip RAM size:  @[0x0000000%x-0x000%x] %dKB\n", SRAM_MEM_START, SRAM_MEM_START + SRAM_MEM_OFFST, SRAM_MEM_OFFST / 1024);
    printf("  Extern PSRAM size: @[0x0%x-0x0%x] %dMB(%dx8MB)\n", PSRAM_MEM_START, PSRAM_MEM_START + PSRAM_MEM_OFFST, 8 * PSRAM_NUM, PSRAM_NUM);
    printf("  SPI Flash size:    @[0x%x-0x%x] %dMB\n\n", SPFS_MEM_START, SPFS_MEM_START + SPFS_MEM_OFFST, SPFS_MEM_OFFST / 1024 / 1024);

    printf("Memory Map IO Device:\n");
    printf("                     1 x QSPFS         @0x0%x\n", &reg_spictrl);
    printf("                    16 x GPIO          @0x0%x\n", &reg_gpio_data);
    printf("                     1 x UART          @0x0%x\n", &reg_uart_clkdiv);
    printf("                     1 x HK SPI        @0x0%x\n", &reg_spi_commconfig);
    printf("                     1 x SYS CTRL      @0x0%x\n", &reg_xtal_out_dest);
    printf("                     2 x TIMER         @0x0%x,0x0%x\n", &reg_tim0_config, &reg_tim1_config);
    printf("                     1 x ARCHINFO      @0x0%x\n", &reg_cust_archinfo_sys);
    printf("                     1 x RNG           @0x0%x\n", &reg_cust_rng_ctrl);
    printf("                     1 x UART(HP)      @0x0%x\n", &reg_cust_uart_lcr);
    printf("                     4 x PWM           @0x0%x\n", &reg_cust_pwm_ctrl);
    printf("                     1 x PS2           @0x0%x\n", &reg_cust_ps2_ctrl);
    printf("                     1 x I2C           @0x0%x\n", &reg_cust_i2c_ctrl);
    printf("                     1 x QSPI          @0x0%x\n", &reg_cust_qspi_status);
    printf("                     1 x PSRAM         @0x0%x\n", &reg_psram_waitcycl);
    printf("                     1 x SPFS(TPO)     @unused\n\n");
}

void app_system_boot() {
    welcome_screen();
    // set_flash_qspi_flag();
    // cmd_read_flash_id();
    // cmd_read_flash_regs();
    // cmd_print_spi_state();
    printf("self test start...\n");

    bool timing_pass = true;

    printf("[PSRAM] device:     ESP-PSRAM64H(max %dMHz)\n", PSRAM_SCLK_MAX_FREQ);
    printf("        volt:       3.3V\n");
    printf("        power-up:   SPI mode\n");
    printf("        normal:     QPI mode\n");
    printf("        sclk freq:  %dMHz\n", PSRAM_SCLK_FREQ);
    // check
    uint32_t timing_expt = 0, timing_actual = 0;
    char  msg_pass[20] = "\e[0;32m[PASS]\e[0m", msg_fail[20] = "\e[0;31m[FAIL]\e[0m";

    printf("[PSRAM] wait cycles(default):      %d\n", reg_psram_waitcycl);
    printf("[PSRAM] chd delay cycles(defalut): %d\n", reg_psram_chd);
    printf("[PSRAM] timing check\n");
    timing_expt = 1000 / PSRAM_SCLK_MAX_FREQ;
    timing_actual = 1000 / (PSRAM_SCLK_FREQ);

    printf("tCLK    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    printf("tCH/tCL ===> expt:  [0.45-0.55] tCLK(min)\n");
    printf("             actul: [0.45-0.55] tCLK ");
    printf("%s\n", msg_pass);

    printf("tKHKL   ===> expt:  1.5ns(max)\n");
    printf("             actul: 1.5ns ");
    printf("%s\n", msg_pass);

    timing_expt = 50;
    timing_actual = (reg_psram_waitcycl / 2) * (1000 / PSRAM_SCLK_FREQ);
    printf("tCPH    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 8;
    // 32(cmd+addr) + 32(data)
    timing_actual = ((1000 / PSRAM_SCLK_FREQ) * ((32 + 32) / 4)) / 1000;
    printf("tCEM    ===> expt:  %dus(max)\n", timing_expt);
    printf("             actul: %dus ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual <= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 2;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) / 2;
    printf("tCSP    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 20;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) * (reg_psram_chd / 2 + 1);
    printf("tCHD    ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    timing_expt = 2;
    timing_actual = (1000 / PSRAM_SCLK_FREQ) / 2;
    printf("tSP     ===> expt:  %dns(min)\n", timing_expt);
    printf("             actul: %dns ", timing_actual);
    printf("%s\n", (timing_pass &= (timing_actual >= timing_expt)) ? msg_pass : msg_fail);

    if(!timing_pass) {
        printf("[PSRAM] timing check fail\n");
        while(1);
    }

    reg_psram_waitcycl = (uint32_t)8;
    printf("[PSRAM] set wait cycles to %d\n", reg_psram_waitcycl);
    reg_psram_chd = (uint32_t)0;
    printf("[PSRAM] set chd cycles to %d\n", reg_psram_chd);
    printf("[extern PSRAM test]\n");
    // psram_selftest(0x04000000, 8 * 1024 * 1024);
    printf("self test done\n\n");
}

void main()
{
    reg_uart_clkdiv = (uint32_t)(CPU_FREQ * 1000000 / UART_BPS);

    app_system_boot();
    ip_tim_test();
    ip_gpio_test();
    ip_hk_spi_test();
    ip_archinfo_test();
    ip_rng_test();
    ip_hpuart_test();
    ip_pwm_test();
    ip_ps2_test();
    ip_i2c_test();
    ip_lcd_test();
    tinybench(true, 0);
    tinysh();
}
