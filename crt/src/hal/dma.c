#include <retrosoc/core/wait.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/lib/printf.h>

static bool rs_dma_channel_valid(uint32_t channel) {
    return channel < RS_DMA_CHANNEL_COUNT;
}

rs_status_t rs_dma_configure(uint32_t channel, const rs_dma_config_t *config) {
    uint32_t channel_config;

    if (rs_dma_config_validate(channel, config) != RS_OK) {
        return RS_EINVAL;
    }
    if ((RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STATUS) & RS_DMA_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }

    channel_config = ((uint32_t)config->kind << RS_DMA_CH_CFG_KIND_SHIFT) |
                     ((uint32_t)config->width << RS_DMA_CH_CFG_WIDTH_SHIFT) |
                     ((uint32_t)config->priority << RS_DMA_CH_CFG_PRIORITY_SHIFT);
    if (config->source_increment) {
        channel_config |= RS_DMA_CH_CFG_SRC_INCREMENT;
    }
    if (config->destination_increment) {
        channel_config |= RS_DMA_CH_CFG_DST_INCREMENT;
    }
    if (config->crc_enable) {
        channel_config |= RS_DMA_CH_CFG_CRC_ENABLE;
    }
    if (config->crc_final) {
        channel_config |= RS_DMA_CH_CFG_CRC_FINAL;
    }

    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CFG) = channel_config;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_SRC_ADDR) = (uint32_t)config->source;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_DST_ADDR) = (uint32_t)config->destination;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_BYTE_COUNT) = config->byte_count;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_REQUEST_SEL) = (uint32_t)config->request;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_BURST_CFG) = (uint32_t)config->burst_beats;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CRC_EXPECTED) = config->crc_expected;
    return RS_OK;
}

rs_status_t rs_dma_submit_tcd(uint32_t channel, rs_dma_tcd_t *tcd, rs_timeout_t timeout) {
    return rs_dma_submit_tcd_chain(channel, tcd, UINT32_C(1), timeout);
}

rs_status_t rs_dma_submit_tcd_chain(uint32_t channel, rs_dma_tcd_t *first, uint32_t max_tcds,
                                    rs_timeout_t timeout) {
    rs_dma_tcd_t *current;
    uint32_t submitted;

    if ((first == NULL) || (max_tcds == UINT32_C(0)) || (channel >= RS_DMA_CHANNEL_COUNT)) {
        return RS_EINVAL;
    }
    current = first;
    submitted = UINT32_C(0);
    while ((current != NULL) && (submitted < max_tcds)) {
        rs_dma_config_t config;
        rs_dma_status_t status;
        rs_status_t result;
        uint32_t control;
        uint32_t burst;

        result = rs_dma_tcd_validate(channel, current);
        if (result != RS_OK) {
            return result;
        }
        control = current->control;
        burst = (control >> RS_DMA_TCD_BURST_SHIFT) & UINT32_C(0x1F);
        if (burst == UINT32_C(0)) {
            burst = RS_DMA_MAX_BURST_BEATS;
        }
        config.kind = (rs_dma_transfer_kind_t)((control >> RS_DMA_TCD_KIND_SHIFT) & UINT32_C(0x7));
        config.request = (rs_dma_request_t)((control >> RS_DMA_TCD_REQUEST_SHIFT) & UINT32_C(0xF));
        config.source = (uintptr_t)current->source;
        config.destination = (uintptr_t)current->destination;
        config.byte_count = current->byte_count;
        config.width = RS_DMA_WIDTH_32;
        config.source_increment = (control & RS_DMA_TCD_SRC_INC) != UINT32_C(0);
        config.destination_increment = (control & RS_DMA_TCD_DST_INC) != UINT32_C(0);
        config.crc_enable = (control & RS_DMA_TCD_CRC_ENABLE) != UINT32_C(0);
        config.crc_final = (control & RS_DMA_TCD_CRC_FINAL) != UINT32_C(0);
        config.crc_expected = current->crc_expected;
        config.priority = (uint8_t)((control >> RS_DMA_TCD_PRIORITY_SHIFT) & UINT32_C(0x3));
        config.burst_beats = (uint8_t)burst;
        result = rs_dma_configure(channel, &config);
        if (result != RS_OK) {
            return result;
        }
        RS_DMA_CH_REG(channel, RS_DMA_CH_REG_TCD_HEAD) = (uint32_t)(uintptr_t)current;
        RS_DMA_CH_REG(channel, RS_DMA_CH_REG_TCD_COUNT) = UINT32_C(1);
        __asm__ volatile("fence rw, rw" ::: "memory");
        result = rs_dma_start(channel);
        if (result != RS_OK) {
            return result;
        }
        result = rs_dma_wait(channel, timeout);
        if (result != RS_OK) {
            (void)rs_dma_get_status(channel, &status);
            current->status = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STATUS);
            current->bytes_done = status.bytes_done;
            current->crc_result = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CRC_RESULT);
            current->error_status = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_ERROR_STATUS);
            return result;
        }
        (void)rs_dma_get_status(channel, &status);
        current->status = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STATUS);
        current->bytes_done = status.bytes_done;
        current->crc_result = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CRC_RESULT);
        current->error_status = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_ERROR_STATUS);
        current = (rs_dma_tcd_t *)(uintptr_t)current->next_ptr;
        submitted++;
    }
    return (current == NULL) ? RS_OK : RS_EINVAL;
}

