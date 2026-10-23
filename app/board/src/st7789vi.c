#include <stddef.h>

#include <retrosoc/board/st7789vi.h>
#include <retrosoc/hal/clint.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/spi.h>

#define RS_ST7789VI_PIN_DC UINT32_C(30)

#ifdef RS_ST7789VI_QUICK
#define RS_ST7789VI_DELAY_RESET_MS  UINT32_C(1)
#define RS_ST7789VI_DELAY_SLPOUT_MS UINT32_C(1)
#define RS_ST7789VI_DELAY_DISPON_MS UINT32_C(1)
#else
#define RS_ST7789VI_DELAY_RESET_MS  UINT32_C(120)
#define RS_ST7789VI_DELAY_SLPOUT_MS UINT32_C(120)
#define RS_ST7789VI_DELAY_DISPON_MS UINT32_C(20)
#endif

#define RS_ST7789VI_CMD_SWRESET UINT8_C(0x01)
#define RS_ST7789VI_CMD_SLPOUT  UINT8_C(0x11)
#define RS_ST7789VI_CMD_NORON   UINT8_C(0x13)
#define RS_ST7789VI_CMD_INVON   UINT8_C(0x21)
#define RS_ST7789VI_CMD_DISPON  UINT8_C(0x29)
#define RS_ST7789VI_CMD_CASET   UINT8_C(0x2A)
#define RS_ST7789VI_CMD_RASET   UINT8_C(0x2B)
#define RS_ST7789VI_CMD_RAMWR   UINT8_C(0x2C)
#define RS_ST7789VI_CMD_MADCTL  UINT8_C(0x36)
#define RS_ST7789VI_CMD_COLMOD  UINT8_C(0x3A)

