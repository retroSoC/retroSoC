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

#define RAM_TOTAL 0x10000 // 64 KB
#define PSRAM_NUM 4
#define CPU_FREQ 50     // unit: MHz
#define UART_BPS 115200 // unit: bps

uint32_t xorshift32(uint32_t *state)
{
    /* Algorithm "xor" from p. 4 of Marsaglia, "Xorshift RNGs" */
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;

    return x;
}

char getchar_prompt(char *prompt)
{
    int32_t c = -1;
    uint32_t cycles_begin, cycles_now, cycles;
    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_begin));

    if (prompt)
        printf(prompt);

    while (c == -1)
    {
        __asm__ volatile("rdcycle %0"
                         : "=r"(cycles_now));
        cycles = cycles_now - cycles_begin;
        if (cycles > 12000000)
        {
            if (prompt)
                printf(prompt);
            cycles_begin = cycles_now;
        }
        c = reg_uart_data;
    }

    return c;
}

void cmd_memtest(uint32_t addr, uint32_t range)
{
    int cyc_count = 5;
    int stride = 256;
    uint32_t state;

    volatile uint32_t *base_word = (uint32_t *)addr;
    volatile uint8_t *base_byte = (uint8_t *)addr;

    printf("[memtest] addr: 0x%x range: %x\n", addr, range);
    // walk in stride increments, word access
    for (int i = 1; i <= cyc_count; i++)
    {
        state = i;
        for (int word = 0; word < range / sizeof(int); word += stride)
        {
            *(base_word + word) = xorshift32(&state);
        }

        state = i;
        for (int word = 0; word < range / sizeof(int); word += stride)
        {
            if (*(base_word + word) != xorshift32(&state))
            {
                printf("***FAILED BYTE*** at %x\n", 4 * word);
                return;
            }
        }
        printf(".");
    }
    printf("stride test done\n");
    // Byte access

    for (int byte = 0; byte < range; byte++)
    {
        *(base_byte + byte) = (uint8_t)byte;
    }

    printf("byte write done\n");
    for (int byte = 0; byte < range; byte++)
    {
        if (*(base_byte + byte) != (uint8_t)byte)
        {
            printf("***FAILED BYTE*** at %x\n", byte);
            return;
        }
    }

    printf("\nmemtest passed\n");
}

uint32_t cmd_benchmark(bool verbose, uint32_t *instns_p)
{
    printf("benckmark test\n");
    uint8_t data[256];
    uint32_t *words = (void *)data;

    uint32_t x32 = 314159265;

    uint32_t cycles_begin, cycles_end;
    uint32_t instns_begin, instns_end;
    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_begin));
    __asm__ volatile("rdinstret %0"
                     : "=r"(instns_begin));

    printf("cycle and instns read done!\n");

    for (int i = 0; i < 20; i++)
    {
        for (int k = 0; k < 256; k++)
        {
            x32 ^= x32 << 13;
            x32 ^= x32 >> 17;
            x32 ^= x32 << 5;
            data[k] = x32;
        }

        for (int k = 0, p = 0; k < 256; k++)
        {
            if (data[k])
                data[p++] = k;
        }

        for (int k = 0, p = 0; k < 64; k++)
        {
            x32 = x32 ^ words[k];
        }
    }

    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_end));
    __asm__ volatile("rdinstret %0"
                     : "=r"(instns_end));

    if (verbose)
    {
        printf("Cycles: 0x%x\n", cycles_end - cycles_begin);
        printf("Instns: 0x%x\n", instns_end - instns_begin);
        printf("Chksum: 0x%x\n", x32);
    }

    if (instns_p)
        *instns_p = instns_end - instns_begin;

    printf("benckmark done\n");
    return cycles_end - cycles_begin;
}

void cmd_benchmark_all()
{
    uint32_t instns = 0;

    printf("default   ");
    set_flash_mode_spi();
    printf("%x\n", cmd_benchmark(false, &instns));

    printf("dual      ");
    set_flash_mode_dual();
    printf("%x\n", cmd_benchmark(false, &instns));

    // printf("dual-crm  ");
    // enable_flash_crm();
    // print_hex(cmd_benchmark(false, &instns), 8);
    // printf("\n");

    printf("quad      ");
    set_flash_mode_quad();
    printf("%x\n", cmd_benchmark(false, &instns));

    printf("quad-crm  ");
    enable_flash_crm();
    printf("%x\n", cmd_benchmark(false, &instns));

    printf("qddr      ");
    set_flash_mode_qddr();
    printf("%x\n", cmd_benchmark(false, &instns));

    printf("qddr-crm  ");
    enable_flash_crm();
    printf("%x\n", cmd_benchmark(false, &instns));
}

