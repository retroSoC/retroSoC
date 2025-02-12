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

#define RAM_TOTAL 0x20000 // 128 KB
#define PSRAM_NUM 4
#define CPU_FREQ 72     // unit: MHz
#define UART_BPS 115200 // unit: bps



#define I2C_TEST_START       ((uint32_t)0x80)
#define I2C_TEST_STOP        ((uint32_t)0x40)
#define I2C_TEST_READ        ((uint32_t)0x20)
#define I2C_TEST_WRITE       ((uint32_t)0x10)
#define I2C_TEST_START_READ  ((uint32_t)0xA0)
#define I2C_TEST_START_WRITE ((uint32_t)0x90)
#define I2C_TEST_STOP_READ   ((uint32_t)0x60)
#define I2C_TEST_STOP_WRITE  ((uint32_t)0x50)

#define I2C_STATUS_RXACK     ((uint32_t)0x80) // (1 << 7)
#define I2C_STATUS_BUSY      ((uint32_t)0x40) // (1 << 6)
#define I2C_STATUS_AL        ((uint32_t)0x20) // (1 << 5)
#define I2C_STATUS_TIP       ((uint32_t)0x02) // (1 << 1)
#define I2C_STATUS_IF        ((uint32_t)0x01) // (1 << 0)

#define I2C_DEV_ADDR_16BIT   0
#define I2C_DEV_ADDR_8BIT    1

#define I2C_TEST_NUM         24
#define AT24C64_SLV_ADDR     0xA0
#define PCF8563B_SLV_ADDR    0xA2

#define PCF8563B_CTL_STATUS1 ((uint8_t)0x00)
#define PCF8563B_CTL_STATUS2 ((uint8_t)0x01)
#define PCF8563B_SECOND_REG  ((uint8_t)0x02)
#define PCF8563B_MINUTE_REG  ((uint8_t)0x03)
#define PCF8563B_HOUR_REG    ((uint8_t)0x04)
#define PCF8563B_DAY_REG     ((uint8_t)0x05)
#define PCF8563B_WEEKDAY_REG ((uint8_t)0x06)
#define PCF8563B_MONTH_REG   ((uint8_t)0x07)
#define PCF8563B_YEAR_REG    ((uint8_t)0x08)

#define SECOND_MINUTE_REG_WIDTH ((uint8_t)0x7F)
#define HOUR_DAY_REG_WIDTH      ((uint8_t)0x3F)
#define WEEKDAY_REG_WIDTH       ((uint8_t)0x07)
#define MONTH_REG_WIDTH         ((uint8_t)0x1F)
#define YEAR_REG_WIDTH          ((uint8_t)0xFF)
#define BCD_Century             ((uint8_t)0x80)

#define lcd_dc_clr      (reg_gpio_data = (uint32_t)0b000)
#define lcd_dc_set      (reg_gpio_data = (uint32_t)0b100)

#define USE_HORIZONTAL 2

#if USE_HORIZONTAL == 0 || USE_HORIZONTAL == 1
#define LCD_W 135
#define LCD_H 240
#else
#define LCD_W 240
#define LCD_H 135
#endif

#define SPI_CMD_RD      0
#define SPI_CMD_WR      1
#define SPI_CMD_QRD     2
#define SPI_CMD_QWR     3
#define SPI_CMD_SWRST   4

#define SPI_CSN0        0
#define SPI_CSN1        1
#define SPI_CSN2        2
#define SPI_CSN3        3

typedef struct {
    struct {
        uint8_t second;
        uint8_t minute;
        uint8_t hour;
    } time;

    struct {
        uint8_t weekday;
        uint8_t day;
        uint8_t month;
        uint8_t year;
    } date;

} PCF8563B_info_t;



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