static rs_status_t rs_st7789vi_wait_clean(rs_timeout_t timeout) {
    rs_spi_status_t status;

    while (timeout-- != 0U) {
        if (rs_spi_get_status(&status) != RS_OK) {
            return RS_EIO;
        }
        if ((status.status & ((UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN) |
                              (UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE))) ==
            ((UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN) |
             (UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE))) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_st7789vi_set_dc(bool data) {
    bool level = false;
    if (rs_gpio_write(RS_ST7789VI_PIN_DC, data) != RS_OK) {
        return RS_EIO;
    }
    if (rs_gpio_read(RS_ST7789VI_PIN_DC, &level) != RS_OK) {
        return RS_EIO;
    }
    return (level == data) ? RS_OK : RS_EIO;
}

static rs_status_t rs_st7789vi_push_bytes(const uint8_t *bytes, uint32_t count, bool hold_cs,
                                          rs_timeout_t timeout) {
    const rs_spi_segment_t segment = {
        .frames = count,
        .direction = RS_SPI_DIRECTION_TX_ONLY,
        .frame16 = false,
        .hold_cs = hold_cs,
        .dummy = UINT16_C(0xFFFF),
    };
    uint32_t word = 0U;
    uint32_t index;
    rs_status_t status;

    if ((bytes == NULL) || (count == 0U)) {
        return RS_EINVAL;
    }
    status = rs_spi_arm(&segment);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_start(timeout);
    if (status != RS_OK) {
        return status;
    }
    for (index = 0U; index < count; index += 4U) {
        uint32_t lane;
        word = 0U;
        for (lane = 0U; lane < 4U; lane++) {
            uint32_t value = 0U;
            if ((index + lane) < count) {
                value = bytes[index + lane];
            }
            word |= value << (lane * 8U);
        }
        status = rs_spi_transfer_cpu(&word, NULL, 1U, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    (void)hold_cs;
    return rs_st7789vi_wait_clean(timeout);
}

static rs_status_t rs_st7789vi_command(uint8_t command, const uint8_t *params, uint32_t param_count,
                                       rs_timeout_t timeout) {
    rs_status_t status;

    status = rs_st7789vi_set_dc(false);
    if (status != RS_OK) {
        return status;
    }
    status = rs_st7789vi_push_bytes(&command, 1U, param_count != 0U, timeout);
    if (status != RS_OK) {
        return status;
    }
    if (param_count == 0U) {
        return rs_st7789vi_wait_clean(timeout);
    }
    status = rs_st7789vi_set_dc(true);
    if (status != RS_OK) {
        return status;
    }
    return rs_st7789vi_push_bytes(params, param_count, false, timeout);
}

static rs_status_t rs_st7789vi_delay_ms(uint32_t ms) {
    uint64_t start;
    uint64_t now;
    uint64_t limit;

    if (rs_clint_get_time(&start) != RS_OK) {
        return RS_EIO;
    }
    limit = start + (uint64_t)ms * UINT64_C(1000);
    for (;;) {
        if (rs_clint_get_time(&now) != RS_OK) {
            return RS_EIO;
        }
        if (now >= limit) {
            return RS_OK;
        }
    }
}

rs_status_t rs_st7789vi_init(uint8_t rotation) {
    const uint8_t colmod = UINT8_C(0x05);
    const rs_timeout_t timeout = UINT32_C(1000000);
    rs_status_t status;

    status = rs_st7789vi_command(RS_ST7789VI_CMD_SWRESET, NULL, 0U, timeout);
    if (status == RS_OK) {
        status = rs_st7789vi_delay_ms(RS_ST7789VI_DELAY_RESET_MS);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_command(RS_ST7789VI_CMD_SLPOUT, NULL, 0U, timeout);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_delay_ms(RS_ST7789VI_DELAY_SLPOUT_MS);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_command(RS_ST7789VI_CMD_COLMOD, &colmod, 1U, timeout);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_set_rotation(rotation);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_command(RS_ST7789VI_CMD_INVON, NULL, 0U, timeout);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_command(RS_ST7789VI_CMD_NORON, NULL, 0U, timeout);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_command(RS_ST7789VI_CMD_DISPON, NULL, 0U, timeout);
    }
    if (status == RS_OK) {
        status = rs_st7789vi_delay_ms(RS_ST7789VI_DELAY_DISPON_MS);
    }
    return status;
}

rs_status_t rs_st7789vi_set_rotation(uint8_t madctl) {
    return rs_st7789vi_command(RS_ST7789VI_CMD_MADCTL, &madctl, 1U, UINT32_C(1000000));
}

rs_status_t rs_st7789vi_begin_pixels(const rs_st7789vi_window_t *window, rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t bytes;
    uint32_t words;
    rs_status_t status;
    uint8_t address[4];
    rs_spi_segment_t data_segment = {
        .frames = 0U,
        .direction = RS_SPI_DIRECTION_TX_ONLY,
        .frame16 = true,
        .hold_cs = false,
        .dummy = UINT16_C(0xFFFF),
    };

    status = rs_st7789vi_window_cells(window, &pixels, &bytes, &words);
    if (status != RS_OK) {
        return status;
    }
    address[0] = (uint8_t)(window->x0 >> 8U);
    address[1] = (uint8_t)window->x0;
    address[2] = (uint8_t)(window->x1 >> 8U);
    address[3] = (uint8_t)window->x1;
    status = rs_st7789vi_command(RS_ST7789VI_CMD_CASET, address, 4U, timeout);
    if (status != RS_OK) {
        return status;
    }
    address[0] = (uint8_t)(window->y0 >> 8U);
    address[1] = (uint8_t)window->y0;
    address[2] = (uint8_t)(window->y1 >> 8U);
    address[3] = (uint8_t)window->y1;
    status = rs_st7789vi_command(RS_ST7789VI_CMD_RASET, address, 4U, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_st7789vi_set_dc(false);
    if (status != RS_OK) {
        return status;
    }
    status = rs_st7789vi_push_bytes(&(uint8_t){RS_ST7789VI_CMD_RAMWR}, 1U, true, timeout);
    if (status != RS_OK) {
        return status;
    }
    status = rs_st7789vi_set_dc(true);
    if (status != RS_OK) {
        return status;
    }
    data_segment.frames = pixels;
    status = rs_spi_arm(&data_segment);
    if (status != RS_OK) {
        return status;
    }
    return rs_spi_start(timeout);
}

rs_status_t rs_st7789vi_fill_window(const rs_st7789vi_window_t *window, uint32_t stage,
                                    uint32_t *workspace, uint32_t workspace_words,
                                    rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t bytes;
    uint32_t words;
    uint32_t produced = 0U;
    rs_status_t status;
    uint32_t width;

    status = rs_st7789vi_window_cells(window, &pixels, &bytes, &words);
    if ((status != RS_OK) || (workspace == NULL) || (workspace_words == 0U)) {
        return RS_EINVAL;
    }
    status = rs_st7789vi_begin_pixels(window, timeout);
    if (status != RS_OK) {
        return status;
    }
    width = (uint32_t)window->x1 - (uint32_t)window->x0 + 1U;
    while (produced < words) {
        uint32_t chunk = words - produced;
        uint32_t index;
        uint32_t first_pixel;
        if (chunk > workspace_words) {
            chunk = workspace_words;
        }
        first_pixel = produced * 2U;
        for (index = 0U; index < chunk; index++) {
            uint32_t pair = first_pixel + (index * 2U);
            uint32_t row = window->y0 + (pair / width);
            uint32_t col = window->x0 + (pair % width);
            uint32_t lo = rs_st7789vi_pattern(stage, row, col);
            uint32_t hi = 0U;
            if ((pair + 1U) < pixels) {
                uint32_t nrow = window->y0 + ((pair + 1U) / width);
                uint32_t ncol = window->x0 + ((pair + 1U) % width);
                hi = rs_st7789vi_pattern(stage, nrow, ncol);
            }
            workspace[index] = lo | (hi << 16U);
        }
        status = rs_spi_transfer_cpu(workspace, NULL, chunk, timeout);
        if (status != RS_OK) {
            return status;
        }
        produced += chunk;
    }
    return rs_st7789vi_wait_clean(timeout);
}