rs_status_t rs_dma_start(uint32_t channel) {
    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_EVENT_STATUS) = RS_DMA_EVENT_ALL;
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CTRL) = RS_DMA_CH_CTRL_START;
    return RS_OK;
}

rs_status_t rs_dma_suspend(uint32_t channel) {
    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CTRL) = RS_DMA_CH_CTRL_SUSPEND;
    return RS_OK;
}

rs_status_t rs_dma_resume(uint32_t channel) {
    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CTRL) = RS_DMA_CH_CTRL_RESUME;
    return RS_OK;
}

rs_status_t rs_dma_abort(uint32_t channel) {
    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CTRL) = RS_DMA_CH_CTRL_ABORT;
    return RS_OK;
}

rs_status_t rs_dma_abort_wait(uint32_t channel, rs_timeout_t timeout) {
    rs_dma_status_t status;
    rs_status_t result;

    result = rs_dma_abort(channel);
    while ((result == RS_OK) && (timeout-- != 0U)) {
        result = rs_dma_get_status(channel, &status);
        if ((result == RS_OK) && !status.busy) {
            return RS_OK;
        }
    }
    return (result == RS_OK) ? RS_ETIMEOUT : result;
}

rs_status_t rs_dma_reset(uint32_t channel) {
    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    if ((RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STATUS) & RS_DMA_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CTRL) = RS_DMA_CH_CTRL_RESET;
    return RS_OK;
}

rs_status_t rs_dma_get_status(uint32_t channel, rs_dma_status_t *status) {
    uint32_t flags;

    if (!rs_dma_channel_valid(channel) || (status == NULL)) {
        return RS_EINVAL;
    }
    flags = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STATUS);
    status->busy = (flags & RS_DMA_STATUS_BUSY) != 0U;
    status->suspended = (flags & RS_DMA_STATUS_SUSPENDED) != 0U;
    status->done = (flags & RS_DMA_STATUS_DONE) != 0U;
    status->aborted = (flags & RS_DMA_STATUS_ABORTED) != 0U;
    status->error = (flags & RS_DMA_STATUS_ERROR) != 0U;
    status->stream_last_seen = (flags & RS_DMA_STATUS_STREAM_LAST) != 0U;
    status->events = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_EVENT_STATUS);
    status->bytes_done = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_BYTES_DONE);
    status->remaining = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_REMAINING);
    status->stall_cycles =
        ((uint64_t)RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STALL_CYCLES_HI) << 32U) |
        RS_DMA_CH_REG(channel, RS_DMA_CH_REG_STALL_CYCLES_LO);
    status->crc_result = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_CRC_RESULT);
    return RS_OK;
}

