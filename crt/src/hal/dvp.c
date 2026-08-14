#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/dvp.h>
#include <retrosoc/lib/printf.h>

#define RS_DVP_CTRL_OFFSET         UINT32_C(0x000)
#define RS_DVP_RXDATA_OFFSET       UINT32_C(0x004)
#define RS_DVP_STATUS_OFFSET       UINT32_C(0x008)
#define RS_DVP_STREAM_CTRL_OFFSET  UINT32_C(0x00C)
#define RS_DVP_FORMAT_OFFSET       UINT32_C(0x010)
#define RS_DVP_SYNC_CFG_OFFSET     UINT32_C(0x014)
#define RS_DVP_FRAME_SIZE_OFFSET   UINT32_C(0x018)
#define RS_DVP_CROP_START_OFFSET   UINT32_C(0x01C)
#define RS_DVP_CROP_SIZE_OFFSET    UINT32_C(0x020)
#define RS_DVP_FRAME_COUNT_OFFSET  UINT32_C(0x024)
#define RS_DVP_LINE_COUNT_OFFSET   UINT32_C(0x028)
#define RS_DVP_PIXEL_COUNT_OFFSET  UINT32_C(0x02C)
#define RS_DVP_WORD_COUNT_OFFSET   UINT32_C(0x030)
#define RS_DVP_DROP_COUNT_OFFSET   UINT32_C(0x034)
#define RS_DVP_ERROR_STATUS_OFFSET UINT32_C(0x038)
#define RS_DVP_INTR_STATE_OFFSET   UINT32_C(0x03C)
#define RS_DVP_INTR_ENABLE_OFFSET  UINT32_C(0x040)
#define RS_DVP_INTR_STATUS_OFFSET  UINT32_C(0x044)
#define RS_DVP_INTR_TEST_OFFSET    UINT32_C(0x048)
#define RS_DVP_COMMAND_OFFSET      UINT32_C(0x04C)
#define RS_DVP_VERSION_OFFSET      UINT32_C(0x0F8)
#define RS_DVP_CAPABILITY_OFFSET   UINT32_C(0x0FC)

#define RS_DVP_CTRL_ENABLE_MASK    UINT32_C(0x00000001)
#define RS_DVP_CTRL_SNAPSHOT_MASK  UINT32_C(0x00000002)
#define RS_DVP_CTRL_CROP_MASK      UINT32_C(0x00000004)
#define RS_DVP_COMMAND_ABORT_MASK  UINT32_C(0x00000001)
#define RS_DVP_COMMAND_FLUSH_MASK  UINT32_C(0x00000002)
#define RS_DVP_STATUS_ACTIVE_MASK  UINT32_C(0x00000001)
#define RS_DVP_STATUS_ERROR_MASK   UINT32_C(0x00000040)

static volatile uint32_t *rs_dvp_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_RIBP_DVP_BASE + (uintptr_t)offset);
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
    *version = *rs_dvp_register(RS_DVP_VERSION_OFFSET);
    *capability = *rs_dvp_register(RS_DVP_CAPABILITY_OFFSET);
    return (*version == UINT32_C(0x00020000)) ? RS_OK : RS_EIO;
}

