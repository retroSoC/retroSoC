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

#include "firmware.h"

#define RAM_TOTAL 0x10000 // 64 KB
#define PSRAM_NUM 4
#define CPU_FREQ 50   // unit: MHz
#define UART_BPS 9600 // unit: bps

// a pointer to this is a null pointer, but the compiler does not
// know that because "sram" is a linker symbol from sections.lds.
extern uint32_t sram;
extern uint32_t flashio_worker_begin;
extern uint32_t flashio_worker_end;

void flashio(uint8_t *data, int len, uint8_t wrencmd)
{
    uint32_t func[&flashio_worker_end - &flashio_worker_begin];

    uint32_t *src_ptr = &flashio_worker_begin;
    uint32_t *dst_ptr = func;

    while (src_ptr != &flashio_worker_end)
        *(dst_ptr++) = *(src_ptr++);

    ((void (*)(uint8_t *, uint32_t, uint32_t))func)(data, len, wrencmd);
}

void set_flash_qspi_flag()
{
    uint8_t buffer[8];

    // Read Configuration Registers (RDCR1 35h)
    buffer[0] = 0x35;
    buffer[1] = 0x00; // rdata
    flashio(buffer, 2, 0);
    uint8_t sr2 = buffer[1];

    // Write Enable Volatile (50h) + Write Status Register 2 (31h)
    buffer[0] = 0x31;
    buffer[1] = sr2 | 2; // Enable QSPI
    flashio(buffer, 2, 0x50);
}

void set_flash_mode_spi()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00000000;
}

void set_flash_mode_dual()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00400000;
}

void set_flash_mode_quad()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00240000;
}

void set_flash_mode_qddr()
{
    reg_spictrl = (reg_spictrl & ~0x007f0000) | 0x00670000;
}

void enable_flash_crm()
{
    reg_spictrl |= 0x00100000;
}

void putchar(char c)
{
    if (c == '\n')
        putchar('\r');
    reg_uart_data = c;
}

void print(const char *p)
{
    while (*p)
        putchar(*(p++));
}

void print_hex(uint32_t v, int digits)
{
    for (int i = 7; i >= 0; i--)
    {
        char c = "0123456789abcdef"[(v >> (4 * i)) & 15];
        if (c == '0' && i >= digits)
            continue;
        putchar(c);
        digits = i;
    }
}

void print_dec(uint32_t v)
{
    if (v >= 1000)
    {
        print(">=1000");
        return;
    }

    if (v >= 900)
    {
        putchar('9');
        v -= 900;
    }
    else if (v >= 800)
    {
        putchar('8');
        v -= 800;
    }
    else if (v >= 700)
    {
        putchar('7');
        v -= 700;
    }
    else if (v >= 600)
    {
        putchar('6');
        v -= 600;
    }
    else if (v >= 500)
    {
        putchar('5');
        v -= 500;
    }
    else if (v >= 400)
    {
        putchar('4');
        v -= 400;
    }
    else if (v >= 300)
    {
        putchar('3');
        v -= 300;
    }
    else if (v >= 200)
    {
        putchar('2');
        v -= 200;
    }
    else if (v >= 100)
    {
        putchar('1');
        v -= 100;
    }

    if (v >= 90)
    {
        putchar('9');
        v -= 90;
    }
    else if (v >= 80)
    {
        putchar('8');
        v -= 80;
    }
    else if (v >= 70)
    {
        putchar('7');
        v -= 70;
    }
    else if (v >= 60)
    {
        putchar('6');
        v -= 60;
    }
    else if (v >= 50)
    {
        putchar('5');
        v -= 50;
    }
    else if (v >= 40)
    {
        putchar('4');
        v -= 40;
    }
    else if (v >= 30)
    {
        putchar('3');
        v -= 30;
    }
    else if (v >= 20)
    {
        putchar('2');
        v -= 20;
    }
    else if (v >= 10)
    {
        putchar('1');
        v -= 10;
    }

    if (v >= 9)
    {
        putchar('9');
        v -= 9;
    }
    else if (v >= 8)
    {
        putchar('8');
        v -= 8;
    }
    else if (v >= 7)
    {
        putchar('7');
        v -= 7;
    }
    else if (v >= 6)
    {
        putchar('6');
        v -= 6;
    }
    else if (v >= 5)
    {
        putchar('5');
        v -= 5;
    }
    else if (v >= 4)
    {
        putchar('4');
        v -= 4;
    }
    else if (v >= 3)
    {
        putchar('3');
        v -= 3;
    }
    else if (v >= 2)
    {
        putchar('2');
        v -= 2;
    }
    else if (v >= 1)
    {
        putchar('1');
        v -= 1;
    }
    else
        putchar('0');
}

