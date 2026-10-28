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

static rs_status_t rs_st7789vi_prepare_pixels(const rs_st7789vi_window_t *window,
                                              rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t bytes;
    uint32_t words;
    rs_status_t status;
    uint8_t address[4];

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
    return rs_st7789vi_set_dc(true);
}

rs_status_t rs_st7789vi_begin_pixels(const rs_st7789vi_window_t *window, rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t bytes;
    uint32_t words;
    rs_status_t status;
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
    status = rs_st7789vi_prepare_pixels(window, timeout);
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

static rs_status_t rs_st7789vi_start_segment(const rs_st7789vi_window_t *window, uint32_t frames,
                                             rs_spi_dma_job_t *job, bool hold_cs, bool commands,
                                             rs_timeout_t timeout) {
    rs_spi_segment_t segment = {
        .frames = frames,
        .direction = RS_SPI_DIRECTION_TX_ONLY,
        .frame16 = true,
        .hold_cs = hold_cs,
        .dummy = UINT16_C(0xFFFF),
    };
    uint32_t window_pixels;
    uint32_t window_bytes;
    uint32_t window_words;
    uint32_t payload_bytes;
    uint32_t transport_words;
    uint32_t transport_bytes;
    rs_status_t status;

    if ((job == NULL) || (job->session == NULL) ||
        (rs_st7789vi_window_cells(window, &window_pixels, &window_bytes, &window_words) != RS_OK) ||
        (frames == 0U) || (frames > window_pixels) ||
        (rs_spi_transport_layout(frames, true, &payload_bytes, &transport_words,
                                 &transport_bytes) != RS_OK) ||
        (job->buffer == (uintptr_t)0U) ||
        ((job->buffer & (sizeof(uint32_t) - 1U)) != (uintptr_t)0U) ||
        (job->buffer > (uintptr_t)UINT32_MAX) || (job->capacity_bytes < transport_bytes) ||
        (job->buffer > (uintptr_t)UINT32_MAX - (uintptr_t)(transport_bytes - 1U))) {
        return RS_EINVAL;
    }
    job->direction = RS_SPI_DIRECTION_TX_ONLY;
    if (commands) {
        status = rs_st7789vi_prepare_pixels(window, timeout);
        if (status != RS_OK) {
            return status;
        }
    }
    status = rs_spi_dma_bind(job->session->channel, RS_SPI_DMA_UNBOUND);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_arm(&segment);
    if (status != RS_OK) {
        return status;
    }
    status = rs_spi_start(timeout);
    if (status != RS_OK) {
        return status;
    }
    return rs_spi_dma_start(job);
}

rs_status_t rs_st7789vi_start_buffer(const rs_st7789vi_window_t *window, rs_spi_dma_job_t *job,
                                     rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t words;

    if ((job == NULL) || (rs_st7789vi_buffer_layout(window, job->buffer, job->capacity_bytes,
                                                    &pixels, &words) != RS_OK)) {
        return RS_EINVAL;
    }
    return rs_st7789vi_start_segment(window, pixels, job, false, true, timeout);
}

static rs_status_t rs_st7789vi_wait_buffer(rs_spi_dma_job_t *job,
                                           rs_st7789vi_dma_measurement_t *measurement,
                                           rs_timeout_t timeout) {
    rs_spi_status_t spi_status;
    rs_dma_status_t dma_status;
    rs_status_t result;
    uint32_t previous_tx_stalls = 0U;
    uint32_t previous_rx_stalls = 0U;
    uint32_t tx_wait_start = 0U;
    uint32_t rx_wait_start = 0U;
    bool tx_waiting = false;
    bool rx_waiting = false;

    for (;;) {
        uint32_t tx_level;
        if (timeout-- == 0U) {
            return RS_ETIMEOUT;
        }
        if (rs_spi_get_status(&spi_status) != RS_OK) {
            return RS_EIO;
        }
        tx_level = spi_status.levels & UINT32_C(0xF);
        if (measurement != NULL) {
            if (tx_level < measurement->tx_fifo_min) {
                measurement->tx_fifo_min = tx_level;
            }
            if (tx_level > measurement->tx_fifo_max) {
                measurement->tx_fifo_max = tx_level;
            }
            if ((spi_status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_TX_WAIT)) != 0U) {
                uint32_t run;
                if (!tx_waiting) {
                    tx_waiting = true;
                    tx_wait_start = previous_tx_stalls;
                }
                run = spi_status.tx_stall_cycles - tx_wait_start;
                if (run > measurement->longest_tx_wait_cycles) {
                    measurement->longest_tx_wait_cycles = run;
                }
            } else {
                tx_waiting = false;
            }
            if ((spi_status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_RX_WAIT)) != 0U) {
                uint32_t run;
                if (!rx_waiting) {
                    rx_waiting = true;
                    rx_wait_start = previous_rx_stalls;
                }
                run = spi_status.rx_stall_cycles - rx_wait_start;
                if (run > measurement->longest_rx_wait_cycles) {
                    measurement->longest_rx_wait_cycles = run;
                }
            } else {
                rx_waiting = false;
            }
            previous_tx_stalls = spi_status.tx_stall_cycles;
            previous_rx_stalls = spi_status.rx_stall_cycles;
        }
        result = rs_dma_get_status(job->session->channel, &dma_status);
        if (result != RS_OK) {
            return result;
        }
        if (dma_status.error || dma_status.aborted) {
            return RS_EIO;
        }
        if (dma_status.done) {
            break;
        }
    }
    result = rs_spi_dma_wait(job, timeout);
    if (result != RS_OK) {
        return result;
    }
    if (rs_spi_get_status(&spi_status) != RS_OK) {
        return RS_EIO;
    }
    if (measurement != NULL) {
        measurement->chunks++;
        measurement->frames += spi_status.frames_done;
        measurement->payload_bytes += spi_status.payload_bytes;
        measurement->transport_words += spi_status.transport_words;
        measurement->tx_stall_cycles += spi_status.tx_stall_cycles;
        measurement->rx_stall_cycles += spi_status.rx_stall_cycles;
        measurement->tx_fifo_final = spi_status.levels & UINT32_C(0xF);
        measurement->clock_hz = spi_status.clock_hz;
        measurement->divider = spi_status.divider;
        measurement->dma_stall_cycles += dma_status.stall_cycles;
    }
    return RS_OK;
}