void cust_ip_pwm_test()
{
    printf("pwm test\n");

    reg_cust_pwm_ctrl = (uint32_t)0;
    reg_cust_pwm_pscr = (uint32_t)(CPU_FREQ - 1); // 50M / 50 = 1MHz
    reg_cust_pwm_cmp = (uint32_t)(1000 - 1);      // 1KHz
    printf("reg_cust_pwm_ctrl: %d reg_cust_pwm_pscr: %d reg_cust_pwm_cmp: %d\n", reg_cust_pwm_ctrl, reg_cust_pwm_pscr, reg_cust_pwm_cmp);
    for (int i = 0; i < 36; i++)
    {
        printf("[PWM]: %d/36\n", i+1);
        for (int j = 10; j <= 990; j++)
        {
            reg_cust_pwm_ctrl = (uint32_t)4;
            reg_cust_pwm_cr0 = j;
            reg_cust_pwm_ctrl = (uint32_t)3;
            reg_cust_pwm_pscr = 49;
            delay_ms(5);
        }

        for (int j = 990; j >= 10; j--)
        {
            reg_cust_pwm_ctrl = (uint32_t)4;
            reg_cust_pwm_cr0 = j;
            reg_cust_pwm_ctrl = (uint32_t)3;
            reg_cust_pwm_pscr = 49;
            delay_ms(5);
        }
    }
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

void i2c_config() {
    reg_cust_i2c_ctrl = (uint32_t)0;
    reg_cust_i2c_pscr = (uint32_t)99;         // 50MHz / (5 * 100KHz) - 1
    printf("CTRL: %d PSCR: %d\n", reg_cust_i2c_ctrl, reg_cust_i2c_pscr);
    reg_cust_i2c_ctrl = (uint32_t)0b10000000; // core en
}

uint32_t i2c_get_ack() {
    while ((reg_cust_i2c_sr & I2C_STATUS_TIP) == 0); // need TIP go to 1
    while ((reg_cust_i2c_sr & I2C_STATUS_TIP) != 0); // and then go back to 0
    return !(reg_cust_i2c_sr & I2C_STATUS_RXACK);    // invert since signal is active low
}

uint32_t i2c_busy() {
    return ((reg_cust_i2c_sr & I2C_STATUS_BUSY) == I2C_STATUS_BUSY);
}

void i2c_wr_start(uint32_t slv_addr) {
    reg_cust_i2c_txr = slv_addr;
    reg_cust_i2c_cmd = I2C_TEST_START_WRITE;
    if (!i2c_get_ack()) printf("[wr start]no ack recv\n");
}

void i2c_rd_start(uint32_t slv_addr) {
    do {
        reg_cust_i2c_txr = slv_addr;
        reg_cust_i2c_cmd = I2C_TEST_START_WRITE;
    }while (!i2c_get_ack());
}

void i2c_write(uint8_t val) {
    reg_cust_i2c_txr = val;
    reg_cust_i2c_cmd = I2C_TEST_WRITE;
    if (!i2c_get_ack()) printf("[i2c write]no ack recv\n");
    // do {
    //     reg_cust_i2c_txr = val;
    //     reg_cust_i2c_cmd = I2C_TEST_WRITE;
    // } while(!i2c_get_ack());
}

uint32_t i2c_read(uint32_t cmd) {
    reg_cust_i2c_cmd = cmd;
    if (!i2c_get_ack()) printf("[i2c read]no ack recv\n");
    return reg_cust_i2c_rxr;
}

void i2c_stop() {
    reg_cust_i2c_cmd = I2C_TEST_STOP;
    while(i2c_busy());
}

void i2c_wr_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    // i2c_wr_start(slv_addr);
    i2c_rd_start(slv_addr);
    if(type == I2C_DEV_ADDR_16BIT) {
        i2c_write((uint8_t)((reg_addr >> 8) & 0xFF));
        i2c_write((uint8_t)(reg_addr & 0xFF));
    } else {
        i2c_write((uint8_t)(reg_addr & 0xFF));
    }
    for(int i = 0; i < num; ++i) {
        i2c_write(*data);
        ++data;
    }
    i2c_stop();
}

void i2c_rd_nbyte(uint8_t slv_addr, uint16_t reg_addr, uint8_t type, uint8_t num, uint8_t *data) {
    i2c_rd_start(slv_addr);
    if(type == I2C_DEV_ADDR_16BIT) {
        i2c_write((uint8_t)((reg_addr >> 8) & 0xFF));
        i2c_write((uint8_t)(reg_addr & 0xFF));
    } else {
        i2c_write((uint8_t)(reg_addr & 0xFF));
    }
    i2c_stop();

    i2c_wr_start(slv_addr + 1);
    for (int i = 0; i < num; ++i) {
        if (i == num - 1) data[i] = i2c_read(I2C_TEST_STOP_READ);
        else data[i] = i2c_read(I2C_TEST_READ);
    }
}