rs_status_t rs_dvp_configure(const rs_dvp_config_t *config) {
    uint32_t format;
    uint32_t sync;
    uint32_t control;

    if (!rs_dvp_config_valid(config))
        return RS_EINVAL;
    (void)rs_dvp_abort();
    format = (uint32_t)config->format;
    if (config->byte_swap)
        format |= UINT32_C(0x00000004);
    if (config->pixel_swap)
        format |= UINT32_C(0x00000008);
    sync = (config->vsync_active_low ? 1U : 0U) | (config->href_active_low ? 2U : 0U) |
           (config->pclk_falling ? 4U : 0U);
    control = (config->snapshot ? RS_DVP_CTRL_SNAPSHOT_MASK : 0U) |
              (config->crop_enable ? RS_DVP_CTRL_CROP_MASK : 0U);
    *rs_dvp_register(RS_DVP_FORMAT_OFFSET) = format;
    *rs_dvp_register(RS_DVP_SYNC_CFG_OFFSET) = sync;
    *rs_dvp_register(RS_DVP_FRAME_SIZE_OFFSET) =
        ((uint32_t)config->frame_height << 16) | config->frame_width;
    *rs_dvp_register(RS_DVP_CROP_START_OFFSET) = ((uint32_t)config->crop_y << 16) | config->crop_x;
    *rs_dvp_register(RS_DVP_CROP_SIZE_OFFSET) =
        ((uint32_t)config->crop_height << 16) | config->crop_width;
    *rs_dvp_register(RS_DVP_STREAM_CTRL_OFFSET) = config->stream_enable ? 1U : 0U;
    *rs_dvp_register(RS_DVP_ERROR_STATUS_OFFSET) = RS_DVP_ERROR_OVERFLOW | RS_DVP_ERROR_SYNC |
                                                   RS_DVP_ERROR_SIZE | RS_DVP_ERROR_PARTIAL |
                                                   RS_DVP_ERROR_CONFIG | RS_DVP_ERROR_ABORT;
    *rs_dvp_register(RS_DVP_INTR_STATE_OFFSET) = RS_DVP_INTERRUPT_ALL;
    *rs_dvp_register(RS_DVP_CTRL_OFFSET) = control;
    return RS_OK;
}

rs_status_t rs_dvp_start(void) {
    *rs_dvp_register(RS_DVP_CTRL_OFFSET) |= RS_DVP_CTRL_ENABLE_MASK;
    return RS_OK;
}

rs_status_t rs_dvp_abort(void) {
    *rs_dvp_register(RS_DVP_COMMAND_OFFSET) = RS_DVP_COMMAND_ABORT_MASK;
    *rs_dvp_register(RS_DVP_CTRL_OFFSET) &= ~RS_DVP_CTRL_ENABLE_MASK;
    return RS_OK;
}

rs_status_t rs_dvp_flush(void) {
    *rs_dvp_register(RS_DVP_COMMAND_OFFSET) = RS_DVP_COMMAND_FLUSH_MASK;
    return RS_OK;
}

rs_status_t rs_dvp_get_status(rs_dvp_status_t *status) {
    if (status == NULL)
        return RS_EINVAL;
    status->status = *rs_dvp_register(RS_DVP_STATUS_OFFSET);
    status->active = (status->status & RS_DVP_STATUS_ACTIVE_MASK) != 0U;
    status->frame_count = *rs_dvp_register(RS_DVP_FRAME_COUNT_OFFSET);
    status->line_count = *rs_dvp_register(RS_DVP_LINE_COUNT_OFFSET);
    status->pixel_count = *rs_dvp_register(RS_DVP_PIXEL_COUNT_OFFSET);
    status->word_count = *rs_dvp_register(RS_DVP_WORD_COUNT_OFFSET);
    status->drop_count = *rs_dvp_register(RS_DVP_DROP_COUNT_OFFSET);
    status->error_status = *rs_dvp_register(RS_DVP_ERROR_STATUS_OFFSET);
    status->interrupt_state = *rs_dvp_register(RS_DVP_INTR_STATE_OFFSET);
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_enable(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_dvp_register(RS_DVP_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_clear(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_dvp_register(RS_DVP_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_dvp_interrupt_test(uint32_t mask) {
    if ((mask & ~RS_DVP_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_dvp_register(RS_DVP_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_dvp_capture_dma(uintptr_t destination, uint32_t word_capacity,
                               rs_timeout_t timeout) {
    rs_dvp_status_t status;
    if ((destination == 0U) || (word_capacity == 0U))
        return RS_EINVAL;
    if ((rs_dma_config(RS_DMA_MODE_DVP_RX, RS_SOC_RIBP_DVP_BASE, 0U, destination, 1U,
                       word_capacity) != RS_OK) ||
        (rs_dma_start() != RS_OK) || (rs_dvp_start() != RS_OK)) {
        return RS_EIO;
    }
    while (timeout-- != 0U) {
        if (rs_dvp_get_status(&status) != RS_OK)
            return RS_EIO;
        if ((status.error_status != 0U) ||
            ((status.interrupt_state & RS_DVP_INTERRUPT_FRAME_DONE) != 0U)) {
            (void)rs_dvp_abort();
            return (status.error_status == 0U) && (rs_dma_wait(timeout) == RS_OK) ? RS_OK : RS_EIO;
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
