#ifndef RETROSOC_HAL_DMA_H
#define RETROSOC_HAL_DMA_H

#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t response_code;
    uintptr_t address;
} rs_dma_error_t;

#define RS_DMA_MODE_SOFTWARE UINT32_C(0)
#define RS_DMA_MODE_I2S_TX   UINT32_C(1)
#define RS_DMA_MODE_I2S_RX   UINT32_C(2)
#define RS_DMA_MODE_QSPI_TX  UINT32_C(3)
#define RS_DMA_MODE_QSPI_RX  UINT32_C(4)
#define RS_DMA_MODE_UART_TX  UINT32_C(5)
#define RS_DMA_MODE_UART_RX  UINT32_C(6)
#define RS_DMA_MODE_I2C0_TX  UINT32_C(7)
#define RS_DMA_MODE_I2C0_RX  UINT32_C(8)
#define RS_DMA_MODE_I2C1_TX  UINT32_C(9)
#define RS_DMA_MODE_I2C1_RX  UINT32_C(10)
#define RS_DMA_MODE_DVP_RX   UINT32_C(11)

rs_status_t rs_dma_config(uint32_t mode, uintptr_t source, uint32_t source_increment,
                          uintptr_t destination, uint32_t destination_increment,
                          uint32_t transfer_words);
rs_status_t rs_dma_start(void);
rs_status_t rs_dma_stop(void);
rs_status_t rs_dma_reset(void);
rs_status_t rs_dma_wait(rs_timeout_t timeout);
rs_status_t rs_dma_get_error(rs_dma_error_t *error);
void ip_dma_test(void);

#endif
