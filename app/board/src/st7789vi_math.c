#include <stddef.h>

#include <retrosoc/board/st7789vi.h>

static const uint16_t rs_st7789vi_bars[8] = {
    UINT16_C(0xFFFF), UINT16_C(0xFFE0), UINT16_C(0x07FF), UINT16_C(0x07E0),
    UINT16_C(0xF81F), UINT16_C(0xF800), UINT16_C(0x001F), UINT16_C(0x0000),
};

static uint32_t rs_st7789vi_clamp(uint32_t value, uint32_t limit) {
    return (value > limit) ? limit : value;
}

uint16_t rs_st7789vi_pattern(uint32_t stage, uint32_t row, uint32_t col) {
    uint32_t red5;
    uint32_t green6;
    uint32_t blue5;

    switch (stage) {
    case RS_ST7789VI_STAGE_BARS:
        return rs_st7789vi_bars[rs_st7789vi_clamp(col / 40U, 7U)];
    case RS_ST7789VI_STAGE_GRADIENT:
    case RS_ST7789VI_STAGE_ABORT:
        red5 = rs_st7789vi_clamp(col >> 3U, 31U);
        green6 = rs_st7789vi_clamp(row >> 2U, 63U);
        blue5 = rs_st7789vi_clamp((row + col) >> 4U, 31U);
        return (uint16_t)((red5 << 11U) | (green6 << 5U) | blue5);
    case RS_ST7789VI_STAGE_ODD_A:
        return ((row + col) & 1U) != 0U ? UINT16_C(0xFFFF) : UINT16_C(0x0000);
    case RS_ST7789VI_STAGE_ODD_B:
        return UINT16_C(0x07E0);
    case RS_ST7789VI_STAGE_ODD_C:
        return UINT16_C(0xFFE0);
    case RS_ST7789VI_STAGE_ROTATION:
        red5 = col & 31U;
        green6 = row & 63U;
        blue5 = (row ^ col) & 31U;
        return (uint16_t)((red5 << 11U) | (green6 << 5U) | blue5);
    case RS_ST7789VI_STAGE_FINAL:
        return UINT16_C(0xFFFF);
    default:
        return UINT16_C(0x0000);
    }
}

rs_status_t rs_st7789vi_window_cells(const rs_st7789vi_window_t *window, uint32_t *pixels,
                                     uint32_t *bytes, uint32_t *words) {
    uint32_t width;
    uint32_t height;
    uint32_t count;

    if ((window == NULL) || (pixels == NULL) || (bytes == NULL) || (words == NULL)) {
        return RS_EINVAL;
    }
    if ((window->x1 < window->x0) || (window->y1 < window->y0) ||
        (window->x1 >= RS_ST7789VI_WIDTH) || (window->y1 >= RS_ST7789VI_HEIGHT)) {
        return RS_EINVAL;
    }
    width = (uint32_t)window->x1 - (uint32_t)window->x0 + 1U;
    height = (uint32_t)window->y1 - (uint32_t)window->y0 + 1U;
    count = width * height;
    *pixels = count;
    *bytes = count * 2U;
    *words = (count + 1U) / 2U;
    return RS_OK;
}
