#ifndef RETROSOC_HAL_DMA_H
#define RETROSOC_HAL_DMA_H

#include <stdint.h>

#include <retrosoc/core/status.h>

typedef struct {
    uint32_t response_code;
    uintptr_t address;
} rs_dma_error_t;

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