uint8_t PCF8563B_bin2bcd(uint8_t val) {
    uint8_t bcdhigh = 0;
    while (val >= 10) {
        ++bcdhigh;
        val -= 10;
    }
    return ((uint8_t)(bcdhigh << 4) | val);
}

static uint8_t PCF8563B_bcd2bin(uint8_t val,uint8_t reg_width)
{
    uint8_t res = 0;
    res = (val & (reg_width & 0xF0)) >> 4;
    res = res * 10 + (val & (reg_width & 0x0F));
    return res;
}

void PCF8563B_wr_reg(PCF8563B_info_t *info) {
    uint8_t wr_data[7] = {0};
    *wr_data       = PCF8563B_bin2bcd(info->time.second);
    *(wr_data + 1) = PCF8563B_bin2bcd(info->time.minute);
    *(wr_data + 2) = PCF8563B_bin2bcd(info->time.hour);
    *(wr_data + 3) = PCF8563B_bin2bcd(info->date.day);
    *(wr_data + 4) = PCF8563B_bin2bcd(info->date.weekday);
    *(wr_data + 5) = PCF8563B_bin2bcd(info->date.month);
    *(wr_data + 6) = PCF8563B_bin2bcd(info->date.year);
    i2c_wr_nbyte(PCF8563B_SLV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, wr_data);
}

PCF8563B_info_t PCF8563B_rd_reg() {
    uint8_t rd_data[7] = {0};
    PCF8563B_info_t info = {0};
    i2c_rd_nbyte(PCF8563B_SLV_ADDR, PCF8563B_SECOND_REG, I2C_DEV_ADDR_8BIT, 7, rd_data);
    info.time.second  = PCF8563B_bcd2bin(rd_data[0], SECOND_MINUTE_REG_WIDTH);
    info.time.minute  = PCF8563B_bcd2bin(rd_data[1], SECOND_MINUTE_REG_WIDTH);
    info.time.hour    = PCF8563B_bcd2bin(rd_data[2], HOUR_DAY_REG_WIDTH);
    info.date.day     = PCF8563B_bcd2bin(rd_data[3], HOUR_DAY_REG_WIDTH);
    info.date.weekday = PCF8563B_bcd2bin(rd_data[4], WEEKDAY_REG_WIDTH);
    info.date.month   = PCF8563B_bcd2bin(rd_data[5], MONTH_REG_WIDTH);
    info.date.year    = PCF8563B_bcd2bin(rd_data[6], YEAR_REG_WIDTH);
    return info;
}

void cust_ip_i2c_test() {
    printf("i2c test\n");
    i2c_config();
    printf("AT24C64 wr/rd test\n");
    // prepare ref data
    // uint8_t ref_data[I2C_TEST_NUM], rd_data[I2C_TEST_NUM];
    // for(int i = 0; i < I2C_TEST_NUM; ++i) ref_data[i] = i;
    // // write AT24C64
    // i2c_wr_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);
    // // read AT24C64
    // i2c_rd_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, rd_data);
    // // check data
    // for(int i = 0; i < I2C_TEST_NUM; ++i) {
    //     printf("recv: %d expt: %d\n", rd_data[i], i);
    //     if (rd_data[i] != i) printf("test fail\n");
    // }

    // i2c_wr_nbyte(AT24C64_SLV_ADDR, (uint16_t)0, I2C_DEV_ADDR_16BIT, I2C_TEST_NUM, ref_data);

    printf("AT24C64 wr/rd test done\n");
    printf("PCF8563B test\n");
    PCF8563B_info_t init1_info = {
        .time.second  = 51,
        .time.minute  = 30,
        .time.hour    = 18,
        .date.weekday = 3,
        .date.day     = 7,
        .date.month   = 8,
        .date.year    = 24
    };
    PCF8563B_wr_reg(&init1_info);

    PCF8563B_info_t rd_info = {0};
    for(int i = 0; i < 100; ++i) {
        rd_info = PCF8563B_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
                                                    rd_info.date.day, rd_info.date.weekday,
                                                    rd_info.time.hour, rd_info.time.minute,
                                                    rd_info.time.second);
    }

    PCF8563B_info_t init2_info = {
        .time.second  = 23,
        .time.minute  = 22,
        .time.hour    = 12,
        .date.weekday = 1,
        .date.day     = 19,
        .date.month   = 8,
        .date.year    = 24
    };
    PCF8563B_wr_reg(&init2_info);
    for(int i = 0; i < 100; ++i) {
        rd_info = PCF8563B_rd_reg();
        printf("[PCF8563B] %d-%d-%d %d %d:%d:%d\n", rd_info.date.year, rd_info.date.month,
                                                    rd_info.date.day, rd_info.date.weekday,
                                                    rd_info.time.hour, rd_info.time.minute,
                                                    rd_info.time.second);
    }

    printf("PCF8563B test done\n");
    printf("test done\n");
}