void cmd_echo()
{
    printf("Return to menu by sending '!'\n\n");
    char c;
    while ((c = getchar_prompt(0)) != '!')
        putch(c);
}

void delay_ms(uint32_t val)
{
    // 1ms = 50MHz  /
    reg_timer0_config = (uint32_t)0x0000;
    reg_timer0_data = (uint32_t)(CPU_FREQ * 1000 - 1);
    for (int i = 1; i <= val; ++i)
    {
        reg_timer0_config = (uint32_t)0x0001; // irq disable, count down, continuous mode, timer enable
        while (reg_timer0_data == 0)
            ;
        reg_timer0_config = (uint32_t)0x0000;
    }
}

void ip_gpio_test()
{
    printf("[IP] gpio test\n");

    printf("[GPIO ENB] %x\n", reg_gpio_enb);
    reg_gpio_enb = (uint32_t)0b0000;
    printf("[GPIO ENB] %x\n", reg_gpio_enb);

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
    reg_gpio_enb = (uint32_t)0b0010;
    printf("[GPIO ENB] %x\n", reg_gpio_enb);
    printf("[GPIO DATA] %x\n", reg_gpio_data);
    for(int i = 0; i < 60; ++i)
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

void ip_hk_spi_test()
{
    printf("[IP] housekeeping spi test\n");
    printf("[HK CONFIG]   %x\n", reg_spi_commconfig);
    printf("[HK ENB]      %x\n", reg_spi_enables);
    printf("[HK PLL]      %x\n", reg_spi_pll_config);
    printf("[HK MFGR ID]  %x\n", reg_spi_mfgr_id);
    printf("[HK PROD ID]  %x\n", reg_spi_prod_id);
    printf("[HK MASK REV] %x\n", reg_spi_mask_rev);
    printf("[HK PLL BYP]  %x\n", reg_spi_pll_bypass);
}

void i2c_init(unsigned int pre)
{
    reg_i2c_control = (uint16_t)(I2C_CTRL_EN | I2C_CTRL_IEN);
    reg_i2c_prescale = (uint16_t)pre;
}

int i2c_send(unsigned char saddr, unsigned char sdata)
{
    int volatile y;
    reg_i2c_data = saddr;
    reg_i2c_command = I2C_CMD_STA | I2C_CMD_WR;

    while ((reg_i2c_status & I2C_STAT_TIP) != 0)
        ;

    if ((reg_i2c_status & I2C_STAT_RXACK) == 1)
    {
        reg_i2c_command = I2C_CMD_STO;
        return 0;
    }

    reg_i2c_data = sdata;
    reg_i2c_command = I2C_CMD_WR;

    while (reg_i2c_status & I2C_STAT_TIP)
        ;
    reg_i2c_command = I2C_CMD_STO;

    if ((reg_i2c_status & I2C_STAT_RXACK) == 1)
        return 0;
    else
        return 1;
}

void ip_i2c_test()
{
    printf("[IP] i2c test\n");
    reg_i2c_config = 0;
    reg_i2c_data = 0;
    i2c_init(5);
    // Send command 6, data byte 0xfa
    i2c_send(0x6, 0xfa);
}

void ip_counter_timer_test()
{
    printf("[IP] counter timer test\n");
    printf("[TIM0 VALUE]  %x\n", reg_timer0_value);
    printf("[TIM0 CONFIG] %x\n", reg_timer0_config);
    printf("[TIM1 VALUE]  %x\n", reg_timer1_value);
    printf("[TIM1 CONFIG] %x\n", reg_timer1_config);

    reg_timer0_value = (uint32_t)0xffffffff;
    reg_timer0_config = (uint32_t)0x0001; // irq disable, count down, continuous mode, timer enable

    reg_timer1_value = (uint32_t)0x00ffffff;
    reg_timer1_config = (uint32_t)0x0101; // irq disable, count up, continuous mode, timer enable

    printf("[TIM0 VALUE]  %x\n", reg_timer0_value);
    printf("[TIM0 CONFIG] %x\n", reg_timer0_config);
    printf("[TIM1 VALUE]  %x\n", reg_timer1_value);
    printf("[TIM1 CONFIG] %x\n", reg_timer1_config);

    for (int i = 0; i < 10; ++i)
    {
        printf("[TIM0 DATA] %x\n", reg_timer0_data);
        printf("[TIM1 DATA] %x\n", reg_timer1_data);
    }
}

void cust_ip_archinfo_test()
{
    printf("[CUST IP] archinfo test\n");
    printf("[ARCHINFO SYS] %x\n", reg_cust_archinfo_sys);
    printf("[ARCHINFO IDL] %x\n", reg_cust_archinfo_idl);
    printf("[ARCHINFO IDH] %x\n", reg_cust_archinfo_idh);
}

void cust_ip_rng_test()
{
    printf("[CUST IP] rng test\n");

    reg_cust_rng_ctrl = (uint32_t)1;      // en the core
    reg_cust_rng_seed = (uint32_t)0xFE1C; // set the init seed
    printf("[RNG SEED] %x\n", reg_cust_rng_seed);

    for (int i = 0; i < 5; ++i)
    {
        printf("[RNG VAL] %x\n", reg_cust_rng_val);
    }

    printf("[RNG] reset the seed\n");
    reg_cust_rng_seed = (uint32_t)0;
    for (int i = 0; i < 5; ++i)
    {
        printf("[RNG VAL] %x\n", reg_cust_rng_val);
    }
}

void cust_ip_uart_test()
{
    printf("[CUST IP] uart test\n");

    printf("[UART DIV] %x\n", reg_cust_uart_div);
    printf("[UART LCR] %x\n", reg_cust_uart_lcr);

    reg_cust_uart_div = (uint32_t)434;    // 50x10^6 / 115200
    reg_cust_uart_fcr = (uint32_t)0b1111; // clear tx and rx fifo
    reg_cust_uart_fcr = (uint32_t)0b1100;
    reg_cust_uart_lcr = (uint32_t)0b00011111; // 8N1, en all irq

    printf("[UART DIV] %x\n", reg_cust_uart_div);
    printf("[UART LCR] %x\n", reg_cust_uart_lcr);

    printf("uart tx test\n");
    uint32_t val = (uint32_t)0x41;
    for (int i = 0; i < 30; ++i)
    {
        while (((reg_cust_uart_lsr & 0x100) >> 8) == 1)
            ;
        reg_cust_uart_trx = (uint32_t)(val + i);
    }

    printf("uart tx test done\n");
    printf("uart rx test\n");
    uint32_t rx_val = 0;
    for (int i = 0; i < 36; ++i)
    {
        while (((reg_cust_uart_lsr & 0x080) >> 7) == 1)
            ;
        rx_val = reg_cust_uart_trx;
        printf("[UART TRX] %x\n", rx_val);
    }

    printf("uart rx test done\n");
    printf("uart done\n");
}

void cust_ip_ps2_test()
{
    printf("[CUST IP] ps2 test\n");

    reg_cust_ps2_ctrl = (uint32_t)0b11;
    uint32_t kdb_code, i = 0;
    for (int i = 0; i < 36;)
    {
        kdb_code = reg_cust_ps2_data;
        if (kdb_code != 0)
        {
            ++i;
            printf("[PS2 DAT] %x\n", kdb_code);
        }
    }
}

void welcome_screen()
{
    printf("first bootloader done\n");
    printf("uart config: 8n1 %dbps\n", UART_BPS);
    printf("app booting...\n");
    printf("\n");
    printf("           _             _____        _____ \n");
    printf("          | |           / ____|      / ____|\n");
    printf("  _ __ ___| |_ _ __ ___| (___   ___ | |     \n");
    printf(" | '__/ _ \\ __| '__/ _ \\\\___ \\ / _ \\| |\n");
    printf(" | | |  __/ |_| | | (_) |___) | (_) | |____ \n");
    printf(" |_|  \\___|\\__|_|  \\___/_____/ \\___/ \\_____|\n");
    printf("   retroSoC: A Customized ASIC for Retro Stuff!\n");
    printf("     <https://github.com/retroSoC/retroSoC>\n");
    printf("  author:  MrAMS(init version) <https://github.com/MrAMS>\n");
    printf("           maksyuki            <https://github.com/maksyuki>\n");
    printf("  License: MulanPSL-2.0 license\n");
    printf("  version: v1.0(commit: 73b7f30)\n");
    printf("\n");

    printf("Processor:\n");
    printf("  CORE:              picorv32\n");
    printf("  ISA:               rv32imac\n");
    printf("  FREQ:              %dMHz\n\n", CPU_FREQ);

    printf("Inst/Memory Device: \n");
    printf("  SPI Flash size:    16MB\n");
    printf("  On-board RAM size: %dKB\n", RAM_TOTAL / 1024);
    printf("  Extern PSRAM size: %dMB(%dx8MB)\n\n", 8 * PSRAM_NUM, PSRAM_NUM);

    printf("Memory Map IO Device:\n");
    printf("                     1 x QSPFS\n");
    printf("                    16 x GPIO\n");
    printf("                     1 x HOUSEKEEPING SPI\n");
    printf("                     1 x UART\n");
    printf("                     1 x SPI\n");
    printf("                     1 x I2C\n");
    printf("                     2 x TIMER\n");
    printf("                     1 x RNG\n");
    printf("                     1 x ARCHINFO\n");
    printf("                     1 x UART(HP)\n");
    printf("                     4 x PWM\n");
    printf("                     1 x PS2\n");
    printf("                     1 x QSPI\n");
    printf("                     1 x PSRAM(4x8MB)\n");
    printf("                     1 x SPFS(TPO)\n\n");
    printf("self test start...\n");
    // cmd_read_flash_id();
    cmd_read_flash_regs();
    cmd_print_spi_state();
    printf("[exterm psram test]\n");
    // cmd_memtest(0x04000000, 8 * 1024); // test extern psram
    printf("self test done\n");
}

void main()
{
    reg_uart_clkdiv = (uint32_t)(CPU_FREQ * 1000000 / UART_BPS);

    welcome_screen();
    set_flash_qspi_flag();

    ip_counter_timer_test();
    ip_gpio_test();
    ip_hk_spi_test();
    // ip_i2c_test();
    cust_ip_archinfo_test();
    cust_ip_rng_test();
    cust_ip_uart_test();
    cust_ip_ps2_test();
    cmd_benchmark(true, 0);
    cmd_benchmark_all();
    while (getchar_prompt("Press ENTER to continue..\n") != '\r')
    {
    }

    while (1)
    {
        printf("\n");
        printf("Select an action:\n");
        printf("\n");
        printf("   [1] Read SPI Flash ID\n");
        printf("   [2] Read SPI Config Regs\n");
        printf("   [3] Switch to default mode\n");
        printf("   [4] Switch to Dual I/O mode\n");
        printf("   [5] Switch to Quad I/O mode\n");
        printf("   [6] Switch to Quad DDR mode\n");
        printf("   [7] Toggle continuous read mode\n");
        printf("   [9] Run simplistic benchmark\n");
        printf("   [0] Benchmark all configs\n");
        printf("   [M] Run Memtest\n");
        printf("   [S] Print SPI state\n");
        printf("   [e] Echo UART\n");
        printf("\n");

        for (int rep = 10; rep > 0; rep--)
        {
            printf("tinysh> ");
            char cmd = getchar_prompt(0);
            if (cmd > 32 && cmd < 127)
                putch(cmd);
            printf("\n");

            switch (cmd)
            {
            case '1':
                cmd_read_flash_id();
                break;
            case '2':
                cmd_read_flash_regs();
                break;
            case '3':
                set_flash_mode_spi();
                break;
            case '4':
                set_flash_mode_dual();
                break;
            case '5':
                set_flash_mode_quad();
                break;
            case '6':
                set_flash_mode_qddr();
                break;
            case '7':
                reg_spictrl = reg_spictrl ^ 0x00100000;
                break;
            case '9':
                cmd_benchmark(true, 0);
                break;
            case '0':
                cmd_benchmark_all();
                break;
            case 'm':
                // cmd_memtest();
                break;
            case 's':
                cmd_print_spi_state();
                break;
            case 'e':
                cmd_echo();
                break;
            default:
                continue;
            }

            break;
        }
    }
}
