#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/ws2812.h>
#include <retrosoc/lib/printf.h>

#define RS_WS2812_CTRL_START          UINT32_C(0x01)
#define RS_WS2812_CTRL_ABORT          UINT32_C(0x02)
#define RS_WS2812_CTRL_FIFO_FLUSH     UINT32_C(0x04)
#define RS_WS2812_STATUS_BUSY         UINT32_C(0x01)
#define RS_WS2812_STATUS_FIFO_EMPTY   UINT32_C(0x02)
#define RS_WS2812_STATUS_FIFO_FULL    UINT32_C(0x04)
#define RS_WS2812_STATUS_CONFIG_VALID UINT32_C(0x08)
#define RS_WS2812_STATUS_RESET_ACTIVE UINT32_C(0x10)
#define RS_WS2812_IP_FIFO_DEPTH_SHIFT 16U
#define RS_WS2812_IP_FIFO_DEPTH_MASK  UINT32_C(0xFF)
#define RS_WS2812_PIXEL_MASK          UINT32_C(0x00FFFFFF)
#define RS_WS2812_DMA_SOFTWARE_MODE   UINT32_C(0)
static uint32_t rs_ws2812_fifo_depth(void) {
    return (reg_ws2812_ip_info >> RS_WS2812_IP_FIFO_DEPTH_SHIFT) & RS_WS2812_IP_FIFO_DEPTH_MASK;
}

static rs_status_t rs_ws2812_prepare(const uint32_t *pixels, size_t pixel_count,
                                     size_t *preloaded) {
    uint32_t fifo_depth;
    size_t preload_count;

    if ((pixels == NULL) || (pixel_count == 0U) || (pixel_count > UINT32_MAX) ||
        (preloaded == NULL)) {
        return RS_EINVAL;
    }
    for (size_t index = 0U; index < pixel_count; ++index) {
        if ((pixels[index] & ~RS_WS2812_PIXEL_MASK) != 0U) {
            return RS_EINVAL;
        }
    }
    if ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }

    fifo_depth = rs_ws2812_fifo_depth();
    if (fifo_depth == 0U) {
        return RS_EIO;
    }
    reg_ws2812_ctrl = RS_WS2812_CTRL_FIFO_FLUSH;
    reg_ws2812_error_status =
        RS_WS2812_ERROR_CONFIG | RS_WS2812_ERROR_UNDERFLOW | RS_WS2812_ERROR_COMMAND;
    reg_ws2812_intr_state = RS_WS2812_INTR_ALL;
    preload_count = pixel_count < (size_t)fifo_depth ? pixel_count : (size_t)fifo_depth;
    for (size_t index = 0U; index < preload_count; ++index) {
        reg_ws2812_txdata = pixels[index];
    }
    *preloaded = preload_count;
    return RS_OK;
}

rs_status_t rs_ws2812_init(const rs_ws2812_config_t *config) {
    rs_ws2812_timing_t timing;
    uint32_t fifo_depth;

    if (rs_ws2812_timing_from_ns(config, &timing) != RS_OK) {
        return RS_EINVAL;
    }
    fifo_depth = rs_ws2812_fifo_depth();
    if ((fifo_depth == 0U) || (config->fifo_watermark >= fifo_depth)) {
        return RS_EINVAL;
    }
    if ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }

    reg_ws2812_ctrl = RS_WS2812_CTRL_FIFO_FLUSH;
    reg_ws2812_error_status =
        RS_WS2812_ERROR_CONFIG | RS_WS2812_ERROR_UNDERFLOW | RS_WS2812_ERROR_COMMAND;
    reg_ws2812_intr_state = RS_WS2812_INTR_ALL;
    reg_ws2812_bit_cycles = timing.bit_cycles;
    reg_ws2812_t0h_cycles = timing.t0h_cycles;
    reg_ws2812_t1h_cycles = timing.t1h_cycles;
    reg_ws2812_reset_cycles = timing.reset_cycles;
    reg_ws2812_fifo_watermark = config->fifo_watermark;
    return ((reg_ws2812_status & RS_WS2812_STATUS_CONFIG_VALID) != 0U) ? RS_OK : RS_EIO;
}

rs_status_t rs_ws2812_get_status(rs_ws2812_status_t *status) {
    uint32_t value;

    if (status == NULL) {
        return RS_EINVAL;
    }
    value = reg_ws2812_status;
    status->fifo_level = reg_ws2812_fifo_level;
    status->remaining_words = reg_ws2812_remaining_words;
    status->error_status = reg_ws2812_error_status;
    status->interrupt_state = reg_ws2812_intr_state;
    status->busy = (value & RS_WS2812_STATUS_BUSY) != 0U;
    status->fifo_empty = (value & RS_WS2812_STATUS_FIFO_EMPTY) != 0U;
    status->fifo_full = (value & RS_WS2812_STATUS_FIFO_FULL) != 0U;
    status->config_valid = (value & RS_WS2812_STATUS_CONFIG_VALID) != 0U;
    status->reset_active = (value & RS_WS2812_STATUS_RESET_ACTIVE) != 0U;
    return RS_OK;
}

