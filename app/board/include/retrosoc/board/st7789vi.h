#ifndef RETROSOC_BOARD_ST7789VI_H
#define RETROSOC_BOARD_ST7789VI_H

#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_ST7789VI_WIDTH            UINT16_C(320)
#define RS_ST7789VI_HEIGHT           UINT16_C(240)

/* Deterministic acceptance stages; the same geometry is recomputed by the
 * host checker, so every value here is part of the source-bound contract. */
#define RS_ST7789VI_STAGE_BARS       UINT32_C(1)
#define RS_ST7789VI_STAGE_GRADIENT   UINT32_C(2)
#define RS_ST7789VI_STAGE_ODD_A      UINT32_C(3)
#define RS_ST7789VI_STAGE_ODD_B      UINT32_C(4)
#define RS_ST7789VI_STAGE_ODD_C      UINT32_C(5)
#define RS_ST7789VI_STAGE_ROTATION   UINT32_C(6)
#define RS_ST7789VI_STAGE_FINAL      UINT32_C(7)
#define RS_ST7789VI_STAGE_ABORT      UINT32_C(8)

#define RS_ST7789VI_ROTATION_NORMAL  UINT8_C(0x00)
#define RS_ST7789VI_ROTATION_VARIANT UINT8_C(0x60)

typedef struct {
    uint16_t x0;
    uint16_t y0;
    uint16_t x1;
    uint16_t y1;
} rs_st7789vi_window_t;

uint16_t rs_st7789vi_pattern(uint32_t stage, uint32_t row, uint32_t col);
rs_status_t rs_st7789vi_window_cells(const rs_st7789vi_window_t *window, uint32_t *pixels,
                                     uint32_t *bytes, uint32_t *words);

rs_status_t rs_st7789vi_init(uint8_t rotation);
rs_status_t rs_st7789vi_set_rotation(uint8_t madctl);
rs_status_t rs_st7789vi_begin_pixels(const rs_st7789vi_window_t *window, rs_timeout_t timeout);
rs_status_t rs_st7789vi_fill_window(const rs_st7789vi_window_t *window, uint32_t stage,
                                    uint32_t *workspace, uint32_t workspace_words,
                                    rs_timeout_t timeout);

#endif