void spi_init() {
    reg_gpio_enb = (uint32_t)0b011;
    reg_cust_qspi_status = (uint32_t)0b10000;
    reg_cust_qspi_status = (uint32_t)0b00000;
    reg_cust_qspi_intcfg = (uint32_t)0b00000;
    reg_cust_qspi_dum    = (uint32_t)0;
    reg_cust_qspi_clkdiv = (uint32_t)0; // sck = apb_clk/2(div+1)
}


int32_t spi_write_fifo(uint32_t *data, uint32_t datalen) {
    volatile int num_words, i;
    num_words = (datalen >> 5) & 0x7FF;

    if ( (datalen & 0x1F) != 0)
        num_words++;

    for (i = 0; i < num_words; i++) {
        while (((reg_cust_qspi_status >> 24) & 0xFF) >= 8);
        reg_cust_qspi_txfifo = data[i];
    }

    return 0;
}


int32_t spi_set_datalen(uint32_t datalen) {
    volatile int old_len;
    old_len = reg_cust_qspi_len;
    old_len = ((datalen << 16) & 0xFFFF0000) | (old_len & 0xFFFF);
    reg_cust_qspi_len = old_len;
    
    return 0;
}

int32_t spi_start_transaction(uint32_t trans_type, uint32_t csnum) {
    reg_cust_qspi_status= ((1 << (csnum + 8)) & 0xF00) | ((1 << trans_type) & 0xFF);
    return 0;
}

void spi_wr_dat(uint8_t data) {
    uint32_t wdata = ((uint32_t) data) << 24;
    spi_set_datalen(8);
    spi_write_fifo(&wdata, 8);
    spi_start_transaction(SPI_CMD_WR, SPI_CSN0);
    while ((reg_cust_qspi_status & 0xFFFF) != 1);
}

void lcd_wr_cmd(uint8_t cmd) {
    lcd_dc_clr;
    spi_wr_dat(cmd);
    // lcd_dc_set;
}

void lcd_wr_data8(uint8_t dat) {
    lcd_dc_set;
    spi_wr_dat(dat);
}

void lcd_wr_data16(uint16_t dat) {
    lcd_dc_set;
    spi_wr_dat(dat >> 8);
    spi_wr_dat(dat);
}

