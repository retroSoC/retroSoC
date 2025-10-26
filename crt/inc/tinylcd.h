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

void ip_lcd_test();

#endif