rs_status_t rs_st7789vi_display_buffer(const rs_st7789vi_window_t *window,
                                       const volatile uint32_t *source, uint32_t capacity_bytes,
                                       uint32_t *workspace, uint32_t workspace_words,
                                       rs_dma_session_t *session,
                                       rs_st7789vi_dma_measurement_t *measurement,
                                       rs_timeout_t timeout) {
    uint32_t pixels;
    uint32_t words;
    uint32_t produced = 0U;
    rs_status_t status;

    if ((session == NULL) ||
        (rs_st7789vi_buffer_layout(window, (uintptr_t)source, capacity_bytes, &pixels, &words) !=
         RS_OK) ||
        ((workspace == NULL) && (workspace_words != 0U)) ||
        ((workspace != NULL) &&
         ((workspace_words == 0U) ||
          (((uintptr_t)workspace & (sizeof(uint32_t) - 1U)) != (uintptr_t)0U) ||
          ((uintptr_t)workspace > (uintptr_t)UINT32_MAX)))) {
        return RS_EINVAL;
    }
    if (measurement != NULL) {
        *measurement = (rs_st7789vi_dma_measurement_t){.tx_fifo_min = 8U};
    }
    while (produced < words) {
        rs_spi_dma_job_t job = {
            .session = session,
            .direction = RS_SPI_DIRECTION_TX_ONLY,
        };
        uint32_t chunk = words - produced;
        uint32_t frames;
        bool held;
        if ((workspace != NULL) && (chunk > workspace_words)) {
            chunk = workspace_words;
        }
        frames = chunk * 2U;
        if ((produced + chunk) == words) {
            frames = pixels - (produced * 2U);
        }
        held = (produced + chunk) < words;
        if (workspace != NULL) {
            for (uint32_t index = 0U; index < chunk; ++index) {
                workspace[index] = source[produced + index];
            }
            job.buffer = (uintptr_t)workspace;
            job.capacity_bytes = chunk * sizeof(uint32_t);
        } else {
            job.buffer = (uintptr_t)(source + produced);
            job.capacity_bytes = capacity_bytes - (produced * sizeof(uint32_t));
        }
        status = rs_st7789vi_start_segment(window, frames, &job, held, produced == 0U, timeout);
        if (status != RS_OK) {
            return status;
        }
        status = rs_st7789vi_wait_buffer(&job, measurement, timeout);
        if (status != RS_OK) {
            return status;
        }
        produced += chunk;
    }
    return rs_spi_dma_bind(RS_SPI_DMA_UNBOUND, RS_SPI_DMA_UNBOUND);
}
