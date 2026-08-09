#ifndef RETROSOC_HAL_UART_H
#define RETROSOC_HAL_UART_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>

#define RS_UART_ERROR_PARITY      UINT32_C(0x01)
#define RS_UART_ERROR_FRAME       UINT32_C(0x02)
#define RS_UART_ERROR_BREAK       UINT32_C(0x04)
#define RS_UART_ERROR_NOISE       UINT32_C(0x08)

#define RS_UART_INTR_RX_WATERMARK UINT32_C(0x01)
#define RS_UART_INTR_RX_TIMEOUT   UINT32_C(0x02)
#define RS_UART_INTR_TX_WATERMARK UINT32_C(0x04)
#define RS_UART_INTR_TX_DONE      UINT32_C(0x08)
#define RS_UART_INTR_RX_ERROR     UINT32_C(0x10)
#define RS_UART_INTR_BREAK        UINT32_C(0x20)
#define RS_UART_INTR_ALL          UINT32_C(0x3F)

typedef enum {
    RS_UART_PARITY_NONE = 0,
    RS_UART_PARITY_EVEN = 1,
    RS_UART_PARITY_ODD = 2,
} rs_uart_parity_t;

typedef struct {
    uint32_t source_clock_hz;
    uint32_t baud_rate;
    uint8_t data_bits;
    uint8_t stop_bits;
    rs_uart_parity_t parity;
    uint8_t tx_watermark;
    uint8_t rx_watermark;
    uint16_t rx_timeout_bits;
    bool tx_enable;
    bool rx_enable;
    bool loopback_enable;
} rs_uart_config_t;

typedef struct {
    uint32_t baud_integer;
    uint32_t baud_fraction;
} rs_uart_timing_t;

typedef struct {
    uint8_t data;
    uint8_t errors;
} rs_uart_rx_data_t;

typedef struct {
    uint32_t flags;
    uint32_t tx_level;
    uint32_t rx_level;
    uint32_t errors;
    uint32_t interrupt_state;
} rs_uart_status_t;

rs_status_t rs_uart_timing_calculate(uint32_t source_clock_hz, uint32_t baud_rate,
                                     rs_uart_timing_t *timing);
rs_status_t rs_uart_init(uint32_t source_clock_hz, uint32_t baud_rate);
rs_status_t rs_uart_configure(const rs_uart_config_t *config, rs_timeout_t timeout);
rs_status_t rs_uart_write(const uint8_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_uart_read(rs_uart_rx_data_t *data, size_t length, rs_timeout_t timeout);
rs_status_t rs_uart_flush(bool flush_tx, bool flush_rx, rs_timeout_t timeout);
rs_status_t rs_uart_get_status(rs_uart_status_t *status);
rs_status_t rs_uart_irq_enable(uint32_t mask);
rs_status_t rs_uart_irq_ack(uint32_t mask);
rs_status_t rs_uart_irq_test(uint32_t mask);
rs_status_t rs_uart_write_dma(const uint32_t *words, size_t count, rs_timeout_t timeout);
rs_status_t rs_uart_read_dma(uint32_t *words, size_t count, rs_timeout_t timeout);
void putch(char ch);

#endif
