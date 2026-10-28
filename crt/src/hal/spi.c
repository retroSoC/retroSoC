#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/spi.h>

#define RS_SPI_ROUTE_PIN_SCK  UINT32_C(27)
#define RS_SPI_ROUTE_PIN_MOSI UINT32_C(28)
#define RS_SPI_ROUTE_PIN_MISO UINT32_C(30)
#define RS_SPI_ROUTE_PIN_CS_N UINT32_C(31)

#if defined(RS_SOC_TINY) && defined(RS_SOC_APB4_SPI_BASE)
#define RS_SPI_TARGET_PRESENT 1
#define RS_SPI_REG(offset)    RS_SOC_REG32(RS_SOC_APB4_SPI_BASE, (offset))

static rs_status_t rs_spi_wait_status(uint32_t mask, bool set, rs_timeout_t timeout) {
    const uint32_t expected = set ? mask : 0U;
    while (timeout-- != 0U) {
        if ((RS_SPI_REG(RS_SPI_ABI_STATUS) & mask) == expected) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}
#endif

rs_status_t rs_spi_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability) {
    if ((ip_id == NULL) || (version == NULL) || (capability == NULL)) {
        return RS_EINVAL;
    }
#if defined(RS_SPI_TARGET_PRESENT) && defined(RS_SOC_HAS_SPI) && (RS_SOC_HAS_SPI != 0U)
    *ip_id = RS_SPI_REG(RS_SPI_ABI_IP_ID);
    *version = RS_SPI_REG(RS_SPI_ABI_IP_VERSION);
    *capability = RS_SPI_REG(RS_SPI_ABI_CAPABILITY);
    return (*ip_id == RS_SPI_ABI_ID_VALUE) ? RS_OK : RS_EIO;
#else
    *ip_id = 0U;
    *version = 0U;
    *capability = 0U;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_configure(const rs_spi_config_t *config) {
    if ((config == NULL) || (config->divider == 0U) || (config->divider > 65535U) ||
        (config->cs_setup == 0U) || (config->cs_hold == 0U) || (config->cs_inactive == 0U) ||
        (config->display_dc && config->miso_enable)) {
        return RS_EINVAL;
    }
#ifdef RS_SPI_TARGET_PRESENT
    RS_SPI_REG(RS_SPI_ABI_SESSION_CFG) =
        (config->cpol ? 1U : 0U) | (config->cpha ? 2U : 0U) | (config->lsb_first ? 4U : 0U) |
        (config->miso_enable ? 8U : 0U) | (config->display_dc ? 16U : 0U);
    RS_SPI_REG(RS_SPI_ABI_DIV) = config->divider;
    RS_SPI_REG(RS_SPI_ABI_CS_SETUP) = config->cs_setup;
    RS_SPI_REG(RS_SPI_ABI_CS_HOLD) = config->cs_hold;
    RS_SPI_REG(RS_SPI_ABI_CS_INACTIVE) = config->cs_inactive;
    return RS_OK;
#else
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_acquire(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_status_t result;
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_ENABLE;
    result = rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY, true, timeout);
    if (result != RS_OK) {
        return result;
    }
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_BUS_IDLE, true, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_release(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_status_t result =
        rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN, true, timeout);
    if (result != RS_OK)
        return result;
    rs_spi_status_t status;
    if (rs_spi_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if ((status.status & UINT32_C(0xF)) != UINT32_C(0x0)) {
        RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_DISABLE;
        result = rs_spi_wait_status(UINT32_C(0xF), false, timeout);
        if (result != RS_OK)
            return result;
    }
    const rs_gpio_config_t input = {
        .mode = RS_GPIO_MODE_INPUT,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = false,
    };
    if ((rs_gpio_configure(RS_SPI_ROUTE_PIN_SCK, &input) != RS_OK) ||
        (rs_gpio_configure(RS_SPI_ROUTE_PIN_MOSI, &input) != RS_OK) ||
        (rs_gpio_configure(RS_SPI_ROUTE_PIN_MISO, &input) != RS_OK) ||
        (rs_gpio_configure(RS_SPI_ROUTE_PIN_CS_N, &input) != RS_OK)) {
        return RS_EIO;
    }
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_RELEASE;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_SESSION_OWNED, false, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_arm(const rs_spi_segment_t *segment) {
#ifdef RS_SPI_TARGET_PRESENT
    uint32_t value;
    uint32_t payload_bytes;
    uint32_t transport_words;
    uint32_t transport_bytes;
    if ((segment == NULL) || ((uint32_t)segment->direction > (uint32_t)RS_SPI_DIRECTION_RX_ONLY)) {
        return RS_EINVAL;
    }
    if (rs_spi_transport_layout(segment->frames, segment->frame16, &payload_bytes, &transport_words,
                                &transport_bytes) != RS_OK) {
        return RS_EINVAL;
    }
    value = (segment->frame16 ? 1U : 0U) | ((uint32_t)segment->direction << 1U) |
            (segment->hold_cs ? 8U : 0U);
    RS_SPI_REG(RS_SPI_ABI_SEG_CONFIG) = value;
    RS_SPI_REG(RS_SPI_ABI_FRAME_COUNT) = segment->frames;
    RS_SPI_REG(RS_SPI_ABI_DUMMY) = segment->dummy;
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_ARM;
    return RS_OK;
#else
    (void)segment;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_dma_bind(uint32_t tx_channel, uint32_t rx_channel) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_spi_status_t status;
    uint32_t state;

    if (((tx_channel != RS_SPI_DMA_UNBOUND) && (tx_channel >= RS_DMA_CHANNEL_COUNT)) ||
        ((rx_channel != RS_SPI_DMA_UNBOUND) && (rx_channel >= RS_DMA_CHANNEL_COUNT)) ||
        ((tx_channel != RS_SPI_DMA_UNBOUND) && (tx_channel == rx_channel))) {
        return RS_EINVAL;
    }
    if (((tx_channel != RS_SPI_DMA_UNBOUND) &&
         (rs_dma_supports_request(RS_DMA_REQUEST_SPI_TX) != RS_OK)) ||
        ((rx_channel != RS_SPI_DMA_UNBOUND) &&
         (rs_dma_supports_request(RS_DMA_REQUEST_SPI_RX) != RS_OK))) {
        return RS_ENOTSUP;
    }
    if (rs_spi_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    state = status.status & UINT32_C(0xF);
    if (((status.status & ((UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN) |
                           (UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE))) !=
         ((UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN) |
          (UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE))) ||
        ((state != RS_SPI_ABI_STATE_DISABLED) && (state != RS_SPI_ABI_STATE_IDLE) &&
         (state != RS_SPI_ABI_STATE_HELD))) {
        return RS_EIO;
    }
    RS_SPI_REG(RS_SPI_ABI_TX_BIND) = 0U;
    RS_SPI_REG(RS_SPI_ABI_RX_BIND) = 0U;
    if (tx_channel != RS_SPI_DMA_UNBOUND) {
        RS_SPI_REG(RS_SPI_ABI_TX_BIND) = (UINT32_C(1) << RS_SPI_ABI_BIND_ENABLE) | tx_channel;
    }
    if (rx_channel != RS_SPI_DMA_UNBOUND) {
        RS_SPI_REG(RS_SPI_ABI_RX_BIND) = (UINT32_C(1) << RS_SPI_ABI_BIND_ENABLE) | rx_channel;
    }
    return RS_OK;
#else
    (void)tx_channel;
    (void)rx_channel;
    return RS_ENOTSUP;
#endif
}

#ifdef RS_SPI_TARGET_PRESENT
static rs_status_t rs_spi_dma_job_info(const rs_spi_dma_job_t *job, bool starting,
                                       uint32_t *expected_bytes, uint32_t *expected_frames) {
    rs_spi_status_t status;
    uint32_t payload_bytes;
    uint32_t transport_words;
    uint32_t transport_bytes;
    uint32_t segment;
    uint32_t direction;
    uint32_t binding;
    rs_dma_request_t request;

    if ((job == NULL) || (job->session == NULL) || (expected_bytes == NULL) ||
        (expected_frames == NULL) || (job->buffer == (uintptr_t)0U) ||
        ((job->buffer & (sizeof(uint32_t) - 1U)) != (uintptr_t)0U) ||
        (job->session->channel >= RS_DMA_CHANNEL_COUNT) ||
        ((job->direction != RS_SPI_DIRECTION_TX_ONLY) &&
         (job->direction != RS_SPI_DIRECTION_RX_ONLY))) {
        return RS_EINVAL;
    }
    if (rs_spi_get_status(&status) != RS_OK) {
        return RS_EIO;
    }
    if ((starting &&
         ((status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_PENDING)) == 0U)) ||
        ((status.status & UINT32_C(0xF)) == RS_SPI_ABI_STATE_CLOSING) || (status.fault != 0U)) {
        return RS_EIO;
    }
    segment = RS_SPI_REG(RS_SPI_ABI_SEG_CONFIG);
    direction = (segment >> RS_SPI_ABI_DIRECTION) & UINT32_C(0x3);
    if ((direction > (uint32_t)RS_SPI_DIRECTION_RX_ONLY) ||
        ((direction != (uint32_t)RS_SPI_DIRECTION_FULL_DUPLEX) &&
         (direction != (uint32_t)job->direction))) {
        return RS_EIO;
    }
    *expected_frames = RS_SPI_REG(RS_SPI_ABI_FRAME_COUNT);
    if ((rs_spi_transport_layout(*expected_frames, (segment & UINT32_C(1)) != 0U, &payload_bytes,
                                 &transport_words, &transport_bytes) != RS_OK) ||
        (status.payload_bytes != payload_bytes) || (status.transport_words != transport_words)) {
        return RS_EIO;
    }
    if (job->capacity_bytes < transport_bytes) {
        return RS_EINVAL;
    }
    binding = RS_SPI_REG((job->direction == RS_SPI_DIRECTION_TX_ONLY) ? RS_SPI_ABI_TX_BIND
                                                                      : RS_SPI_ABI_RX_BIND);
    if ((binding != ((UINT32_C(1) << RS_SPI_ABI_BIND_ENABLE) | job->session->channel))) {
        return RS_EIO;
    }
    request = (job->direction == RS_SPI_DIRECTION_TX_ONLY) ? RS_DMA_REQUEST_SPI_TX
                                                           : RS_DMA_REQUEST_SPI_RX;
    if (rs_dma_supports_request(request) != RS_OK) {
        return RS_ENOTSUP;
    }
    *expected_bytes = transport_bytes;
    return RS_OK;
}

static rs_status_t rs_spi_dma_abort_one(const rs_spi_dma_job_t *job, rs_timeout_t timeout) {
    rs_dma_status_t status;
    rs_status_t result = rs_dma_session_abort(job->session);

    if (result != RS_OK) {
        return result;
    }
    while (timeout-- != 0U) {
        result = rs_dma_get_status(job->session->channel, &status);
        if (result != RS_OK) {
            return result;
        }
        if (!status.busy) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}
#endif

rs_status_t rs_spi_dma_start(const rs_spi_dma_job_t *job) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_dma_config_t config;
    uint32_t expected_bytes;
    uint32_t expected_frames;
    rs_status_t result = rs_spi_dma_job_info(job, true, &expected_bytes, &expected_frames);

    if (result != RS_OK) {
        return result;
    }
    config = (rs_dma_config_t){
        .kind = RS_DMA_KIND_MM_TO_MM,
        .request = (job->direction == RS_SPI_DIRECTION_TX_ONLY) ? RS_DMA_REQUEST_SPI_TX
                                                                : RS_DMA_REQUEST_SPI_RX,
        .source = (job->direction == RS_SPI_DIRECTION_TX_ONLY)
                      ? job->buffer
                      : (uintptr_t)(RS_SOC_APB4_SPI_BASE + RS_SPI_ABI_DMA_RXDATA),
        .destination = (job->direction == RS_SPI_DIRECTION_TX_ONLY)
                           ? (uintptr_t)(RS_SOC_APB4_SPI_BASE + RS_SPI_ABI_DMA_TXDATA)
                           : job->buffer,
        .byte_count = expected_bytes,
        .width = RS_DMA_WIDTH_32,
        .source_increment = job->direction == RS_SPI_DIRECTION_TX_ONLY,
        .destination_increment = job->direction == RS_SPI_DIRECTION_RX_ONLY,
        .priority = 2U,
        .burst_beats = 1U,
    };
    (void)expected_frames;
    result = rs_dma_session_configure(job->session, &config);
    return (result == RS_OK) ? rs_dma_session_start(job->session) : result;
#else
    (void)job;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_dma_wait(const rs_spi_dma_job_t *job, rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_spi_status_t spi_status;
    rs_dma_status_t dma_status;
    uint32_t expected_bytes;
    uint32_t expected_frames;
    uint32_t direction;
    uint32_t state;
    bool hold_cs;
    rs_status_t result = rs_spi_dma_job_info(job, false, &expected_bytes, &expected_frames);

    if (result != RS_OK) {
        return result;
    }
    for (;;) {
        if (timeout-- == 0U) {
            return RS_ETIMEOUT;
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
    if (dma_status.busy || (dma_status.bytes_done != expected_bytes) ||
        (dma_status.remaining != 0U)) {
        return RS_EIO;
    }
    result = rs_spi_wait_status((UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN) |
                                    (UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE),
                                true, timeout);
    if (result != RS_OK) {
        return result;
    }
    if (rs_spi_get_status(&spi_status) != RS_OK) {
        return RS_EIO;
    }
    direction = (RS_SPI_REG(RS_SPI_ABI_SEG_CONFIG) >> RS_SPI_ABI_DIRECTION) & UINT32_C(0x3);
    hold_cs = (RS_SPI_REG(RS_SPI_ABI_SEG_CONFIG) & UINT32_C(0x8)) != 0U;
    state = spi_status.status & UINT32_C(0xF);
    if ((spi_status.fault != 0U) || (spi_status.frames_done != expected_frames) ||
        (spi_status.dma_status != 0U) || ((spi_status.levels & UINT32_C(0xF0F)) != 0U) ||
        (state != (hold_cs ? RS_SPI_ABI_STATE_HELD : RS_SPI_ABI_STATE_IDLE)) ||
        (((spi_status.status & (UINT32_C(1) << RS_SPI_ABI_STATUS_CS_ACTIVE)) != 0U) != hold_cs) ||
        (((direction == (uint32_t)RS_SPI_DIRECTION_TX_ONLY) ||
          (direction == (uint32_t)RS_SPI_DIRECTION_FULL_DUPLEX)) &&
         (spi_status.tx_words != spi_status.transport_words)) ||
        (((direction == (uint32_t)RS_SPI_DIRECTION_RX_ONLY) ||
          (direction == (uint32_t)RS_SPI_DIRECTION_FULL_DUPLEX)) &&
         ((spi_status.rx_words != spi_status.transport_words) ||
          (spi_status.rx_removed != spi_status.transport_words)))) {
        return RS_EIO;
    }
    return RS_OK;
#else
    (void)job;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_start(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_START;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_CS_ACTIVE, true, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_end(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_END;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_SEGMENT_CLEAN, true, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_abort(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    const uint32_t aborted = UINT32_C(1) << RS_SPI_ABI_IRQ_ABORTED;
    RS_SPI_REG(RS_SPI_ABI_IRQ_STATE) = aborted;
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_ABORT;
    while (timeout-- != 0U) {
        const uint32_t status = RS_SPI_REG(RS_SPI_ABI_STATUS);
        if (((status & UINT32_C(0xF)) == RS_SPI_ABI_STATE_CLOSING) &&
            ((status & (UINT32_C(1) << RS_SPI_ABI_STATUS_CS_ACTIVE)) == 0U) &&
            ((RS_SPI_REG(RS_SPI_ABI_IRQ_STATE) & aborted) != 0U)) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_abort_dma(const rs_spi_dma_job_t *tx_job, const rs_spi_dma_job_t *rx_job,
                             rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    rs_status_t tx_result = RS_OK;
    rs_status_t rx_result = RS_OK;
    rs_status_t result;

    if (((tx_job != NULL) &&
         ((tx_job->session == NULL) || (tx_job->session->channel >= RS_DMA_CHANNEL_COUNT))) ||
        ((rx_job != NULL) &&
         ((rx_job->session == NULL) || (rx_job->session->channel >= RS_DMA_CHANNEL_COUNT)))) {
        return RS_EINVAL;
    }
    result = rs_spi_abort(timeout);
    if (result != RS_OK) {
        return result;
    }
    if (tx_job != NULL) {
        tx_result = rs_spi_dma_abort_one(tx_job, timeout);
    }
    if (rx_job != NULL) {
        rx_result = rs_spi_dma_abort_one(rx_job, timeout);
    }
    if (tx_result != RS_OK) {
        return tx_result;
    }
    if (rx_result != RS_OK) {
        return rx_result;
    }
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE, true, timeout);
#else
    (void)tx_job;
    (void)rx_job;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_recover(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_RECOVER;
    return rs_spi_wait_status(UINT32_C(0xF), false, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_get_status(rs_spi_status_t *status) {
    if (status == NULL)
        return RS_EINVAL;
#ifdef RS_SPI_TARGET_PRESENT
    status->status = RS_SPI_REG(RS_SPI_ABI_STATUS);
    status->levels = RS_SPI_REG(RS_SPI_ABI_FIFO_LEVELS);
    status->fault = RS_SPI_REG(RS_SPI_ABI_FAULT_CODE);
    status->frames_done = RS_SPI_REG(RS_SPI_ABI_FRAMES_DONE);
    status->transport_words = RS_SPI_REG(RS_SPI_ABI_TRANSPORT_WORDS);
    status->tx_words = RS_SPI_REG(RS_SPI_ABI_TX_WORDS_ACCEPTED);
    status->rx_words = RS_SPI_REG(RS_SPI_ABI_RX_WORDS_PRODUCED);
    status->rx_removed = RS_SPI_REG(RS_SPI_ABI_RX_WORDS_REMOVED);
    status->dma_status = RS_SPI_REG(RS_SPI_ABI_DMA_STATUS);
    status->pins_ready = RS_SPI_REG(RS_SPI_ABI_PINS_READY);
    status->payload_bytes = RS_SPI_REG(RS_SPI_ABI_PAYLOAD_BYTES);
    status->clock_hz = RS_SPI_REG(RS_SPI_ABI_CLOCK_HZ);
    status->divider = RS_SPI_REG(RS_SPI_ABI_DIV);
    status->irq_state = RS_SPI_REG(RS_SPI_ABI_IRQ_STATE);
    status->tx_stall_cycles = RS_SPI_REG(RS_SPI_ABI_TX_STALL_CYCLES);
    status->rx_stall_cycles = RS_SPI_REG(RS_SPI_ABI_RX_STALL_CYCLES);
    return RS_OK;
#else
    (void)status;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_transfer_cpu(const uint32_t *tx_words, uint32_t *rx_words, uint32_t word_count,
                                rs_timeout_t timeout) {
    if ((word_count == 0U) || (tx_words == NULL && rx_words == NULL))
        return RS_EINVAL;
#ifdef RS_SPI_TARGET_PRESENT
    for (uint32_t index = 0U; index < word_count; ++index) {
        if (tx_words != NULL)
            RS_SPI_REG(RS_SPI_ABI_CPU_TXDATA) = tx_words[index];
        if (rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_RX_WAIT, false, timeout) != RS_OK)
            return RS_ETIMEOUT;
        if (rx_words != NULL)
            rx_words[index] = RS_SPI_REG(RS_SPI_ABI_CPU_RXDATA);
    }
    return RS_OK;
#else
    (void)tx_words;
    (void)rx_words;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}
