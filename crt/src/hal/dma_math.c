#include <limits.h>
#include <stdbool.h>
#include <stddef.h>

#include <retrosoc/hal/dma.h>

static bool rs_dma_address_valid(uintptr_t address, uint32_t byte_count, bool increment) {
    uintptr_t last_address;

    if (address > (uintptr_t)UINT32_MAX) {
        return false;
    }
    if (!increment) {
        return true;
    }
    last_address = address + (uintptr_t)(byte_count - sizeof(uint32_t));
    return last_address >= address && last_address <= (uintptr_t)UINT32_MAX;
}

static bool rs_dma_request_valid(const rs_dma_config_t *config) {
    switch (config->kind) {
    case RS_DMA_KIND_MM_TO_MM:
        return (config->request == RS_DMA_REQUEST_SOFTWARE) ||
               ((config->request >= RS_DMA_REQUEST_XPI_TX) &&
                (config->request <= RS_DMA_REQUEST_I2C1_RX));
    case RS_DMA_KIND_MM_TO_STREAM:
        return (config->request == RS_DMA_REQUEST_I2S_TX) ||
               (config->request == RS_DMA_REQUEST_CRYPTO_IN);
    case RS_DMA_KIND_STREAM_TO_MM:
        return (config->request == RS_DMA_REQUEST_I2S_RX) ||
               (config->request == RS_DMA_REQUEST_DVP_RX) ||
               (config->request == RS_DMA_REQUEST_CRYPTO_OUT);
    default:
        return false;
    }
}

rs_status_t rs_dma_config_validate(uint32_t channel, const rs_dma_config_t *config) {
    if ((channel >= RS_DMA_CHANNEL_COUNT) || (config == NULL) ||
        (config->width != RS_DMA_WIDTH_32) || (config->byte_count == 0U) ||
        ((config->byte_count % sizeof(uint32_t)) != 0U) || (config->priority > 3U) ||
        (config->burst_beats == 0U) || (config->burst_beats > RS_DMA_MAX_BURST_BEATS) ||
        !rs_dma_request_valid(config)) {
        return RS_EINVAL;
    }

    switch (config->kind) {
    case RS_DMA_KIND_MM_TO_MM:
        if ((config->source == (uintptr_t)0U) || (config->destination == (uintptr_t)0U) ||
            ((config->source % sizeof(uint32_t)) != 0U) ||
            ((config->destination % sizeof(uint32_t)) != 0U) ||
            !rs_dma_address_valid(config->source, config->byte_count, config->source_increment) ||
            !rs_dma_address_valid(config->destination, config->byte_count,
                                  config->destination_increment)) {
            return RS_EINVAL;
        }
        break;
    case RS_DMA_KIND_MM_TO_STREAM:
        if ((config->source == (uintptr_t)0U) || ((config->source % sizeof(uint32_t)) != 0U) ||
            !config->source_increment ||
            !rs_dma_address_valid(config->source, config->byte_count, true)) {
            return RS_EINVAL;
        }
        break;
    case RS_DMA_KIND_STREAM_TO_MM:
        if ((config->destination == (uintptr_t)0U) ||
            ((config->destination % sizeof(uint32_t)) != 0U) || !config->destination_increment ||
            !rs_dma_address_valid(config->destination, config->byte_count, true)) {
            return RS_EINVAL;
        }
        break;
    default:
        return RS_EINVAL;
    }
    return RS_OK;
}
