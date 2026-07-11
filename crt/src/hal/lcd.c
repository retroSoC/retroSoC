
#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/hal/timer.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/qspi.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/dma.h>
#ifdef CSR_ENABLE
#include <retrosoc/arch/riscv/system_base.h>
#endif
// #include "image.h"
// #include "video.h"

// static uint16_t test_frame_data[] = {
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
//     0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678, 0x1234, 0x5678,
// };

static uint32_t rgb_color[][32] = {
    {
        // red
        0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
        0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
        0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
        0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
        0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
    },
    {
        // green
        0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
        0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
        0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
        0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
        0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
    },
    {
        // blue
        0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
        0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
        0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
        0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
        0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
    },
};

static bool rs_lcd_region_valid(uint16_t x_start, uint16_t y_start, uint16_t x_end,
                                uint16_t y_end) {
    return (x_end > x_start) && (y_end > y_start) && (x_end <= LCD_W) && (y_end <= LCD_H);
}

static void lcd_wr_dc_cmd(uint8_t cmd) {
    lcd_dc_clr;
    qspi0_wr_dat8(cmd);
}

static void lcd_wr_dc_data8(uint8_t dat) {
    lcd_dc_set;
    qspi0_wr_dat8(dat);
}

static void lcd_wr_dc_data16(uint16_t dat) {
    lcd_dc_set;
    qspi0_wr_dat16(dat);
}

static void lcd_wr_data32(uint32_t *dat, uint32_t len) {
    lcd_dc_set;
    qspi0_wr_data32(dat, len);
}

void lcd_init(void) {
    delay_ms(500);
    lcd_wr_dc_cmd(0x11);
    delay_ms(120);
    lcd_wr_dc_cmd(0x36);
    if (USE_HORIZONTAL == 0)
        lcd_wr_dc_data8(0x00);
    else if (USE_HORIZONTAL == 1)
        lcd_wr_dc_data8(0xC0);
    else if (USE_HORIZONTAL == 2)
        lcd_wr_dc_data8(0x70);
    else
        lcd_wr_dc_data8(0xA0);

    lcd_wr_dc_cmd(0x3A);
    lcd_wr_dc_data8(0x05);

    lcd_wr_dc_cmd(0xB2);
    lcd_wr_dc_data8(0x0C);
    lcd_wr_dc_data8(0x0C);
    lcd_wr_dc_data8(0x00);
    lcd_wr_dc_data8(0x33);
    lcd_wr_dc_data8(0x33);

    lcd_wr_dc_cmd(0xB7);
    lcd_wr_dc_data8(0x35);

    lcd_wr_dc_cmd(0xBB);
    lcd_wr_dc_data8(0x19);

    lcd_wr_dc_cmd(0xC0);
    lcd_wr_dc_data8(0x2C);

    lcd_wr_dc_cmd(0xC2);
    lcd_wr_dc_data8(0x01);

    lcd_wr_dc_cmd(0xC3);
    lcd_wr_dc_data8(0x12);

    lcd_wr_dc_cmd(0xC4);
    lcd_wr_dc_data8(0x20);

    lcd_wr_dc_cmd(0xC6);
    lcd_wr_dc_data8(0x0F);

    lcd_wr_dc_cmd(0xD0);
    lcd_wr_dc_data8(0xA4);
    lcd_wr_dc_data8(0xA1);

    lcd_wr_dc_cmd(0xE0);
    lcd_wr_dc_data8(0xD0);
    lcd_wr_dc_data8(0x04);
    lcd_wr_dc_data8(0x0D);
    lcd_wr_dc_data8(0x11);
    lcd_wr_dc_data8(0x13);
    lcd_wr_dc_data8(0x2B);
    lcd_wr_dc_data8(0x3F);
    lcd_wr_dc_data8(0x54);
    lcd_wr_dc_data8(0x4C);
    lcd_wr_dc_data8(0x18);
    lcd_wr_dc_data8(0x0D);
    lcd_wr_dc_data8(0x0B);
    lcd_wr_dc_data8(0x1F);
    lcd_wr_dc_data8(0x23);

    lcd_wr_dc_cmd(0xE1);
    lcd_wr_dc_data8(0xD0);
    lcd_wr_dc_data8(0x04);
    lcd_wr_dc_data8(0x0C);
    lcd_wr_dc_data8(0x11);
    lcd_wr_dc_data8(0x13);
    lcd_wr_dc_data8(0x2C);
    lcd_wr_dc_data8(0x3F);
    lcd_wr_dc_data8(0x44);
    lcd_wr_dc_data8(0x51);
    lcd_wr_dc_data8(0x2F);
    lcd_wr_dc_data8(0x1F);
    lcd_wr_dc_data8(0x1F);
    lcd_wr_dc_data8(0x20);
    lcd_wr_dc_data8(0x23);

    lcd_wr_dc_cmd(0x21);
    lcd_wr_dc_cmd(0x29);
    printf("lcd init done\n");
}

