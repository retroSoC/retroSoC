
#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
#include <tinygpio.h>
#include <tinylcd.h>

void spi_init()
{
    reg_gpio_enb = (uint32_t)0b011;
    reg_cust_qspi_status = (uint32_t)0b10000;
    reg_cust_qspi_status = (uint32_t)0b00000;
    reg_cust_qspi_intcfg = (uint32_t)0b00000;
    reg_cust_qspi_dum = (uint32_t)0;
    reg_cust_qspi_clkdiv = (uint32_t)0; // sck = apb_clk/2(div+1)
}

void spi_wr_dat(uint8_t dat)
{
    uint32_t wdat = ((uint32_t)dat) << 24;
    // spi_set_datalen(8);
    reg_cust_qspi_len = 0x80000;
    // spi_write_fifo(&wdata, 8);
    reg_cust_qspi_txfifo = wdat;
    // spi_start_transaction(SPI_CMD_WR, SPI_CSN0);
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_cmd(uint8_t cmd)
{
    lcd_dc_clr;
    spi_wr_dat(cmd);
}

void lcd_wr_data8(uint8_t dat)
{
    lcd_dc_set;
    spi_wr_dat(dat);
}

void lcd_wr_data16(uint16_t dat)
{
    lcd_dc_set;

    uint32_t wdat = ((uint32_t)dat) << 16;
    reg_cust_qspi_len = 0x100000; // NOTE: 16bits
    reg_cust_qspi_txfifo = wdat;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
    // spi_wr_dat(dat >> 8);
    // spi_wr_dat(dat);
}

void lcd_wr_data32(uint32_t dat)
{
    lcd_dc_set;

    reg_cust_qspi_len = 0x200000; // NOTE: 32bits
    reg_cust_qspi_txfifo = dat;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_data32x2(uint32_t dat1, uint32_t dat2)
{
    lcd_dc_set;

    reg_cust_qspi_len = 0x400000; // NOTE: 32x2bits
    reg_cust_qspi_txfifo = dat1;
    reg_cust_qspi_txfifo = dat2;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_data32x8(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                     uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8)
{
    lcd_dc_set;

    reg_cust_qspi_len = 0x1000000; // NOTE: 32x8bits
    reg_cust_qspi_txfifo = dat1;
    reg_cust_qspi_txfifo = dat2;
    reg_cust_qspi_txfifo = dat3;
    reg_cust_qspi_txfifo = dat4;
    reg_cust_qspi_txfifo = dat5;
    reg_cust_qspi_txfifo = dat6;
    reg_cust_qspi_txfifo = dat7;
    reg_cust_qspi_txfifo = dat8;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_data32x16(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                      uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8,
                      uint32_t dat9, uint32_t dat10, uint32_t dat11, uint32_t dat12,
                      uint32_t dat13, uint32_t dat14, uint32_t dat15, uint32_t dat16)
{
    lcd_dc_set;

    reg_cust_qspi_len = 0x2000000; // NOTE: 32x16bits
    reg_cust_qspi_txfifo = dat1;
    reg_cust_qspi_txfifo = dat2;
    reg_cust_qspi_txfifo = dat3;
    reg_cust_qspi_txfifo = dat4;
    reg_cust_qspi_txfifo = dat5;
    reg_cust_qspi_txfifo = dat6;
    reg_cust_qspi_txfifo = dat7;
    reg_cust_qspi_txfifo = dat8;
    reg_cust_qspi_txfifo = dat9;
    reg_cust_qspi_txfifo = dat10;
    reg_cust_qspi_txfifo = dat11;
    reg_cust_qspi_txfifo = dat12;
    reg_cust_qspi_txfifo = dat13;
    reg_cust_qspi_txfifo = dat14;
    reg_cust_qspi_txfifo = dat15;
    reg_cust_qspi_txfifo = dat16;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_data32x32(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                      uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8,
                      uint32_t dat9, uint32_t dat10, uint32_t dat11, uint32_t dat12,
                      uint32_t dat13, uint32_t dat14, uint32_t dat15, uint32_t dat16,
                      uint32_t dat17, uint32_t dat18, uint32_t dat19, uint32_t dat20,
                      uint32_t dat21, uint32_t dat22, uint32_t dat23, uint32_t dat24,
                      uint32_t dat25, uint32_t dat26, uint32_t dat27, uint32_t dat28,
                      uint32_t dat29, uint32_t dat30, uint32_t dat31, uint32_t dat32)
{
    lcd_dc_set;

    reg_cust_qspi_len = 0x4000000; // NOTE: 32x32bits
    reg_cust_qspi_txfifo = dat1;
    reg_cust_qspi_txfifo = dat2;
    reg_cust_qspi_txfifo = dat3;
    reg_cust_qspi_txfifo = dat4;
    reg_cust_qspi_txfifo = dat5;
    reg_cust_qspi_txfifo = dat6;
    reg_cust_qspi_txfifo = dat7;
    reg_cust_qspi_txfifo = dat8;
    reg_cust_qspi_txfifo = dat9;
    reg_cust_qspi_txfifo = dat10;
    reg_cust_qspi_txfifo = dat11;
    reg_cust_qspi_txfifo = dat12;
    reg_cust_qspi_txfifo = dat13;
    reg_cust_qspi_txfifo = dat14;
    reg_cust_qspi_txfifo = dat15;
    reg_cust_qspi_txfifo = dat16;
    reg_cust_qspi_txfifo = dat17;
    reg_cust_qspi_txfifo = dat18;
    reg_cust_qspi_txfifo = dat19;
    reg_cust_qspi_txfifo = dat20;
    reg_cust_qspi_txfifo = dat21;
    reg_cust_qspi_txfifo = dat22;
    reg_cust_qspi_txfifo = dat23;
    reg_cust_qspi_txfifo = dat24;
    reg_cust_qspi_txfifo = dat25;
    reg_cust_qspi_txfifo = dat26;
    reg_cust_qspi_txfifo = dat27;
    reg_cust_qspi_txfifo = dat28;
    reg_cust_qspi_txfifo = dat29;
    reg_cust_qspi_txfifo = dat30;
    reg_cust_qspi_txfifo = dat31;
    reg_cust_qspi_txfifo = dat32;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_wr_data32xlen(uint32_t dat, uint32_t dat_len)
{
    lcd_dc_set;

    reg_cust_qspi_len = (32 * dat_len) << 16; // NOTE: 32xlenbits
    for (int i = 0; i < dat_len; ++i)
        reg_cust_qspi_txfifo = dat;
    reg_cust_qspi_status = 258;
    while ((reg_cust_qspi_status & 0xFFFF) != 1)
        ;
}

void lcd_init()
{
    delay_ms(500);
    lcd_wr_cmd(0x11);
    delay_ms(120);
    lcd_wr_cmd(0x36);
    if (USE_HORIZONTAL == 0)
        lcd_wr_data8(0x00);
    else if (USE_HORIZONTAL == 1)
        lcd_wr_data8(0xC0);
    else if (USE_HORIZONTAL == 2)
        lcd_wr_data8(0x70);
    else
        lcd_wr_data8(0xA0);

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

void lcd_addr_set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2)
{
    if (USE_HORIZONTAL == 0)
    {
        lcd_wr_cmd(0x2A); // set col addr
        lcd_wr_data16(x1 + 52);
        lcd_wr_data16(x2 + 52);
        lcd_wr_cmd(0x2B); // set row addr
        lcd_wr_data16(y1 + 40);
        lcd_wr_data16(y2 + 40);
        lcd_wr_cmd(0x2C); // write memory
    }
    else if (USE_HORIZONTAL == 1)
    {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 53);
        lcd_wr_data16(x2 + 53);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 40);
        lcd_wr_data16(y2 + 40);
        lcd_wr_cmd(0x2C);
    }
    else if (USE_HORIZONTAL == 2)
    {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 40);
        lcd_wr_data16(x2 + 40);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 53);
        lcd_wr_data16(y2 + 53);
        lcd_wr_cmd(0x2C);
    }
    else
    {
        lcd_wr_cmd(0x2A);
        lcd_wr_data16(x1 + 40);
        lcd_wr_data16(x2 + 40);
        lcd_wr_cmd(0x2B);
        lcd_wr_data16(y1 + 52);
        lcd_wr_data16(y2 + 52);
        lcd_wr_cmd(0x2C);
    }
}

void lcd_fill(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t color)
{
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    for (uint16_t i = ysta; i < yend; ++i)
    {
        for (uint16_t j = xsta; j < xend; j += 64)
        {
            // lcd_wr_data16(color);
            // lcd_wr_data32(color);
            // lcd_wr_data32x2(color, color);
            // lcd_wr_data32x8(color, color, color, color, color, color, color, color);
            // lcd_wr_data32x16(color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color);
            lcd_wr_data32x32(color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color, color);
            // lcd_wr_data32xlen(color, 16);
        }
    }
}

void ip_lcd_test()
{
    printf("lcd test\n");
    spi_init();
    lcd_init();
    printf("lcd init done\n");
    // lcd_wr_cmd(0x01); // software reset
    // for(int i = 0; i < 6; ++i) {
    while (1)
    {
        lcd_fill(0, 0, LCD_W, LCD_H, 0xF800F800); // red
        lcd_fill(0, 0, LCD_W, LCD_H, 0x07E007E0); // green
        lcd_fill(0, 0, LCD_W, LCD_H, 0x001F001F); // blue
    }
}