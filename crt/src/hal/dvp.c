#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/lib/printf.h>

#define RS_DVP_CTRL_OFFSET            UINT32_C(0x000)
#define RS_DVP_RXDATA_OFFSET          UINT32_C(0x004)
#define RS_DVP_STATUS_OFFSET          UINT32_C(0x008)
#define RS_DVP_STREAM_CTRL_OFFSET     UINT32_C(0x00C)
#define RS_DVP_FORMAT_OFFSET          UINT32_C(0x010)
#define RS_DVP_SYNC_CFG_OFFSET        UINT32_C(0x014)
#define RS_DVP_FRAME_SIZE_OFFSET      UINT32_C(0x018)
#define RS_DVP_CROP_START_OFFSET      UINT32_C(0x01C)
#define RS_DVP_CROP_SIZE_OFFSET       UINT32_C(0x020)
#define RS_DVP_FRAME_COUNT_OFFSET     UINT32_C(0x024)
#define RS_DVP_LINE_COUNT_OFFSET      UINT32_C(0x028)
#define RS_DVP_PIXEL_COUNT_OFFSET     UINT32_C(0x02C)
#define RS_DVP_WORD_COUNT_OFFSET      UINT32_C(0x030)
#define RS_DVP_DROP_COUNT_OFFSET      UINT32_C(0x034)
#define RS_DVP_ERROR_STATUS_OFFSET    UINT32_C(0x038)
#define RS_DVP_INTR_STATE_OFFSET      UINT32_C(0x03C)
#define RS_DVP_INTR_ENABLE_OFFSET     UINT32_C(0x040)
#define RS_DVP_INTR_STATUS_OFFSET     UINT32_C(0x044)
#define RS_DVP_INTR_TEST_OFFSET       UINT32_C(0x048)
#define RS_DVP_COMMAND_OFFSET         UINT32_C(0x04C)
#define RS_DVP_VERSION_OFFSET         UINT32_C(0x0F8)
#define RS_DVP_CAPABILITY_OFFSET      UINT32_C(0x0FC)

#define RS_DVP_CTRL_ENABLE_MASK       UINT32_C(0x00000001)
#define RS_DVP_CTRL_SNAPSHOT_MASK     UINT32_C(0x00000002)
#define RS_DVP_CTRL_CROP_MASK         UINT32_C(0x00000004)
#define RS_DVP_COMMAND_ABORT_MASK     UINT32_C(0x00000001)
#define RS_DVP_COMMAND_FLUSH_MASK     UINT32_C(0x00000002)
#define RS_DVP_STATUS_ACTIVE_MASK     UINT32_C(0x00000002)
#define RS_DVP_STATUS_ENABLE_MASK     UINT32_C(0x00000001)
#define RS_DVP_STATUS_ERROR_MASK      UINT32_C(0x00000020)
#define RS_DVP_STATUS_FIFO_EMPTY_MASK UINT32_C(0x00000004)

#ifdef RS_SOC_TINY
#define RS_DVP_DMA_CHANNEL RS_DMA_CHANNEL_DVP
#else
#define RS_DVP_DMA_CHANNEL RS_DMA_CHANNEL_BULK
#endif

#ifndef RS_SOC_DVP_DMA_BURST_BEATS
#define RS_SOC_DVP_DMA_BURST_BEATS RS_DMA_MAX_BURST_BEATS
#endif

#ifdef RS_DVP_TEST_MMIO
uint32_t rs_dvp_test_read(uint32_t offset);
void rs_dvp_test_write(uint32_t offset, uint32_t value);
#endif

static uint32_t rs_dvp_read(uint32_t offset) {
#ifdef RS_DVP_TEST_MMIO
    return rs_dvp_test_read(offset);
#else
    return *(volatile uint32_t *)(RS_SOC_APB4_DVP_BASE + (uintptr_t)offset);
#endif
}

static void rs_dvp_write(uint32_t offset, uint32_t value) {
#ifdef RS_DVP_TEST_MMIO
    rs_dvp_test_write(offset, value);
#else
    *(volatile uint32_t *)(RS_SOC_APB4_DVP_BASE + (uintptr_t)offset) = value;
#endif
}