void lcd_init() {
    delay_ms(500);
    lcd_wr_cmd(0x11);
    delay_ms(120);
    lcd_wr_cmd(0x36);
    if(USE_HORIZONTAL == 0)lcd_wr_data8(0x00);
    else if(USE_HORIZONTAL == 1)lcd_wr_data8(0xC0);
    else if(USE_HORIZONTAL == 2)lcd_wr_data8(0x70);
    else lcd_wr_data8(0xA0);

    lcd_wr_cmd(0x3A);
    lcd_wr_data8(0x05);

    lcd_wr_cmd(0xB2);
    lcd_wr_data8(0x0C);
    lcd_wr_data8(0x0C);
    lcd_wr_data8(0x00);
    lcd_wr_data8(0x33);
    lcd_wr_data8(0x33);

    lcd_wr_cmd(0xB7);
    lcd_wr_data8(0x35);

    lcd_wr_cmd(0xBB);
    lcd_wr_data8(0x19);

    lcd_wr_cmd(0xC0);
    lcd_wr_data8(0x2C);

    lcd_wr_cmd(0xC2);
    lcd_wr_data8(0x01);

    lcd_wr_cmd(0xC3);
    lcd_wr_data8(0x12);

    lcd_wr_cmd(0xC4);
    lcd_wr_data8(0x20);

    lcd_wr_cmd(0xC6);
    lcd_wr_data8(0x0F);

    lcd_wr_cmd(0xD0);
    lcd_wr_data8(0xA4);
    lcd_wr_data8(0xA1);

    lcd_wr_cmd(0xE0);
    lcd_wr_data8(0xD0);
    lcd_wr_data8(0x04);
    lcd_wr_data8(0x0D);
    lcd_wr_data8(0x11);
    lcd_wr_data8(0x13);
    lcd_wr_data8(0x2B);
    lcd_wr_data8(0x3F);
    lcd_wr_data8(0x54);
    lcd_wr_data8(0x4C);
    lcd_wr_data8(0x18);
    lcd_wr_data8(0x0D);
    lcd_wr_data8(0x0B);
    lcd_wr_data8(0x1F);
    lcd_wr_data8(0x23);

    lcd_wr_cmd(0xE1);
    lcd_wr_data8(0xD0);
    lcd_wr_data8(0x04);
    lcd_wr_data8(0x0C);
    lcd_wr_data8(0x11);
    lcd_wr_data8(0x13);
    lcd_wr_data8(0x2C);
    lcd_wr_data8(0x3F);
    lcd_wr_data8(0x44);
    lcd_wr_data8(0x51);
    lcd_wr_data8(0x2F);
    lcd_wr_data8(0x1F);
    lcd_wr_data8(0x1F);
    lcd_wr_data8(0x20);
    lcd_wr_data8(0x23);

    lcd_wr_cmd(0x21);
    lcd_wr_cmd(0x29);
}


void lcd_addr_set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2) {
    if(USE_HORIZONTAL == 0) {
        lcd_wr_cmd(0x2A);      // set col addr
        lcd_wr_data16(x1 + 52);
        lcd_wr_data16(x2 + 52);
        lcd_wr_cmd(0x2B);      // set row addr
        lcd_wr_data16(y1 + 40);
        lcd_wr_data16(y2 + 40);
        lcd_wr_cmd(0x2C);      // write memory
    } else if(USE_HORIZONTAL == 1) {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 53);
        lcd_wr_data16(x2 + 53);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 40);
        lcd_wr_data16(y2 + 40);
        lcd_wr_cmd(0x2C);
    } else if(USE_HORIZONTAL == 2) {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 40);
        lcd_wr_data16(x2 + 40);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 53);
        lcd_wr_data16(y2 + 53);
        lcd_wr_cmd(0x2C);
    } else {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 40);
        lcd_wr_data16(x2 + 40);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 52);
        lcd_wr_data16(y2 + 52);
        lcd_wr_cmd(0x2C);
    }
}

void lcd_fill(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint16_t color) {
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    for(uint16_t i = ysta; i < yend; ++i) {
        for(uint16_t j = xsta; j < xend; ++j) {
            lcd_wr_data16(color);
        }
    }
}

void cust_ip_lcd_test() {
    printf("lcd test\n");
    spi_init();
    lcd_init();
    printf("lcd init done\n");
    // lcd_wr_cmd(0x01); // software reset
    for(int i = 0; i < 6; ++i) {
        lcd_fill(0, 0, LCD_W, LCD_H, 0xF800); // red
        lcd_fill(0, 0, LCD_W, LCD_H, 0x07E0); // green
        lcd_fill(0, 0, LCD_W, LCD_H, 0x001F); // blue
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
    printf("                     2 x TIMER\n");
    printf("                     1 x RNG\n");
    printf("                     1 x ARCHINFO\n");
    printf("                     1 x UART(HP)\n");
    printf("                     4 x PWM\n");
    printf("                     1 x PS2\n");
    printf("                     1 x QSPI\n");
    printf("                     1 x I2C\n");
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

    cust_ip_archinfo_test();
    cust_ip_rng_test();
    // cust_ip_uart_test();
    cust_ip_pwm_test();
    // cust_ip_ps2_test();
    cust_ip_i2c_test();
    cust_ip_lcd_test();

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
