#include <retrosoc/core/soc.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/lib/printf.h>

rs_status_t rs_dma_config(uint32_t mode, uintptr_t source, uint32_t source_increment,
                          uintptr_t destination, uint32_t destination_increment,
                          uint32_t transfer_words) {
    if ((mode > RS_DMA_MODE_DVP_RX) || (source == 0U) || (destination == 0U) ||
        (transfer_words == 0U) || (source_increment > 1U) || (destination_increment > 1U)) {
        return RS_EINVAL;
    }

    reg_dma_mode = mode;
    reg_dma_srcaddr = (uint32_t)source;
    reg_dma_srcincr = source_increment;
    reg_dma_dstaddr = (uint32_t)destination;
    reg_dma_dstincr = destination_increment;
    reg_dma_xferlen = transfer_words;
    return RS_OK;
}

rs_status_t rs_dma_start(void) {
    reg_dma_error_status = RS_SOC_DMA_ERROR_PENDING;
    reg_dma_start = 1U;
    return RS_OK;
}

rs_status_t rs_dma_stop(void) {
    reg_dma_stop = 1U;
    return RS_OK;
}

rs_status_t rs_dma_reset(void) {
    (void)rs_dma_stop();
    reg_dma_reset = 1U;
    (void)rs_dma_stop();
    return RS_OK;
}

rs_status_t rs_dma_wait(rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        if ((reg_dma_error_status & RS_SOC_DMA_ERROR_PENDING) != 0U) {
            return RS_EIO;
        }
        if (reg_dma_status == 1U) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_dma_get_error(rs_dma_error_t *error) {
    uint32_t status;

    if (error == NULL) {
        return RS_EINVAL;
    }

    status = reg_dma_error_status;
    error->response_code =
        (status & RS_SOC_DMA_ERROR_RESPONSE_MASK) >> RS_SOC_DMA_ERROR_RESPONSE_SHIFT;
    error->address = (uintptr_t)reg_dma_error_addr;
    if ((status & RS_SOC_DMA_ERROR_PENDING) != 0U) {
        reg_dma_error_status = RS_SOC_DMA_ERROR_PENDING;
        return RS_EIO;
    }
    return RS_OK;
}

void ip_dma_test(void) {
    rs_i2s_config_t i2s_config = {
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
    };

    printf("dma test\n");
    if ((rs_i2s_configure(&i2s_config) != RS_OK) || (rs_i2s_enable(true, false) != RS_OK)) {
        printf("dma i2s configure failed\n");
        return;
    }

    if ((rs_dma_config(RS_DMA_MODE_I2S_TX, 0x40000000U, 1U, rs_i2s_txdata_address(), 0U, 512U) !=
         RS_OK) ||
        (rs_dma_start() != RS_OK) || (rs_dma_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        printf("dma transmit failed\n");
        return;
    }

    i2s_config.stream_tx = false;
    i2s_config.stream_rx = true;
    if ((rs_i2s_configure(&i2s_config) != RS_OK) || (rs_i2s_enable(false, true) != RS_OK) ||
        (rs_dma_config(RS_DMA_MODE_I2S_RX, rs_i2s_rxdata_address(), 0U, 0x41000000U, 1U, 180U) !=
         RS_OK) ||
        (rs_dma_start() != RS_OK) || (rs_dma_wait(RS_TIMEOUT_DEFAULT) != RS_OK)) {
        printf("dma receive failed\n");
        (void)rs_i2s_disable();
        return;
    }
    (void)rs_i2s_disable();
    printf("dma test passed\n");
}