rs_status_t rs_dma_wait(uint32_t channel, rs_timeout_t timeout) {
    rs_dma_status_t status;

    if (!rs_dma_channel_valid(channel)) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        if (rs_dma_get_status(channel, &status) != RS_OK) {
            return RS_EIO;
        }
        if (status.error || status.aborted) {
            return RS_EIO;
        }
        if (status.done) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_dma_get_error(uint32_t channel, rs_dma_error_t *error) {
    uint32_t status;

    if (!rs_dma_channel_valid(channel) || (error == NULL)) {
        return RS_EINVAL;
    }
    status = RS_DMA_CH_REG(channel, RS_DMA_CH_REG_ERROR_STATUS);
    error->code = status & RS_DMA_ERROR_CODE_MASK;
    error->response_code = (status & RS_DMA_ERROR_RESPONSE_MASK) >> RS_DMA_ERROR_RESPONSE_SHIFT;
    error->address = (uintptr_t)RS_DMA_CH_REG(channel, RS_DMA_CH_REG_ERROR_ADDR);
    error->read = (status & RS_DMA_ERROR_READ) != 0U;
    return ((status & RS_DMA_ERROR_CODE_MASK) == 0U) ? RS_OK : RS_EIO;
}

rs_status_t rs_dma_irq_enable(uint32_t channel_mask) {
    const uint32_t valid_mask = (UINT32_C(1) << RS_DMA_CHANNEL_COUNT) - UINT32_C(1);
    uint32_t channel;

    if ((channel_mask & ~valid_mask) != 0U) {
        return RS_EINVAL;
    }
    for (channel = 0U; channel < RS_DMA_CHANNEL_COUNT; channel++) {
        if ((channel_mask & (UINT32_C(1) << channel)) != 0U) {
            RS_DMA_CH_REG(channel, RS_DMA_CH_REG_EVENT_ENABLE) = RS_DMA_EVENT_ALL;
        }
    }
    RS_DMA_REG(RS_DMA_REG_IRQ_ENABLE) = channel_mask;
    return RS_OK;
}

rs_status_t rs_dma_irq_pending(uint32_t *channel_mask) {
    if (channel_mask == NULL) {
        return RS_EINVAL;
    }
    *channel_mask = RS_DMA_REG(RS_DMA_REG_IRQ_STATE);
    return RS_OK;
}

rs_status_t rs_dma_irq_clear(uint32_t channel_mask) {
    const uint32_t valid_mask = (UINT32_C(1) << RS_DMA_CHANNEL_COUNT) - UINT32_C(1);
    uint32_t channel;

    if ((channel_mask & ~valid_mask) != 0U) {
        return RS_EINVAL;
    }
    for (channel = 0U; channel < RS_DMA_CHANNEL_COUNT; channel++) {
        if ((channel_mask & (UINT32_C(1) << channel)) != 0U) {
            RS_DMA_CH_REG(channel, RS_DMA_CH_REG_EVENT_STATUS) = RS_DMA_EVENT_ALL;
        }
    }
    RS_DMA_REG(RS_DMA_REG_IRQ_STATE) = channel_mask;
    return RS_OK;
}

void ip_dma_test(void) {
    const rs_dma_config_t tx_config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_I2S_TX,
        .source = (uintptr_t)0x40000000U,
        .destination = (uintptr_t)0U,
        .byte_count = UINT32_C(512) * sizeof(uint32_t),
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 2U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };
    const rs_dma_config_t rx_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_I2S_RX,
        .source = (uintptr_t)0U,
        .destination = (uintptr_t)0x41000000U,
        .byte_count = UINT32_C(180) * sizeof(uint32_t),
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 2U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };

    printf("dma test\n");
    if ((rs_i2s_configure(&(rs_i2s_config_t){
             .loopback = false,
             .stream_tx = true,
             .stream_rx = false,
             .clock_prog = false,
             .preset = RS_I2S_PRESET_16B_48K,
             .bitmode_24 = false,
             .sclk_div = 0U,
             .lrck_div = 0U,
             .mclk_div = 0U,
             .upbound = 120U,
             .lowbound = 32U,
         }) != RS_OK) ||
        (rs_i2s_enable(true, false) != RS_OK) ||
        (rs_dma_configure(RS_DMA_CHANNEL_BULK, &tx_config) != RS_OK) ||
        (rs_dma_start(RS_DMA_CHANNEL_BULK) != RS_OK) ||
        (rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        printf("dma transmit failed\n");
        return;
    }
    if ((rs_i2s_disable() != RS_OK) ||
        (rs_i2s_configure(&(rs_i2s_config_t){
             .loopback = false,
             .stream_tx = false,
             .stream_rx = true,
             .clock_prog = false,
             .preset = RS_I2S_PRESET_16B_48K,
             .bitmode_24 = false,
             .sclk_div = 0U,
             .lrck_div = 0U,
             .mclk_div = 0U,
             .upbound = 120U,
             .lowbound = 32U,
         }) != RS_OK) ||
        (rs_i2s_enable(false, true) != RS_OK) ||
        (rs_dma_configure(RS_DMA_CHANNEL_BULK, &rx_config) != RS_OK) ||
        (rs_dma_start(RS_DMA_CHANNEL_BULK) != RS_OK) ||
        (rs_dma_wait(RS_DMA_CHANNEL_BULK, RS_TIMEOUT_DEFAULT) != RS_OK)) {
        printf("dma receive failed\n");
        (void)rs_i2s_disable();
        return;
    }
    (void)rs_i2s_disable();
    printf("dma test passed\n");
}
