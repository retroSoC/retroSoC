#ifndef RETROSOC_HAL_XPI_PSRAM_H
#define RETROSOC_HAL_XPI_PSRAM_H

#include <retrosoc/hal/xpi.h>

#define RS_XPI_PSRAM_BASE        UINT32_C(0x54000000)
#define RS_XPI_PSRAM_BYTES       UINT32_C(0x00800000)
#define RS_XPI_PSRAM_BURST_BEATS UINT8_C(4)

typedef struct {
    bool initialized;
    uint32_t memory_clock_hz;
    uint32_t capacity_bytes;
    uint8_t id[6];
} rs_xpi_psram_t;

/* ESP-PSRAM64H reference profile: slot 1, LUT 8..11, QPI SDR, SCK=MEM/2.
 * Caller owns XPI exclusively, routes NSS1, and executes code/IRQs from SRAM.
 * Clock changes/reset invalidate this software session; explicitly initialize
 * again before using memory. This is not physical part/rate qualification. */
rs_status_t rs_xpi_psram_timing(uint32_t memory_clock_hz, rs_xpi_slot_config_t *config);
rs_status_t rs_xpi_psram_initialize(uint32_t memory_clock_hz, rs_timeout_t timeout,
                                    rs_xpi_psram_t *device);
/* Direct DMA uses SOFTWARE request and mapped addresses, not XPI TX/RX FIFO.
 * Align bases to 16 bytes for four-beat bursts; the DMA splits at 4 KiB. */
rs_status_t rs_xpi_psram_validate_dma(const rs_xpi_psram_t *device, uint32_t address,
                                      uint32_t bytes, uint8_t burst_beats);

#endif