char getchar_prompt(char *prompt)
{
    int32_t c = -1;

    uint32_t cycles_begin, cycles_now, cycles;
    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_begin));

    if (prompt)
        print(prompt);

    while (c == -1)
    {
        __asm__ volatile("rdcycle %0"
                         : "=r"(cycles_now));
        cycles = cycles_now - cycles_begin;
        if (cycles > 12000000)
        {
            if (prompt)
                print(prompt);
            cycles_begin = cycles_now;
        }
        c = reg_uart_data;
    }

    return c;
}

char getchar()
{
    return getchar_prompt(0);
}

void cmd_print_spi_state()
{
    print("SPI State:\n");

    print("  LATENCY ");
    print_dec((reg_spictrl >> 16) & 15);
    print("\n");

    print("  DDR ");
    if ((reg_spictrl & (1 << 22)) != 0)
        print("ON\n");
    else
        print("OFF\n");

    print("  QSPI ");
    if ((reg_spictrl & (1 << 21)) != 0)
        print("ON\n");
    else
        print("OFF\n");

    print("  CRM ");
    if ((reg_spictrl & (1 << 20)) != 0)
        print("ON\n");
    else
        print("OFF\n");
}

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

void cmd_memtest(uint32_t addr, uint32_t range)
{
    int cyc_count = 5;
    int stride = 256;
    uint32_t state;

    volatile uint32_t *base_word = (uint32_t *)addr;
    volatile uint8_t *base_byte = (uint8_t *)addr;

    print("Running memtest: \n");

    // Walk in stride increments, word access
    // for (int i = 1; i <= cyc_count; i++)
    // {
    //     state = i;
    //     for (int word = 0; word < RAM_TOTAL / sizeof(int); word += stride)
    //     {
    //         *(base_word + word) = xorshift32(&state);
    //     }

    //     state = i;
    //     for (int word = 0; word < RAM_TOTAL / sizeof(int); word += stride)
    //     {
    //         if (*(base_word + word) != xorshift32(&state))
    //         {
    //             print(" ***FAILED WORD*** at ");
    //             print_hex(4 * word, 4);
    //             print("\n");
    //             return;
    //         }
    //     }

    //     print(".");
    // }

    // Byte access
    for (int byte = 0; byte < range; byte++)
    {
        *(base_byte + byte) = (uint8_t)byte;
    }

    for (int byte = 0; byte < range; byte++)
    {
        if (*(base_byte + byte) != (uint8_t)byte)
        {
            print(" ***FAILED BYTE*** at ");
            print_hex(byte, 4);
            print("\n");
            return;
        }
    }

    print(" passed\n");
}

void cmd_read_flash_id()
{
    uint8_t buffer[17] = {0x9F, /* zeros */};
    flashio(buffer, 17, 0);

    for (int i = 1; i <= 16; i++)
    {
        putchar(' ');
        print_hex(buffer[i], 2);
    }
    putchar('\n');
}

uint8_t cmd_read_flash_reg(uint8_t cmd)
{
    uint8_t buffer[2] = {cmd, 0};
    flashio(buffer, 2, 0);
    return buffer[1];
}

void print_reg_bit(int val, const char *name)
{
    for (int i = 0; i < 12; i++)
    {
        if (*name == 0)
            putchar(' ');
        else
            putchar(*(name++));
    }

    putchar(val ? '1' : '0');
    putchar('\n');
}

void cmd_read_flash_regs()
{
    putchar('\n');

    uint8_t sr1 = cmd_read_flash_reg(0x05);
    uint8_t sr2 = cmd_read_flash_reg(0x35);
    uint8_t sr3 = cmd_read_flash_reg(0x15);

    print_reg_bit(sr1 & 0x01, "S0  (BUSY)");
    print_reg_bit(sr1 & 0x02, "S1  (WEL)");
    print_reg_bit(sr1 & 0x04, "S2  (BP0)");
    print_reg_bit(sr1 & 0x08, "S3  (BP1)");
    print_reg_bit(sr1 & 0x10, "S4  (BP2)");
    print_reg_bit(sr1 & 0x20, "S5  (TB)");
    print_reg_bit(sr1 & 0x40, "S6  (SEC)");
    print_reg_bit(sr1 & 0x80, "S7  (SRP)");
    putchar('\n');

    print_reg_bit(sr2 & 0x01, "S8  (SRL)");
    print_reg_bit(sr2 & 0x02, "S9  (QE)");
    print_reg_bit(sr2 & 0x04, "S10 ----");
    print_reg_bit(sr2 & 0x08, "S11 (LB1)");
    print_reg_bit(sr2 & 0x10, "S12 (LB2)");
    print_reg_bit(sr2 & 0x20, "S13 (LB3)");
    print_reg_bit(sr2 & 0x40, "S14 (CMP)");
    print_reg_bit(sr2 & 0x80, "S15 (SUS)");
    putchar('\n');

    print_reg_bit(sr3 & 0x01, "S16 ----");
    print_reg_bit(sr3 & 0x02, "S17 ----");
    print_reg_bit(sr3 & 0x04, "S18 (WPS)");
    print_reg_bit(sr3 & 0x08, "S19 ----");
    print_reg_bit(sr3 & 0x10, "S20 ----");
    print_reg_bit(sr3 & 0x20, "S21 (DRV0)");
    print_reg_bit(sr3 & 0x40, "S22 (DRV1)");
    print_reg_bit(sr3 & 0x80, "S23 (HOLD)");
    putchar('\n');
}

