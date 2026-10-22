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
    while (timeout-- != 0U) {
        const bool value = (RS_SPI_REG(RS_SPI_ABI_STATUS) & mask) != 0U;
        if (value == set) {
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
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_ENABLE;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_GPIO_READY, true, timeout);
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
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_DISABLE;
    result = rs_spi_wait_status(UINT32_C(0xF), false, timeout);
    if (result != RS_OK)
        return result;
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
    if ((segment == NULL) || (segment->frames == 0U) ||
        ((uint32_t)segment->direction > (uint32_t)RS_SPI_DIRECTION_RX_ONLY)) {
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
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_ABORT;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_TRANSPORT_IDLE, true, timeout);
#else
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_spi_recover(rs_timeout_t timeout) {
#ifdef RS_SPI_TARGET_PRESENT
    RS_SPI_REG(RS_SPI_ABI_COMMAND) = UINT32_C(1) << RS_SPI_ABI_RECOVER;
    return rs_spi_wait_status(UINT32_C(1) << RS_SPI_ABI_STATUS_SESSION_OWNED, false, timeout);
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