void lcd_addr_set(uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2) {
    if ((x1 > x2) || (y1 > y2) || (x2 >= LCD_W) || (y2 >= LCD_H)) {
        return;
    }
    if (USE_HORIZONTAL == 0) {
        lcd_wr_dc_cmd(0x2A); // set col addr
        lcd_wr_dc_data16(x1 + 52);
        lcd_wr_dc_data16(x2 + 52);
        lcd_wr_dc_cmd(0x2B); // set row addr
        lcd_wr_dc_data16(y1 + 40);
        lcd_wr_dc_data16(y2 + 40);
        lcd_wr_dc_cmd(0x2C); // write memory
    } else if (USE_HORIZONTAL == 1) {
        lcd_wr_dc_cmd(0x2A);
        lcd_wr_dc_data16(x1 + 53);
        lcd_wr_dc_data16(x2 + 53);
        lcd_wr_dc_cmd(0x2B);
        lcd_wr_dc_data16(y1 + 40);
        lcd_wr_dc_data16(y2 + 40);
        lcd_wr_dc_cmd(0x2C);
    } else if (USE_HORIZONTAL == 2) {
        lcd_wr_dc_cmd(0x2A);
        lcd_wr_dc_data16(x1 + 40);
        lcd_wr_dc_data16(x2 + 40);
        lcd_wr_dc_cmd(0x2B);
        lcd_wr_dc_data16(y1 + 53);
        lcd_wr_dc_data16(y2 + 53);
        lcd_wr_dc_cmd(0x2C);
    } else {
        lcd_wr_dc_cmd(0x2A);
        lcd_wr_dc_data16(x1 + 40);
        lcd_wr_dc_data16(x2 + 40);
        lcd_wr_dc_cmd(0x2B);
        lcd_wr_dc_data16(y1 + 52);
        lcd_wr_dc_data16(y2 + 52);
        lcd_wr_dc_cmd(0x2C);
    }
}

static void lcd_fill_bg(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t idx) {
    if (!rs_lcd_region_valid(xsta, ysta, xend, yend) ||
        (idx >= (sizeof(rgb_color) / sizeof(rgb_color[0])))) {
        return;
    }
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    uint32_t total_pixels = (uint32_t)(xend - xsta) * (uint32_t)(yend - ysta);

    for (uint32_t i = 0U; i < total_pixels; i += 64U) {
        const uint32_t pixels = ((total_pixels - i) < 64U) ? (total_pixels - i) : 64U;
        lcd_wr_data32(rgb_color[idx], (pixels + 1U) / 2U);
    }
}

void lcd_fill_image(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t *data) {
    if (!rs_lcd_region_valid(xsta, ysta, xend, yend) || (data == NULL)) {
        return;
    }
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);

    uint32_t total_pixels = (uint32_t)(xend - xsta) * (uint32_t)(yend - ysta);

#ifdef USE_QSPI0_DMA
    lcd_dc_set;
    uintptr_t addr = (uintptr_t)data;
    // printf("addr: %x\n\n", addr);
    qspi0_dma_xfer(addr, total_pixels / 2U); // every xfer contains two RGB565 pixels
#else
    uint32_t i;
    uint32_t j;
    for (i = 0U, j = 0U; (i + 64U) < total_pixels; i += 64U, j += 32U) {
        lcd_wr_data32(data + j, 32); // 32x2 pixels = 64pisel
    }

    if (i < total_pixels)
        lcd_wr_data32(data + j, (total_pixels - i) / 2U);
#endif
}

