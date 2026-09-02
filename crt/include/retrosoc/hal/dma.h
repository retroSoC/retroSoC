#ifndef RETROSOC_HAL_DMA_H
#define RETROSOC_HAL_DMA_H

#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/dma_regs.h>

typedef struct {
    uint32_t code;
    uint32_t response_code;
    uintptr_t address;
    bool read;
} rs_dma_error_t;

typedef enum {
    RS_DMA_KIND_MM_TO_MM = 0,
    RS_DMA_KIND_MM_TO_STREAM = 1,
    RS_DMA_KIND_STREAM_TO_MM = 2,
} rs_dma_transfer_kind_t;

typedef enum {
    RS_DMA_WIDTH_8 = 0,
    RS_DMA_WIDTH_16 = 1,
    RS_DMA_WIDTH_32 = 2,
} rs_dma_width_t;

typedef enum {
    RS_DMA_REQUEST_SOFTWARE = 0,
    RS_DMA_REQUEST_I2S_TX = 1,
    RS_DMA_REQUEST_I2S_RX = 2,
    RS_DMA_REQUEST_XPI_TX = 3,
    RS_DMA_REQUEST_XPI_RX = 4,
    RS_DMA_REQUEST_UART_TX = 5,
    RS_DMA_REQUEST_UART_RX = 6,
    RS_DMA_REQUEST_I2C0_TX = 7,
    RS_DMA_REQUEST_I2C0_RX = 8,
    RS_DMA_REQUEST_I2C1_TX = 9,
    RS_DMA_REQUEST_I2C1_RX = 10,
    RS_DMA_REQUEST_DVP_RX = 11,
    RS_DMA_REQUEST_CRYPTO_IN = 12,
    RS_DMA_REQUEST_CRYPTO_OUT = 13,
} rs_dma_request_t;

typedef enum {
    RS_DMA_CHANNEL_UART0 = 0,
    RS_DMA_CHANNEL_I2C0 = 1,
    RS_DMA_CHANNEL_I2C1 = 2,
    RS_DMA_CHANNEL_BULK = 3,
    RS_DMA_CHANNEL_CRYPTO_IN = 4,
    RS_DMA_CHANNEL_CRYPTO_OUT = 5,
} rs_dma_channel_t;

typedef struct {
    rs_dma_transfer_kind_t kind;
    rs_dma_request_t request;
    uintptr_t source;
    uintptr_t destination;
    uint32_t byte_count;
    rs_dma_width_t width;
    bool source_increment;
    bool destination_increment;
    bool crc_enable;
    bool crc_final;
    uint32_t crc_expected;
    uint8_t priority;
    uint8_t burst_beats;
} rs_dma_config_t;

typedef struct {
    bool busy;
    bool suspended;
    bool done;
    bool aborted;
    bool error;
    bool stream_last_seen;
    uint32_t events;
    uint32_t bytes_done;
    uint32_t remaining;
    uint64_t stall_cycles;
    uint32_t crc_result;
} rs_dma_status_t;

typedef struct {
    uint32_t next_ptr;
    uint32_t source;
    uint32_t destination;
    uint32_t byte_count;
    int32_t source_stride;
    int32_t destination_stride;
    uint16_t y_count;
    uint16_t reserved;
    uint32_t control;
    uint32_t crc_expected;
    uint32_t crc_seed;
    uint32_t crc_result;
    uint32_t status;
    uint32_t bytes_done;
    uint32_t error_status;
    uint32_t reserved_tail;
    uint32_t reserved_tail2;
} rs_dma_tcd_t;

_Static_assert(sizeof(rs_dma_tcd_t) == 64U, "DMA TCD ABI must be 64 bytes");

#define RS_DMA_TCD_VALID          UINT32_C(0x00000001)
#define RS_DMA_TCD_SRC_INC        UINT32_C(0x00000002)
#define RS_DMA_TCD_DST_INC        UINT32_C(0x00000004)
#define RS_DMA_TCD_CRC_ENABLE     UINT32_C(0x00000008)
#define RS_DMA_TCD_CRC_FINAL      UINT32_C(0x00000010)
#define RS_DMA_TCD_INT_DONE       UINT32_C(0x00000020)
#define RS_DMA_TCD_INT_ERROR      UINT32_C(0x00000040)
#define RS_DMA_TCD_KIND_SHIFT     8U
#define RS_DMA_TCD_REQUEST_SHIFT  12U
#define RS_DMA_TCD_PRIORITY_SHIFT 16U
#define RS_DMA_TCD_BURST_SHIFT    20U

rs_status_t rs_dma_config_validate(uint32_t channel, const rs_dma_config_t *config);
rs_status_t rs_dma_configure(uint32_t channel, const rs_dma_config_t *config);
rs_status_t rs_dma_tcd_validate(uint32_t channel, const rs_dma_tcd_t *tcd);
rs_status_t rs_dma_submit_tcd(uint32_t channel, rs_dma_tcd_t *tcd, rs_timeout_t timeout);
rs_status_t rs_dma_submit_tcd_chain(uint32_t channel, rs_dma_tcd_t *first, uint32_t max_tcds,
                                    rs_timeout_t timeout);
rs_status_t rs_dma_start(uint32_t channel);
rs_status_t rs_dma_suspend(uint32_t channel);
rs_status_t rs_dma_resume(uint32_t channel);
rs_status_t rs_dma_abort(uint32_t channel);
rs_status_t rs_dma_abort_wait(uint32_t channel, rs_timeout_t timeout);
rs_status_t rs_dma_reset(uint32_t channel);
rs_status_t rs_dma_get_status(uint32_t channel, rs_dma_status_t *status);
rs_status_t rs_dma_wait(uint32_t channel, rs_timeout_t timeout);
rs_status_t rs_dma_get_error(uint32_t channel, rs_dma_error_t *error);
rs_status_t rs_dma_irq_enable(uint32_t channel_mask);
rs_status_t rs_dma_irq_pending(uint32_t *channel_mask);
rs_status_t rs_dma_irq_clear(uint32_t channel_mask);
void ip_dma_test(void);

#endif
