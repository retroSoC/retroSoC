
#include <firmware.h>
#include <tinyprintf.h>
#include <tinytim.h>
#include <tinygpio.h>
#include <tinyqspi.h>
#include <tinylcd.h>
#include <tinydma.h>
#include "image.h"
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
 { // red
    0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
    0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
    0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
    0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800, 0xF800F800,
 },
 { // green
    0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
    0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
    0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
    0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0, 0x07E007E0,
 },
 { // blue
     0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
     0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
     0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
     0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F, 0x001F001F,
 },
};

void lcd_wr_dc_cmd(uint8_t cmd) {
    lcd_dc_clr;
#ifdef USE_QSPI0_DEV
    qspi0_wr_dat8(cmd);
#else
    qspi1_wr_dat8(cmd);
#endif
}

void lcd_wr_dc_data8(uint8_t dat) {
    lcd_dc_set;
#ifdef USE_QSPI0_DEV
    qspi0_wr_dat8(dat);
#else
    qspi1_wr_dat8(dat);
#endif
}

void lcd_wr_dc_data16(uint16_t dat) {
    lcd_dc_set;
#ifdef USE_QSPI0_DEV
    qspi0_wr_dat16(dat);
#else
    qspi1_wr_data16(dat);
#endif
}

void lcd_wr_data32(uint32_t* dat, uint32_t len) {
    lcd_dc_set;
#ifdef USE_QSPI0_DEV
    qspi0_wr_data32(dat, len);
#else
    qspi1_wr_data32(dat, len);
#endif
}


void lcd_init() {
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

void lcd_fill_bg(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t idx) {
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    int tot = (xend - xsta) * (yend - ysta);

    for(int i = 0; i < tot; i += 64) {
        lcd_wr_data32(rgb_color[idx], 32);
    }
    
}

void lcd_fill_image(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t *data) {
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);

    int tot = (xend - xsta) * (yend - ysta);
    printf("tot: %d\n", tot);

#ifdef USE_QSPI0_DMA
    uintptr_t addr = (uintptr_t)data;
    printf("addr: %x\n\n", addr);
    lcd_dc_set;
    qspi0_dma_xfer(addr, tot / 2); // perf: every xfer in 32bits(2 pixels for RGB565 format)
#else
    int i, j;
    for (i = 0, j = 0; i + 64 < tot; i += 64, j += 32) {
        lcd_wr_data32(data + j, 32); // 32x2 pixels = 64pisel
    }

    if (i < tot) lcd_wr_data32(data + j, (tot - i) / 2);
#endif
}

void lcd_fill_video(uint16_t xsta, uint16_t ysta, uint16_t xend, uint16_t yend, uint32_t *data) {
    lcd_addr_set(xsta, ysta, xend - 1, yend - 1);
    int tot = (xend - xsta) * (yend - ysta);
    int i, j;
    for (i = 0, j = 0; i + 64 < tot; i += 64, j += 32) {
        lcd_wr_data32(data + j, 32); // 32x2 pixels = 64pisel
    }

    if (i < tot) lcd_wr_data32(data + j, (tot - i) / 2);
}


void lcd_frame(uint32_t first, uint32_t pref_cnt) {
    static uint32_t cycle_start, cycle_end;
    static uint32_t cycleh_start, cycleh_end;
    static uint32_t inst_start, inst_end;
    static uint32_t insth_start, insth_end;

    if(first) {
        __asm__ volatile("rdcycle %0"    : "=r"(cycle_start));
        __asm__ volatile("rdcycleh %0"   : "=r"(cycleh_start));
        __asm__ volatile("rdinstret %0"  : "=r"(inst_start));
        __asm__ volatile("rdinstreth %0" : "=r"(insth_start));
    } else {
        __asm__ volatile("rdcycle %0"    : "=r"(cycle_end));
        __asm__ volatile("rdcycleh %0"   : "=r"(cycleh_end));
        __asm__ volatile("rdinstret %0"  : "=r"(inst_end));
        __asm__ volatile("rdinstreth %0" : "=r"(insth_end));

        printf("cycles num: %d(high: %d)\n", cycle_end - cycle_start, cycleh_end - cycleh_start);
        printf("insts  num: %d(high: %d)\n", inst_end - inst_start, insth_end - insth_start);
        printf("flush rate: %dfps\n", pref_cnt / ((cycle_end - cycle_start) / CPU_FREQ / 1000000));
    }
}


void ip_lcd_test() {
    printf("lcd test\n");
#ifdef USE_QSPI0_DEV
    QSPI0_InitStruct_t qspi0 = {
        (uint32_t)0, 
        (uint32_t)0b0001, // fpga
        // (uint32_t)0b1000, // soc
        (uint32_t)0,
        (uint32_t)250,
        (uint32_t)140,
        (uint32_t)24,
        (uint32_t)10,
        (uint32_t)2,
    };
    qspi0_init(qspi0);
    // 1-1-1(tx data only)
    qspi0_xfer_config((uint32_t)0, (uint32_t)0, (uint32_t)1, // flush bit
                      (uint32_t)0, (uint32_t)0,
                      (uint32_t)0, (uint32_t)0,
                      (uint32_t)0,
                      (uint32_t)1, (uint32_t)1, (uint32_t)1
                     );
#else
    qspi1_init();
#endif

    lcd_init();
    // // lcd_wr_dc_cmd(0x01); // software reset
    // uint32_t pref_cnt = 0;
    // lcd_frame(1, pref_cnt);
    // for (int i = 0; i < 6; ++i) {
    //     lcd_fill_bg(0, 0, LCD_W, LCD_H, 0);
    //     lcd_fill_bg(0, 0, LCD_W, LCD_H, 1);
    //     lcd_fill_bg(0, 0, LCD_W, LCD_H, 2);
    //     pref_cnt += 3;
    // }
    // lcd_frame(0, pref_cnt);

#ifdef USE_QSPI0_DMA
    printf("enable dma\n");
#endif

    lcd_fill_video(0, 0, 48, 48, (uint32_t*)gImage_hello_file);
    delay_ms(1000);
    // lcd_fill_image(0, 0, 48, 48, (uint32_t*)gImage_hello_file);
    lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_chunyihongbao);
    lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_retro_spitft);
    // pref_cnt = 0;
    // lcd_frame(1, pref_cnt);
    // for (int i = 0; i < 16; ++i) {
        // lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_chunyihongbao);
        // lcd_fill_image(0, 0, 240, 135, (uint32_t*)image_data_retro_spitft);
        // pref_cnt += 2;
    // }
    // lcd_frame(0, pref_cnt);

    // for (int i = 0; i < 100; ++i)
    // {
    //     lcd_fill_video(0, 0, 240, 135, only_my_railgun[i]);
    //     pref_cnt += 1;
    // }
    // lcd_frame(0, pref_cnt);
}