uint32_t cmd_benchmark(bool verbose, uint32_t *instns_p)
{
    uint8_t data[256];
    uint32_t *words = (void *)data;

    uint32_t x32 = 314159265;

    uint32_t cycles_begin, cycles_end;
    uint32_t instns_begin, instns_end;
    __asm__ volatile("rdcycle %0"
                     : "=r"(cycles_begin));
    __asm__ volatile("rdinstret %0"
                     : "=r"(instns_begin));

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
        print("Cycles: 0x");
        print_hex(cycles_end - cycles_begin, 8);
        putchar('\n');

        print("Instns: 0x");
        print_hex(instns_end - instns_begin, 8);
        putchar('\n');

        print("Chksum: 0x");
        print_hex(x32, 8);
        putchar('\n');
    }

    if (instns_p)
        *instns_p = instns_end - instns_begin;

    return cycles_end - cycles_begin;
}

void cmd_benchmark_all()
{
    uint32_t instns = 0;

    print("default   ");
    set_flash_mode_spi();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');

    print("dual      ");
    set_flash_mode_dual();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');

    // print("dual-crm  ");
    // enable_flash_crm();
    // print_hex(cmd_benchmark(false, &instns), 8);
    // putchar('\n');

    print("quad      ");
    set_flash_mode_quad();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');

    print("quad-crm  ");
    enable_flash_crm();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');

    print("qddr      ");
    set_flash_mode_qddr();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');

    print("qddr-crm  ");
    enable_flash_crm();
    print_hex(cmd_benchmark(false, &instns), 8);
    putchar('\n');
}

void cmd_echo()
{
    print("Return to menu by sending '!'\n\n");
    char c;
    while ((c = getchar()) != '!')
        putchar(c);
}

void print_reg(char *info, uint32_t val, int digits)
{
    print(info);
    print_hex(val, digits);
    print("\n");
}

void ip_gpio_test()
{
    print("[IP] gpio test\n");

    print_reg("[GPIO ENB] ", reg_gpio_enb, 8);
    reg_gpio_enb = (uint32_t)0x0000;
    print_reg("[GPIO ENB] ", reg_gpio_enb, 8);

    print_reg("[GPIO DATA] ", reg_gpio_data, 8);
    reg_gpio_data = (uint32_t)0xffff;
    print_reg("[GPIO DATA] ", reg_gpio_data, 8);

    reg_gpio_data = (uint32_t)0x0000;
    print_reg("[GPIO DATA] ", reg_gpio_data, 8);
}

void ip_hk_spi_test()
{
    print("[IP] housekeeping spi test\n");

    print_reg("[HK CONFIG] ", reg_spi_commconfig, 8);
    print_reg("[HK ENB] ", reg_spi_enables, 8);
    print_reg("[HK PLL] ", reg_spi_pll_config, 8);
    print_reg("[HK MFGR ID] ", reg_spi_mfgr_id, 8);
    print_reg("[HK PROD ID] ", reg_spi_prod_id, 8);
    print_reg("[HK MASK REV] ", reg_spi_mask_rev, 8);
    print_reg("[HK PLL BYP] ", reg_spi_pll_bypass, 8);
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
    print("[IP] i2c test\n");
    reg_i2c_config = 0;
    reg_i2c_data = 0;
    i2c_init(5);
    // Send command 6, data byte 0xfa
    i2c_send(0x6, 0xfa);
}

