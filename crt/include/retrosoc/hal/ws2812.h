#ifndef RETROSOC_HAL_WS2812_H
#define RETROSOC_HAL_WS2812_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_WS2812_DEFAULT_BIT_PERIOD_NS UINT32_C(1250)
#define RS_WS2812_DEFAULT_T0H_NS        UINT32_C(350)
#define RS_WS2812_DEFAULT_T1H_NS        UINT32_C(700)
#define RS_WS2812_DEFAULT_RESET_NS      UINT32_C(300000)

#define RS_WS2812_ERROR_CONFIG          UINT32_C(0x01)
#define RS_WS2812_ERROR_UNDERFLOW       UINT32_C(0x02)
#define RS_WS2812_ERROR_COMMAND         UINT32_C(0x04)

#define RS_WS2812_INTR_DONE             UINT32_C(0x01)
#define RS_WS2812_INTR_FIFO_LOW         UINT32_C(0x02)
#define RS_WS2812_INTR_ERROR            UINT32_C(0x04)
#define RS_WS2812_INTR_ABORTED          UINT32_C(0x08)
#define RS_WS2812_INTR_ALL              UINT32_C(0x0F)

typedef struct {
    uint32_t source_clock_hz;
    uint32_t bit_period_ns;
    uint32_t t0h_ns;
    uint32_t t1h_ns;
    uint32_t reset_ns;
    uint32_t fifo_watermark;
} rs_ws2812_config_t;

typedef struct {
    uint16_t bit_cycles;
    uint16_t t0h_cycles;
    uint16_t t1h_cycles;
    uint32_t reset_cycles;
} rs_ws2812_timing_t;

typedef struct {
    uint32_t fifo_level;
    uint32_t remaining_words;
    uint32_t error_status;
    uint32_t interrupt_state;
    bool busy;
    bool fifo_empty;
    bool fifo_full;
    bool config_valid;
    bool reset_active;
} rs_ws2812_status_t;

uint32_t rs_ws2812_pack_grb(uint8_t red, uint8_t green, uint8_t blue);
rs_status_t rs_ws2812_timing_from_ns(const rs_ws2812_config_t *config, rs_ws2812_timing_t *timing);
rs_status_t rs_ws2812_init(const rs_ws2812_config_t *config);
rs_status_t rs_ws2812_get_status(rs_ws2812_status_t *status);
rs_status_t rs_ws2812_push(uint32_t pixel, rs_timeout_t timeout);
rs_status_t rs_ws2812_start(uint32_t pixel_count);
rs_status_t rs_ws2812_wait(rs_timeout_t timeout);
rs_status_t rs_ws2812_abort(rs_timeout_t timeout);
rs_status_t rs_ws2812_irq_enable(uint32_t mask);
rs_status_t rs_ws2812_irq_ack(uint32_t mask);
rs_status_t rs_ws2812_write(const uint32_t *pixels, size_t pixel_count, rs_timeout_t timeout);
rs_status_t rs_ws2812_write_dma(const uint32_t *pixels, size_t pixel_count, rs_timeout_t timeout);
void ip_ws2812_test(int argc, char **argv);

#endif
