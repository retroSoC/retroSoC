#ifndef TINYLCD_H__
#define TINYLCD_H__

#include <stdint.h>

#define lcd_dc_clr     (reg_gpio_data = (uint32_t)0b000)
#define lcd_dc_set     (reg_gpio_data = (uint32_t)0b100)

#define USE_HORIZONTAL 2

#if USE_HORIZONTAL == 0 || USE_HORIZONTAL == 1
#define LCD_W 135
#define LCD_H 240
#else
#define LCD_W 240
#define LCD_H 135
#endif

#define SPI_CMD_RD     0
#define SPI_CMD_WR     1
#define SPI_CMD_QRD    2
#define SPI_CMD_QWR    3
#define SPI_CMD_SWRST  4

#define SPI_CSN0       0
#define SPI_CSN1       1
#define SPI_CSN2       2
#define SPI_CSN3       3

void qspi1_init();
void qspi1_wr_dat(uint8_t dat);
void lcd_wr_cmd(uint8_t cmd);
void lcd_wr_data8(uint8_t dat);
void lcd_wr_data16(uint16_t dat);
void lcd_wr_data32(uint32_t dat);
void lcd_wr_data32x2(uint32_t dat1, uint32_t dat2);
void lcd_wr_data32x8(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                     uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8);

void lcd_wr_data32x16(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                      uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8,
                      uint32_t dat9, uint32_t dat10, uint32_t dat11, uint32_t dat12,
                      uint32_t dat13, uint32_t dat14, uint32_t dat15, uint32_t dat16);

void lcd_wr_data32x32(uint32_t dat1, uint32_t dat2, uint32_t dat3, uint32_t dat4,
                      uint32_t dat5, uint32_t dat6, uint32_t dat7, uint32_t dat8,
                      uint32_t dat9, uint32_t dat10, uint32_t dat11, uint32_t dat12,
                      uint32_t dat13, uint32_t dat14, uint32_t dat15, uint32_t dat16,
                      uint32_t dat17, uint32_t dat18, uint32_t dat19, uint32_t dat20,
                      uint32_t dat21, uint32_t dat22, uint32_t dat23, uint32_t dat24,
                      uint32_t dat25, uint32_t dat26, uint32_t dat27, uint32_t dat28,
                      uint32_t dat29, uint32_t dat30, uint32_t dat31, uint32_t dat32);

void lcd_wr_data32xlen(uint32_t dat, uint32_t dat_len);
void lcd_init();
void lcd_addr_set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2);
void lcd_fill(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t color);
void ip_lcd_test();

#endif