void ip_counter_timer_test()
{
    print("[IP] counter timer test\n");
    print_reg("[TIM0 VALUE] ", reg_timer0_value, 8);
    print_reg("[TIM0 CONFIG] ", reg_timer0_config, 8);
    print_reg("[TIM1 VALUE] ", reg_timer1_value, 8);
    print_reg("[TIM1 CONFIG] ", reg_timer1_config, 8);

    reg_timer0_value = (uint32_t)0xffffffff;
    reg_timer0_config = (uint32_t)0x0001; // irq disable, count down, continuous mode, timer enable

    reg_timer1_value = (uint32_t)0x0000ffff;
    reg_timer1_config = (uint32_t)0x0101; // irq disable, count up, continuous mode, timer enable

    print_reg("[TIM0 VALUE] ", reg_timer0_value, 8);
    print_reg("[TIM0 CONFIG] ", reg_timer0_config, 8);
    print_reg("[TIM1 VALUE] ", reg_timer1_value, 8);
    print_reg("[TIM1 CONFIG] ", reg_timer1_config, 8);

    for (int i = 0; i < 10; ++i)
    {
        print_reg("[TIM0 DATA] ", reg_timer0_data, 8);
        print_reg("[TIM1 DATA] ", reg_timer1_data, 8);
    }
}

void cust_ip_archinfo_test()
{
    print("[CUST IP] archinfo test\n");

    print_reg("[ARCHINFO SYS] ", reg_cust_archinfo_sys, 8);
    print_reg("[ARCHINFO IDL] ", reg_cust_archinfo_idl, 8);
    print_reg("[ARCHINFO IDH] ", reg_cust_archinfo_idh, 8);
}

void cust_ip_rng_test()
{
    print("[CUST IP] rng test\n");

    reg_cust_rng_ctrl = (uint32_t)1;      // en the core
    reg_cust_rng_seed = (uint32_t)0xFE1C; // set the init seed
    print_reg("[RNG SEED] ", reg_cust_rng_seed, 8);

    for (int i = 0; i < 5; ++i)
    {
        print_reg("[RNG VAL] ", reg_cust_rng_val, 8);
    }

    print("[RNG] reset the seed\n");
    reg_cust_rng_seed = (uint32_t)0;
    for (int i = 0; i < 5; ++i)
    {
        print_reg("[RNG VAL] ", reg_cust_rng_val, 8);
    }
}

void cust_ip_uart_test()
{
    print("[CUST IP] uart test\n");

    print_reg("[UART DIV] ", reg_cust_uart_div, 8);
    print_reg("[UART LCR] ", reg_cust_uart_lcr, 8);

    reg_cust_uart_div = (uint32_t)434;    // 50x10^6 / 115200
    reg_cust_uart_fcr = (uint32_t)0b1111; // clear tx and rx fifo
    reg_cust_uart_fcr = (uint32_t)0b1100;
    reg_cust_uart_lcr = (uint32_t)0b00011111; // 8N1, en all irq

    print_reg("[UART DIV] ", reg_cust_uart_div, 8);
    print_reg("[UART LCR] ", reg_cust_uart_lcr, 8);

    print("uart tx test\n");
    uint32_t val = (uint32_t)0x41;
    for (int i = 0; i < 5; ++i)
    {
        while (((reg_cust_uart_lsr & 0x100) >> 8) == 1)
            ;
        reg_cust_uart_trx = (uint32_t)(val + i);
    }

    print("uart tx test done\n");
    print("uart rx test\n");
    uint32_t rx_val = 0;
    for (int i = 0; i < 5; ++i)
    {
        while (((reg_cust_uart_lsr & 0x080) >> 7) == 1)
            ;
        rx_val = reg_cust_uart_trx;
        print_reg("[UART TRX] ", rx_val, 8);
    }

    print("uart rx test done\n");
    print("uart done\n");
}

void cust_ip_ps2_test()
{
    print("[CUST IP] ps2 test\n");

    reg_cust_ps2_ctrl = (uint32_t)0b11;
    uint32_t kdb_code, i = 0;
    for (int i = 0; i < 5; i++)
    {
        kdb_code = reg_cust_ps2_data;
        if (kdb_code != 0)
        {
            print_reg("[PS2 DAT] ", kdb_code, 8);
        }
    }
}