static rs_status_t rs_dvp_clear_errors(rs_timeout_t timeout) {
    if (rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET) == 0U) {
        return RS_OK;
    }
    rs_dvp_write(RS_DVP_ERROR_STATUS_OFFSET, UINT32_C(0x3F));
    while (timeout-- != 0U) {
        if (rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET) == 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_dvp_wait_disabled(rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        if ((rs_dvp_read(RS_DVP_STATUS_OFFSET) & RS_DVP_STATUS_ENABLE_MASK) == 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_dvp_rearm(rs_timeout_t timeout) {
    const uint32_t status = rs_dvp_read(RS_DVP_STATUS_OFFSET);
    if ((status & RS_DVP_STATUS_ACTIVE_MASK) != 0U ||
        (status & RS_DVP_STATUS_FIFO_EMPTY_MASK) == 0U ||
        rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET) != 0U) {
        return RS_EIO;
    }
    rs_dvp_write(RS_DVP_CTRL_OFFSET, rs_dvp_read(RS_DVP_CTRL_OFFSET) & ~RS_DVP_CTRL_ENABLE_MASK);
    return rs_dvp_wait_disabled(timeout);
}

static bool rs_dvp_config_valid(const rs_dvp_config_t *config) {
    if ((config == NULL) || ((uint32_t)config->format > (uint32_t)RS_DVP_FORMAT_YUV422) ||
        (config->frame_width == 0U) || (config->frame_height == 0U)) {
        return false;
    }
    if (config->crop_enable &&
        ((config->crop_width == 0U) || (config->crop_height == 0U) ||
         ((uint32_t)config->crop_x + config->crop_width > config->frame_width) ||
         ((uint32_t)config->crop_y + config->crop_height > config->frame_height))) {
        return false;
    }
    return true;
}

rs_status_t rs_dvp_probe(uint32_t *version, uint32_t *capability) {
    if ((version == NULL) || (capability == NULL))
        return RS_EINVAL;
    *version = rs_dvp_read(RS_DVP_VERSION_OFFSET);
    *capability = rs_dvp_read(RS_DVP_CAPABILITY_OFFSET);
    return (*version == UINT32_C(0x00020000)) ? RS_OK : RS_EIO;
}

rs_status_t rs_dvp_configure(const rs_dvp_config_t *config) {
    uint32_t format;
    uint32_t sync;
    uint32_t control;

    if (!rs_dvp_config_valid(config))
        return RS_EINVAL;
    const rs_status_t stop = rs_dvp_abort();
    if (stop != RS_OK) {
        return stop;
    }
    format = (uint32_t)config->format;
    if (config->byte_swap)
        format |= UINT32_C(0x00000004);
    if (config->pixel_swap)
        format |= UINT32_C(0x00000008);
    sync = (config->vsync_active_low ? 1U : 0U) | (config->href_active_low ? 2U : 0U) |
           (config->pclk_falling ? 4U : 0U);
    control = (config->snapshot ? RS_DVP_CTRL_SNAPSHOT_MASK : 0U) |
              (config->crop_enable ? RS_DVP_CTRL_CROP_MASK : 0U);
    rs_dvp_write(RS_DVP_FORMAT_OFFSET, format);
    rs_dvp_write(RS_DVP_SYNC_CFG_OFFSET, sync);
    rs_dvp_write(RS_DVP_FRAME_SIZE_OFFSET,
                 ((uint32_t)config->frame_height << 16) | config->frame_width);
    rs_dvp_write(RS_DVP_CROP_START_OFFSET, ((uint32_t)config->crop_y << 16) | config->crop_x);
    rs_dvp_write(RS_DVP_CROP_SIZE_OFFSET,
                 ((uint32_t)config->crop_height << 16) | config->crop_width);
    rs_dvp_write(RS_DVP_STREAM_CTRL_OFFSET, config->stream_enable ? 1U : 0U);
    rs_dvp_write(RS_DVP_INTR_STATE_OFFSET, RS_DVP_INTERRUPT_ALL);
    rs_dvp_write(RS_DVP_CTRL_OFFSET, control);
    return RS_OK;
}

static rs_status_t rs_dvp_start_bounded(rs_timeout_t timeout) {
    const rs_status_t rearm = rs_dvp_rearm(timeout);
    if (rearm != RS_OK) {
        return rearm;
    }
    rs_dvp_write(RS_DVP_CTRL_OFFSET, rs_dvp_read(RS_DVP_CTRL_OFFSET) | RS_DVP_CTRL_ENABLE_MASK);
    while (timeout-- != 0U) {
        if ((rs_dvp_read(RS_DVP_STATUS_OFFSET) & RS_DVP_STATUS_ENABLE_MASK) != 0U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_dvp_start(void) {
    return rs_dvp_start_bounded(RS_TIMEOUT_DEFAULT);
}

rs_status_t rs_dvp_abort(void) {
    rs_dma_status_t dma_status;
    rs_timeout_t timeout = RS_TIMEOUT_DEFAULT;
    if (rs_dma_get_status(RS_DVP_DMA_CHANNEL, &dma_status) != RS_OK || dma_status.busy) {
        return RS_EIO;
    }
    if (rs_dvp_clear_errors(timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    rs_dvp_write(RS_DVP_COMMAND_OFFSET, RS_DVP_COMMAND_ABORT_MASK);
    while (timeout-- != 0U) {
        const uint32_t status = rs_dvp_read(RS_DVP_STATUS_OFFSET);
        if ((rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET) & RS_DVP_ERROR_ABORT) != 0U &&
            (status & RS_DVP_STATUS_ACTIVE_MASK) == 0U &&
            (status & RS_DVP_STATUS_FIFO_EMPTY_MASK) != 0U) {
            rs_dvp_write(RS_DVP_CTRL_OFFSET,
                         rs_dvp_read(RS_DVP_CTRL_OFFSET) & ~RS_DVP_CTRL_ENABLE_MASK);
            const rs_status_t clear = rs_dvp_clear_errors(RS_TIMEOUT_DEFAULT);
            return clear == RS_OK ? rs_dvp_wait_disabled(RS_TIMEOUT_DEFAULT) : clear;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_dvp_flush(void) {
    rs_dvp_write(RS_DVP_COMMAND_OFFSET, RS_DVP_COMMAND_FLUSH_MASK);
    return RS_OK;
}

rs_status_t rs_dvp_get_status(rs_dvp_status_t *status) {
    if (status == NULL)
        return RS_EINVAL;
    status->status = rs_dvp_read(RS_DVP_STATUS_OFFSET);
    status->active = (status->status & RS_DVP_STATUS_ACTIVE_MASK) != 0U;
    status->frame_count = rs_dvp_read(RS_DVP_FRAME_COUNT_OFFSET);
    status->line_count = rs_dvp_read(RS_DVP_LINE_COUNT_OFFSET);
    status->pixel_count = rs_dvp_read(RS_DVP_PIXEL_COUNT_OFFSET);
    status->word_count = rs_dvp_read(RS_DVP_WORD_COUNT_OFFSET);
    status->drop_count = rs_dvp_read(RS_DVP_DROP_COUNT_OFFSET);
    status->error_status = rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET);
    status->interrupt_state = rs_dvp_read(RS_DVP_INTR_STATE_OFFSET);
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_enable(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    rs_dvp_write(RS_DVP_INTR_ENABLE_OFFSET, mask);
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_clear(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    rs_dvp_write(RS_DVP_INTR_STATE_OFFSET, mask);
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_test(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    rs_dvp_write(RS_DVP_INTR_TEST_OFFSET, mask);
    return RS_OK;
}

static rs_status_t rs_dvp_dma_cleanup(uint32_t channel) {
    const rs_status_t status = rs_dma_abort_wait(channel, RS_TIMEOUT_DEFAULT);

    if (status != RS_OK) {
        return status;
    }
    return rs_dma_reset(channel);
}

static rs_status_t rs_dvp_cancel_dma(void) {
    const rs_status_t result = rs_dvp_dma_cleanup(RS_DVP_DMA_CHANNEL);
    return result == RS_OK ? rs_dvp_abort() : result;
}

static rs_status_t rs_dvp_layout(uintptr_t destination, uint32_t capacity, bool dma,
                                 uint32_t *words, uint32_t *pixels) {
    const uint32_t control = rs_dvp_read(RS_DVP_CTRL_OFFSET);
    const uint32_t size =
        rs_dvp_read((control & RS_DVP_CTRL_CROP_MASK) != 0U ? RS_DVP_CROP_SIZE_OFFSET
                                                            : RS_DVP_FRAME_SIZE_OFFSET);
    const uint32_t width = size & UINT32_C(0xFFFF);
    const uint32_t height = size >> 16;
    if (width == 0U || height == 0U || (control & RS_DVP_CTRL_SNAPSHOT_MASK) == 0U ||
        (dma && (width & 1U) != 0U) || destination == 0U ||
        (destination & (sizeof(uint32_t) - 1U)) != 0U) {
        return RS_EINVAL;
    }
    *words = ((width + 1U) / 2U) * height;
    *pixels = width * height;
    if (*words > UINT32_MAX / sizeof(uint32_t) || capacity < *words) {
        return RS_ENOSPC;
    }
    if (destination > (uintptr_t)UINT32_MAX ||
        destination > (uintptr_t)UINT32_MAX - (*words * sizeof(uint32_t) - 1U)) {
        return RS_EINVAL;
    }
    return RS_OK;
}

rs_status_t rs_dvp_capture_dma(uintptr_t destination, uint32_t word_capacity,
                               rs_timeout_t timeout) {
    rs_dma_config_t dma_config = {0};
    rs_dma_status_t dma_status;
    rs_dvp_status_t status;
    rs_status_t result;
    uint32_t words;
    uint32_t pixels;
    const uint32_t previous_frame = rs_dvp_read(RS_DVP_FRAME_COUNT_OFFSET);
    result = rs_dvp_layout(destination, word_capacity, true, &words, &pixels);
    if (result != RS_OK) {
        return result;
    }
    if (rs_dvp_read(RS_DVP_STREAM_CTRL_OFFSET) == 0U ||
        rs_dvp_read(RS_DVP_ERROR_STATUS_OFFSET) != 0U) {
        return RS_EIO;
    }
    (void)rs_dvp_interrupt_clear(RS_DVP_INTERRUPT_ALL);
    dma_config.kind = RS_DMA_KIND_STREAM_TO_MM;
    dma_config.request = RS_DMA_REQUEST_DVP_RX;
    dma_config.source = (uintptr_t)0U;
    dma_config.destination = destination;
    dma_config.byte_count = words * sizeof(uint32_t);
    dma_config.width = RS_DMA_WIDTH_32;
    dma_config.source_increment = false;
    dma_config.destination_increment = true;
    dma_config.priority = 3U;
    dma_config.burst_beats = RS_SOC_DVP_DMA_BURST_BEATS;
    result = rs_dma_configure(RS_DVP_DMA_CHANNEL, &dma_config);
    if (result != RS_OK) {
        // A rejected configure may belong to another owner: do not abort it.
        return RS_EIO;
    }
    result = rs_dma_start(RS_DVP_DMA_CHANNEL);
    if (result != RS_OK)
        return result;
    result = rs_dvp_start_bounded(timeout);
    if (result != RS_OK) {
        const rs_status_t cleanup = rs_dvp_cancel_dma();
        return cleanup == RS_OK ? result : cleanup;
    }
    while (timeout != 0U) {
        timeout--;
        if ((rs_dvp_get_status(&status) != RS_OK) ||
            (rs_dma_get_status(RS_DVP_DMA_CHANNEL, &dma_status) != RS_OK)) {
            result = rs_dvp_cancel_dma();
            return result == RS_OK ? RS_EIO : result;
        }
        if (status.error_status != 0U || dma_status.error || dma_status.aborted) {
            result = rs_dvp_cancel_dma();
            return result == RS_OK ? RS_EIO : result;
        }
        if ((status.interrupt_state & RS_DVP_INTERRUPT_FRAME_DONE) != 0U &&
            status.frame_count == previous_frame + 1U && !status.active) {
            if ((rs_dma_wait(RS_DVP_DMA_CHANNEL, timeout) != RS_OK) ||
                (rs_dma_get_status(RS_DVP_DMA_CHANNEL, &dma_status) != RS_OK) ||
                (rs_dvp_get_status(&status) != RS_OK) || dma_status.error || dma_status.aborted ||
                !dma_status.done || dma_status.remaining != 0U ||
                dma_status.bytes_done != dma_config.byte_count || status.error_status != 0U ||
                status.pixel_count != pixels || status.word_count != words ||
                (status.status & RS_DVP_STATUS_FIFO_EMPTY_MASK) == 0U) {
                result = rs_dvp_cancel_dma();
                return result == RS_OK ? RS_EIO : result;
            }
            return RS_OK;
        }
    }
    result = rs_dvp_cancel_dma();
    return result == RS_OK ? RS_ETIMEOUT : result;
}

rs_status_t rs_dvp_capture_pio(uintptr_t destination, uint32_t word_capacity,
                               uint32_t expected_words, rs_timeout_t timeout) {
    rs_dvp_status_t status;
    rs_dma_status_t dma_status;
    uint32_t words = 0U;
    uint32_t layout_words;
    uint32_t pixels;
    if (rs_dma_get_status(RS_DVP_DMA_CHANNEL, &dma_status) != RS_OK || dma_status.busy ||
        dma_status.suspended) {
        return RS_EIO;
    }
    const uint32_t previous_frame = rs_dvp_read(RS_DVP_FRAME_COUNT_OFFSET);
    const rs_status_t layout =
        rs_dvp_layout(destination, word_capacity, false, &layout_words, &pixels);
    if (layout != RS_OK) {
        return layout;
    }
    if (expected_words != layout_words) {
        return RS_EINVAL;
    }
    const rs_status_t rearm = rs_dvp_rearm(timeout);
    if (rearm != RS_OK)
        return rearm;
    rs_dvp_write(RS_DVP_STREAM_CTRL_OFFSET, 0U);
    (void)rs_dvp_interrupt_clear(RS_DVP_INTERRUPT_ALL);
    const rs_status_t start = rs_dvp_start_bounded(timeout);
    if (start != RS_OK)
        return start;
    while (timeout-- != 0U) {
        if (rs_dvp_get_status(&status) != RS_OK || status.error_status != 0U) {
            (void)rs_dvp_abort();
            return RS_EIO;
        }
        if ((status.status & RS_DVP_STATUS_FIFO_EMPTY_MASK) == 0U) {
            if (words >= expected_words) {
                (void)rs_dvp_abort();
                return RS_ENOSPC;
            }
            ((volatile uint32_t *)(uintptr_t)destination)[words] =
                rs_dvp_read(RS_DVP_RXDATA_OFFSET);
            words++;
        }
        if (((status.interrupt_state & RS_DVP_INTERRUPT_FRAME_DONE) != 0U) &&
            status.frame_count == previous_frame + 1U && (words == expected_words) &&
            !status.active) {
            if ((rs_dvp_read(RS_DVP_STATUS_OFFSET) & RS_DVP_STATUS_FIFO_EMPTY_MASK) != 0U &&
                status.pixel_count == pixels && status.word_count == expected_words) {
                return RS_OK;
            }
        }
    }
    (void)rs_dvp_abort();
    return RS_ETIMEOUT;
}

void ip_dvp_test(void) {
    uint32_t version;
    uint32_t capability;
    printf("dvp test\n");
    if (rs_dvp_probe(&version, &capability) == RS_OK) {
        printf("dvp v%lx capability %lx\n", (unsigned long)version, (unsigned long)capability);
    } else {
        printf("dvp probe failed\n");
    }
}