rs_status_t rs_ws2812_push(uint32_t pixel, rs_timeout_t timeout) {
    uint32_t status;

    if ((pixel & ~RS_WS2812_PIXEL_MASK) != 0U) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        status = reg_ws2812_status;
        if ((reg_ws2812_error_status & RS_WS2812_ERROR_UNDERFLOW) != 0U) {
            return RS_EIO;
        }
        if ((status & RS_WS2812_STATUS_FIFO_FULL) == 0U) {
            reg_ws2812_txdata = pixel;
            return RS_OK;
        }
        if ((status & RS_WS2812_STATUS_BUSY) == 0U) {
            return RS_ENOSPC;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_ws2812_start(uint32_t pixel_count) {
    if ((pixel_count == 0U) || ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) != 0U)) {
        return RS_EINVAL;
    }
    reg_ws2812_frame_words = pixel_count;
    reg_ws2812_ctrl = RS_WS2812_CTRL_START;
    if ((reg_ws2812_error_status & (RS_WS2812_ERROR_CONFIG | RS_WS2812_ERROR_COMMAND)) != 0U) {
        return RS_EIO;
    }
    return ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) != 0U) ? RS_OK : RS_EIO;
}

rs_status_t rs_ws2812_wait(rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        const uint32_t interrupt_state = reg_ws2812_intr_state;
        if ((interrupt_state & RS_WS2812_INTR_ERROR) != 0U) {
            return RS_EIO;
        }
        if ((interrupt_state & RS_WS2812_INTR_ABORTED) != 0U) {
            reg_ws2812_intr_state = RS_WS2812_INTR_ABORTED;
            return RS_EIO;
        }
        if ((interrupt_state & RS_WS2812_INTR_DONE) != 0U) {
            reg_ws2812_intr_state = RS_WS2812_INTR_DONE;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_ws2812_abort(rs_timeout_t timeout) {
    if ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) == 0U) {
        return RS_OK;
    }
    reg_ws2812_ctrl = RS_WS2812_CTRL_ABORT;
    while (timeout-- != 0U) {
        if ((reg_ws2812_status & RS_WS2812_STATUS_BUSY) == 0U) {
            reg_ws2812_intr_state = RS_WS2812_INTR_ABORTED;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_ws2812_irq_enable(uint32_t mask) {
    if ((mask & ~RS_WS2812_INTR_ALL) != 0U) {
        return RS_EINVAL;
    }
    reg_ws2812_intr_enable = mask;
    return RS_OK;
}

rs_status_t rs_ws2812_irq_ack(uint32_t mask) {
    if ((mask & ~RS_WS2812_INTR_ALL) != 0U) {
        return RS_EINVAL;
    }
    reg_ws2812_intr_state = mask;
    return RS_OK;
}

rs_status_t rs_ws2812_write(const uint32_t *pixels, size_t pixel_count, rs_timeout_t timeout) {
    size_t preloaded;
    rs_status_t status;

    status = rs_ws2812_prepare(pixels, pixel_count, &preloaded);
    if (status != RS_OK) {
        return status;
    }
    status = rs_ws2812_start((uint32_t)pixel_count);
    if (status != RS_OK) {
        return status;
    }
    for (size_t index = preloaded; index < pixel_count; ++index) {
        status = rs_ws2812_push(pixels[index], timeout);
        if (status != RS_OK) {
            (void)rs_ws2812_abort(timeout);
            return status;
        }
    }
    return rs_ws2812_wait(timeout);
}

rs_status_t rs_ws2812_write_dma(const uint32_t *pixels, size_t pixel_count, rs_timeout_t timeout) {
    size_t preloaded;
    size_t dma_words;
    rs_status_t status;

    status = rs_ws2812_prepare(pixels, pixel_count, &preloaded);
    if (status != RS_OK) {
        return status;
    }
    dma_words = pixel_count - preloaded;
    if (dma_words != 0U) {
        status = rs_dma_config(RS_WS2812_DMA_SOFTWARE_MODE, (uintptr_t)&pixels[preloaded], 1U,
                               (uintptr_t)&reg_ws2812_txdata, 0U, (uint32_t)dma_words);
        if (status != RS_OK) {
            return status;
        }
    }
    status = rs_ws2812_start((uint32_t)pixel_count);
    if (status != RS_OK) {
        return status;
    }
    if (dma_words != 0U) {
        status = rs_dma_start();
        if (status == RS_OK) {
            status = rs_dma_wait(timeout);
        }
        if (status != RS_OK) {
            (void)rs_ws2812_abort(timeout);
            return status;
        }
    }
    return rs_ws2812_wait(timeout);
}

void ip_ws2812_test(int argc, char **argv) {
    const rs_ws2812_config_t config = {
        CPU_FREQ * UINT32_C(1000000), RS_WS2812_DEFAULT_BIT_PERIOD_NS, RS_WS2812_DEFAULT_T0H_NS,
        RS_WS2812_DEFAULT_T1H_NS,     RS_WS2812_DEFAULT_RESET_NS,      4U,
    };
    const uint32_t pixels[] = {
        rs_ws2812_pack_grb(0x20U, 0x00U, 0x00U),
        rs_ws2812_pack_grb(0x00U, 0x20U, 0x00U),
        rs_ws2812_pack_grb(0x00U, 0x00U, 0x20U),
        rs_ws2812_pack_grb(0x10U, 0x10U, 0x10U),
    };
    const rs_gpio_config_t gpio_config = {
        .mode = RS_GPIO_MODE_ALT1,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
        .open_drain = false,
        .input_cmos = false,
        .filter_enable = false,
        .interrupt_enable = false,
    };

    (void)argc;
    (void)argv;
    printf("ws2812 test\n");
    if ((rs_gpio_configure(2U, &gpio_config) != RS_OK) || (rs_ws2812_init(&config) != RS_OK) ||
        (rs_ws2812_write(pixels, sizeof(pixels) / sizeof(pixels[0]), RS_TIMEOUT_DEFAULT) !=
         RS_OK)) {
        printf("ws2812 transfer failed\n");
        return;
    }
    printf("ws2812 test passed\n");
}