void main()
{
    reg_uart_clkdiv = 52; // for 50M/9600bps
    // reg_uart_clkdiv = 434; // for 50M/115200bps
    // reg_uart_clkdiv = CPU_FREQ  * 1000000 / UART_BPS;
    print("bootloader end\n");
    print("uart config: 8n1 ");
    print_dec(UART_BPS);
    print("bps\n");
    print("booting...\n");
    set_flash_qspi_flag();

    // while (getchar_prompt("Press ENTER to continue..\n") != '\r') { /* wait */ }

    print("\n");
    print("           _             _____        _____ \n");
    print("          | |           / ____|      / ____|\n");
    print("  _ __ ___| |_ _ __ ___| (___   ___ | |     \n");
    print(" | '__/ _ \\ __| '__/ _ \\\\___ \\ / _ \\| |\n");
    print(" | | |  __/ |_| | | (_) |___) | (_) | |____ \n");
    print(" |_|  \\___|\\__|_|  \\___/_____/ \\___/ \\_____|\n");
    print("        author: maksyuki (2025-2025)\n");
    print("\n");

    print("Processor:\n");
    print("  CORE:              picorv32\n");
    print("  ISA:               rv32imac\n");
    print("  FREQ:              ");
    print_dec(CPU_FREQ);
    print("MHz\n");
    print("Inst/Memory Device: \n");
    print("  SPI Flash size:    32 MB\n");
    print("  On-board RAM size: ");
    print_dec(RAM_TOTAL / 1024);
    print(" KB\n");
    print("  Extern PSRAM size: ");
    print_dec(8 * PSRAM_NUM);
    print(" MB(");
    print_dec(PSRAM_NUM);
    print("x8MB)\n\n");

    print("Memory Map IO Device: \n");
    print("  1 x SPFS\n");
    print(" 16 x GPIO\n");
    print("  1 x HOUSEKEEPING SPI\n");
    print("  1 x UART\n");
    print("  1 x SPI\n");
    print("  1 x I2C\n");
    print("  2 x TIMER\n");
    print("  1 x RNG\n");
    print("  1 x ARCHINFO\n");
    print("  1 x UART(HP)\n");
    print("  4 x PWM\n");
    print("  1 x PS2\n");
    print("  1 x QSPI\n");
    print("  1 x PSRAM(4x8MB)\n\n");

    // cmd_read_flash_id();
    // cmd_read_flash_regs();
    // cmd_print_spi_state();
    // cmd_memtest(0, RAM_TOTAL); // test overwrites bss and data memory
    cmd_memtest(0x04000000, 16); // test extern psram

    // ip_counter_timer_test();
    // ip_gpio_test();
    // ip_hk_spi_test();
    // ip_i2c_test();
    // cust_ip_archinfo_test();
    // cust_ip_rng_test();
    // cust_ip_uart_test();
    // cust_ip_ps2_test();
    // cmd_benchmark(true, 0);
    // cmd_benchmark_all();
    // cmd_memtest();
    // cmd_echo();
    while (1)
        ;
    // while (1) {
    //     print("\n");
    //     print("Select an action:\n");
    //     print("\n");
    //     print("   [1] Read SPI Flash ID\n");
    //     print("   [2] Read SPI Config Regs\n");
    //     print("   [3] Switch to default mode\n");
    //     print("   [4] Switch to Dual I/O mode\n");
    //     print("   [5] Switch to Quad I/O mode\n");
    //     print("   [6] Switch to Quad DDR mode\n");
    //     print("   [7] Toggle continuous read mode\n");
    //     print("   [9] Run simplistic benchmark\n");
    //     print("   [0] Benchmark all configs\n");
    //     print("   [M] Run Memtest\n");
    //     print("   [S] Print SPI state\n");
    //     print("   [e] Echo UART\n");
    //     print("\n");

    //     for (int rep = 10; rep > 0; rep--)
    //     {
    //         print("Command> ");
    //         char cmd = getchar();
    //         if (cmd > 32 && cmd < 127)
    //             putchar(cmd);
    //         print("\n");

    //         switch (cmd)
    //         {
    //         case '1':
    //             cmd_read_flash_id();
    //             break;
    //         case '2':
    //             cmd_read_flash_regs();
    //             break;
    //         case '3':
    //             set_flash_mode_spi();
    //             break;
    //         case '4':
    //             set_flash_mode_dual();
    //             break;
    //         case '5':
    //             set_flash_mode_quad();
    //             break;
    //         case '6':
    //             set_flash_mode_qddr();
    //             break;
    //         case '7':
    //             reg_spictrl = reg_spictrl ^ 0x00100000;
    //             break;
    //         case '9':
    //             cmd_benchmark(true, 0);
    //             break;
    //         case '0':
    //             cmd_benchmark_all();
    //             break;
    //         case 'M':
    //             cmd_memtest();
    //             break;
    //         case 'S':
    //             cmd_print_spi_state();
    //             break;
    //         case 'e':
    //             cmd_echo();
    //             break;
    //         default:
    //             continue;
    //         }

    //         break;
    //     }
    // }
}