void lcd_fill_video(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t *data) {
    if (!rs_lcd_region_valid(xsta, ysta, xend, yend) || (data == NULL)) {
        return;
    }
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    uint32_t total_pixels = (uint32_t)(xend - xsta) * (uint32_t)(yend - ysta);
    uint32_t i;
    uint32_t j;
    for (i = 0U, j = 0U; (i + 64U) < total_pixels; i += 64U, j += 32U) {
        lcd_wr_data32(data + j, 32); // 32x2 pixels = 64pisel
    }

    if (i < total_pixels)
        lcd_wr_data32(data + j, (total_pixels - i) / 2U);
}

static void lcd_frame(uint32_t first, uint32_t pref_cnt) {
#ifdef CORE_PICORV32
    static uint32_t cycle_start, cycle_end;
    static uint32_t cycleh_start, cycleh_end;
    static uint32_t inst_start, inst_end;
    static uint32_t insth_start, insth_end;
    if (first) {
        __asm__ volatile("rdcycle %0" : "=r"(cycle_start));
        __asm__ volatile("rdcycleh %0" : "=r"(cycleh_start));
        __asm__ volatile("rdinstret %0" : "=r"(inst_start));
        __asm__ volatile("rdinstreth %0" : "=r"(insth_start));
    } else {
        __asm__ volatile("rdcycle %0" : "=r"(cycle_end));
        __asm__ volatile("rdcycleh %0" : "=r"(cycleh_end));
        __asm__ volatile("rdinstret %0" : "=r"(inst_end));
        __asm__ volatile("rdinstreth %0" : "=r"(insth_end));

        printf("cycles num: %d(high: %d)\n", cycle_end - cycle_start, cycleh_end - cycleh_start);
        printf("insts  num: %d(high: %d)\n", inst_end - inst_start, insth_end - insth_start);
        if (cycle_end > cycle_start) {
            const uint32_t elapsed_us = (cycle_end - cycle_start) / CPU_FREQ;
            if (elapsed_us != 0U) {
                printf("flush rate: %dfps\n", (pref_cnt * 1000000U) / elapsed_us);
            }
        }
    }
#elif CORE_HAZARD3
    static uint64_t cycle_start, cycle_end;
    static uint64_t inst_start, inst_end;
    if (first) {
        // cycle_start = __get_rv_cycle();
        // inst_start = __get_rv_instret();
    } else {
        // cycle_end = __get_rv_cycle();
        // inst_end = __get_rv_instret();
        if (cycle_end > cycle_start) {
            const uint64_t elapsed_us = (cycle_end - cycle_start) / CPU_FREQ;
            printf("cycles num: %lld\n", cycle_end - cycle_start);
            printf("insts  num: %lld\n", inst_end - inst_start);
            if (elapsed_us != 0U) {
                printf("flush rate: %lldfps\n", ((uint64_t)pref_cnt * 1000000U) / elapsed_us);
            }
        } else {
            printf("frame timing is unavailable on this core\n");
        }
    }

#else
    (void)first;
    (void)pref_cnt;
#endif
}

void ip_lcd_test(int argc, char **argv) {
    (void)argc;
    (void)argv;

    printf("lcd test\n");
    // // lcd_wr_dc_cmd(0x01); // software reset
    uint32_t pref_cnt = 0;
    lcd_frame(1, pref_cnt);
    for (int i = 0; i < 12; ++i) {
        lcd_fill_bg(0, 0, LCD_W, LCD_H, 0);
        lcd_fill_bg(0, 0, LCD_W, LCD_H, 1);
        lcd_fill_bg(0, 0, LCD_W, LCD_H, 2);
        pref_cnt += 3;
    }
    lcd_frame(0, pref_cnt);

#ifdef USE_QSPI0_DMA
    printf("enable dma\n");
#endif

    // pref_cnt = 0;
    // lcd_frame(1, pref_cnt);
    // for (int i = 0; i < 100; ++i) {
    //     lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_chunyihongbao);
    //     lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_retro_spitft);
    //     pref_cnt += 2;
    // }
    // lcd_frame(0, pref_cnt);

    // delay_ms(1000);

    // for (int i = 0; i < 100; ++i)
    // {
    //     lcd_fill_video(0, 0, 240, 135, only_my_railgun[i]);
    //     pref_cnt += 1;
    // }
    // lcd_frame(0, pref_cnt);
}
