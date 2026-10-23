#ifndef RETROSOC_HAL_SPI_H
#define RETROSOC_HAL_SPI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/spi_regs.h>

typedef enum {
    RS_SPI_DIRECTION_TX_ONLY = RS_SPI_ABI_TX_ONLY,
    RS_SPI_DIRECTION_FULL_DUPLEX = RS_SPI_ABI_FULL_DUPLEX,
    RS_SPI_DIRECTION_RX_ONLY = RS_SPI_ABI_RX_ONLY,
} rs_spi_direction_t;

typedef struct {
    uint32_t clock_hz;
    uint32_t divider;
    uint16_t cs_setup;
    uint16_t cs_hold;
    uint16_t cs_inactive;
    bool cpol;
    bool cpha;
    bool lsb_first;
    bool miso_enable;
    bool display_dc;
} rs_spi_config_t;

typedef struct {
    uint32_t frames;
    rs_spi_direction_t direction;
    bool frame16;
    bool hold_cs;
    uint16_t dummy;
} rs_spi_segment_t;

typedef struct {
    uint32_t status;
    uint32_t levels;
    uint32_t fault;
    uint32_t frames_done;
    uint32_t transport_words;
    uint32_t tx_words;
    uint32_t rx_words;
    uint32_t rx_removed;
    uint32_t dma_status;
    uint32_t pins_ready;
    uint32_t payload_bytes;
} rs_spi_status_t;

rs_status_t rs_spi_probe(uint32_t *ip_id, uint32_t *version, uint32_t *capability);
rs_status_t rs_spi_divider_from_hz(uint32_t pclk_hz, uint32_t requested_sck_hz, uint32_t *divider,
                                   uint32_t *actual_sck_hz);
rs_status_t rs_spi_configure(const rs_spi_config_t *config);
rs_status_t rs_spi_acquire(rs_timeout_t timeout);
rs_status_t rs_spi_release(rs_timeout_t timeout);
rs_status_t rs_spi_arm(const rs_spi_segment_t *segment);
rs_status_t rs_spi_start(rs_timeout_t timeout);
rs_status_t rs_spi_end(rs_timeout_t timeout);
rs_status_t rs_spi_abort(rs_timeout_t timeout);
rs_status_t rs_spi_recover(rs_timeout_t timeout);
rs_status_t rs_spi_get_status(rs_spi_status_t *status);
rs_status_t rs_spi_transfer_cpu(const uint32_t *tx_words, uint32_t *rx_words, uint32_t word_count,
                                rs_timeout_t timeout);

#endif
