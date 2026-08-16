#include <limits.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/dma.h>
#include <retrosoc/hal/gpio.h>
#include <retrosoc/hal/uart.h>

#define RS_UART_REG(offset)          RS_SOC_REG32(RS_SOC_APB4_UART0_BASE, (offset))

#define RS_UART_BAUD_INT             RS_UART_REG(UINT32_C(0x00))
#define RS_UART_BAUD_FRAC            RS_UART_REG(UINT32_C(0x04))
#define RS_UART_LINE_CTRL            RS_UART_REG(UINT32_C(0x08))
#define RS_UART_CTRL                 RS_UART_REG(UINT32_C(0x0C))
#define RS_UART_TXDATA               RS_UART_REG(UINT32_C(0x10))
#define RS_UART_RXDATA               RS_UART_REG(UINT32_C(0x14))
#define RS_UART_STATUS               RS_UART_REG(UINT32_C(0x18))
#define RS_UART_FIFO_LEVEL           RS_UART_REG(UINT32_C(0x1C))
#define RS_UART_FIFO_CTRL            RS_UART_REG(UINT32_C(0x20))
#define RS_UART_TX_WATERMARK         RS_UART_REG(UINT32_C(0x24))
#define RS_UART_RX_WATERMARK         RS_UART_REG(UINT32_C(0x28))
#define RS_UART_RX_TIMEOUT           RS_UART_REG(UINT32_C(0x2C))
#define RS_UART_ERROR_STATUS         RS_UART_REG(UINT32_C(0x30))
#define RS_UART_INTR_STATE           RS_UART_REG(UINT32_C(0x34))
#define RS_UART_INTR_ENABLE          RS_UART_REG(UINT32_C(0x38))
#define RS_UART_INTR_TEST            RS_UART_REG(UINT32_C(0x40))
#define RS_UART_DMA_CTRL             RS_UART_REG(UINT32_C(0x44))
#define RS_UART_FLOW_CTRL            RS_UART_REG(UINT32_C(0x48))
#define RS_UART_RTS_WATERMARK        RS_UART_REG(UINT32_C(0x4C))

#define RS_UART_CTRL_TX_ENABLE       UINT32_C(0x01)
#define RS_UART_CTRL_RX_ENABLE       UINT32_C(0x02)
#define RS_UART_CTRL_LOOPBACK        UINT32_C(0x04)
#define RS_UART_STATUS_TX_BUSY       UINT32_C(0x04)
#define RS_UART_STATUS_RX_BUSY       UINT32_C(0x08)
#define RS_UART_STATUS_TX_FULL       UINT32_C(0x20)
#define RS_UART_STATUS_RX_EMPTY      UINT32_C(0x40)
#define RS_UART_STATUS_CONFIG_VALID  UINT32_C(0x100)
#define RS_UART_FIFO_TX_FLUSH        UINT32_C(0x01)
#define RS_UART_FIFO_RX_FLUSH        UINT32_C(0x02)
#define RS_UART_ERROR_ALL            UINT32_C(0x7F)
#define RS_UART_DMA_TX_ENABLE        UINT32_C(0x01)
#define RS_UART_DMA_RX_ENABLE        UINT32_C(0x02)
#define RS_UART_FLOW_AUTO_CTS        UINT32_C(0x01)
#define RS_UART_FLOW_AUTO_RTS        UINT32_C(0x02)
#define RS_UART_CTS_GPIO             UINT32_C(0)
#define RS_UART_RTS_GPIO             UINT32_C(1)
#define RS_UART_RTS_ASSERT_DEFAULT   UINT32_C(32)
#define RS_UART_RTS_DEASSERT_DEFAULT UINT32_C(48)

static uint32_t rs_uart_control_from_config(const rs_uart_config_t *config) {
    uint32_t control = 0U;

    if (config->tx_enable) {
        control |= RS_UART_CTRL_TX_ENABLE;
    }
    if (config->rx_enable) {
        control |= RS_UART_CTRL_RX_ENABLE;
    }
    if (config->loopback_enable) {
        control |= RS_UART_CTRL_LOOPBACK;
    }
    return control;
}

static bool rs_uart_config_valid(const rs_uart_config_t *config) {
    return (config != NULL) && (config->data_bits >= 5U) && (config->data_bits <= 8U) &&
           ((config->stop_bits == 1U) || (config->stop_bits == 2U)) &&
           (config->parity <= RS_UART_PARITY_ODD) && (config->tx_watermark < 64U) &&
           (config->rx_watermark > 0U) && (config->rx_watermark <= 64U) &&
           (!config->auto_rts_enable || ((config->rts_assert_level < config->rts_deassert_level) &&
                                         (config->rts_deassert_level <= 64U)));
}

static rs_status_t rs_uart_flow_gpio_configure(const rs_uart_config_t *config) {
    const rs_gpio_config_t pin_config = {
        .mode = RS_GPIO_MODE_ALT0,
        .pull = RS_GPIO_PULL_NONE,
        .trigger = RS_GPIO_TRIGGER_NONE,
        .output_high = true,
        .open_drain = false,
        .input_cmos = false,
        .filter_enable = false,
        .interrupt_enable = false,
    };
    rs_status_t status = RS_OK;

    if (config->auto_cts_enable) {
        status = rs_gpio_configure(RS_UART_CTS_GPIO, &pin_config);
    }
    if ((status == RS_OK) && config->auto_rts_enable) {
        status = rs_gpio_configure(RS_UART_RTS_GPIO, &pin_config);
    }
    return status;
}

rs_status_t rs_uart_configure(const rs_uart_config_t *config, rs_timeout_t timeout) {
    rs_uart_timing_t timing;
    rs_status_t status;
    uint32_t flow_control = 0U;
    uint32_t line_control;
    uint32_t rts_assert_level;
    uint32_t rts_deassert_level;

    if (!rs_uart_config_valid(config) ||
        (rs_uart_timing_calculate(config->source_clock_hz, config->baud_rate, &timing) != RS_OK)) {
        return RS_EINVAL;
    }

    RS_UART_CTRL = 0U;
    while (((RS_UART_STATUS & (RS_UART_STATUS_TX_BUSY | RS_UART_STATUS_RX_BUSY)) != 0U) &&
           (timeout != 0U)) {
        timeout--;
    }
    if ((RS_UART_STATUS & (RS_UART_STATUS_TX_BUSY | RS_UART_STATUS_RX_BUSY)) != 0U) {
        return RS_ETIMEOUT;
    }

    status = rs_uart_flow_gpio_configure(config);
    if (status != RS_OK) {
        return status;
    }

    RS_UART_FIFO_CTRL = RS_UART_FIFO_TX_FLUSH | RS_UART_FIFO_RX_FLUSH;
    RS_UART_ERROR_STATUS = RS_UART_ERROR_ALL;
    RS_UART_INTR_STATE = RS_UART_INTR_ALL;
    RS_UART_BAUD_INT = timing.baud_integer;
    RS_UART_BAUD_FRAC = timing.baud_fraction;
    line_control = ((uint32_t)config->data_bits - 5U) | (((uint32_t)config->stop_bits - 1U) << 2U) |
                   ((uint32_t)config->parity << 3U);
    RS_UART_LINE_CTRL = line_control;
    RS_UART_TX_WATERMARK = config->tx_watermark;
    RS_UART_RX_WATERMARK = config->rx_watermark;
    RS_UART_RX_TIMEOUT = config->rx_timeout_bits;
    RS_UART_DMA_CTRL = 0U;
    if (config->auto_cts_enable) {
        flow_control |= RS_UART_FLOW_AUTO_CTS;
    }
    if (config->auto_rts_enable) {
        flow_control |= RS_UART_FLOW_AUTO_RTS;
    }
    rts_assert_level =
        config->auto_rts_enable ? config->rts_assert_level : RS_UART_RTS_ASSERT_DEFAULT;
    rts_deassert_level =
        config->auto_rts_enable ? config->rts_deassert_level : RS_UART_RTS_DEASSERT_DEFAULT;
    RS_UART_RTS_WATERMARK = rts_assert_level | (rts_deassert_level << 16U);
    RS_UART_FLOW_CTRL = flow_control;
    RS_UART_CTRL = rs_uart_control_from_config(config);

    return ((RS_UART_STATUS & RS_UART_STATUS_CONFIG_VALID) != 0U) ? RS_OK : RS_EIO;
}

rs_status_t rs_uart_init(uint32_t source_clock_hz, uint32_t baud_rate) {
    const rs_uart_config_t config = {
        .source_clock_hz = source_clock_hz,
        .baud_rate = baud_rate,
        .data_bits = 8U,
        .stop_bits = 1U,
        .parity = RS_UART_PARITY_NONE,
        .tx_watermark = 16U,
        .rx_watermark = 32U,
        .rx_timeout_bits = 32U,
        .tx_enable = true,
        .rx_enable = true,
        .loopback_enable = false,
        .auto_cts_enable = false,
        .auto_rts_enable = false,
        .rts_assert_level = (uint8_t)RS_UART_RTS_ASSERT_DEFAULT,
        .rts_deassert_level = (uint8_t)RS_UART_RTS_DEASSERT_DEFAULT,
    };
    return rs_uart_configure(&config, RS_TIMEOUT_DEFAULT);
}

rs_status_t rs_uart_write(const uint8_t *data, size_t length, rs_timeout_t timeout) {
    size_t index;

    if ((data == NULL) && (length != 0U)) {
        return RS_EINVAL;
    }
    for (index = 0U; index < length; index++) {
        while ((RS_UART_STATUS & RS_UART_STATUS_TX_FULL) != 0U) {
            if (timeout == 0U) {
                return RS_ETIMEOUT;
            }
            timeout--;
        }
        RS_UART_TXDATA = data[index];
    }
    return RS_OK;
}

rs_status_t rs_uart_read(rs_uart_rx_data_t *data, size_t length, rs_timeout_t timeout) {
    size_t index;

    if ((data == NULL) && (length != 0U)) {
        return RS_EINVAL;
    }
    for (index = 0U; index < length; index++) {
        uint32_t value;

        while ((RS_UART_STATUS & RS_UART_STATUS_RX_EMPTY) != 0U) {
            if (timeout == 0U) {
                return RS_ETIMEOUT;
            }
            timeout--;
        }
        value = RS_UART_RXDATA;
        data[index].data = (uint8_t)value;
        data[index].errors = (uint8_t)((value >> 8U) & UINT32_C(0x0F));
    }
    return RS_OK;
}

rs_status_t rs_uart_flush(bool flush_tx, bool flush_rx, rs_timeout_t timeout) {
    const uint32_t old_control = RS_UART_CTRL;
    uint32_t control = old_control;
    uint32_t command = 0U;

    if (!flush_tx && !flush_rx) {
        return RS_EINVAL;
    }
    if (flush_tx) {
        control &= ~RS_UART_CTRL_TX_ENABLE;
        command |= RS_UART_FIFO_TX_FLUSH;
    }
    if (flush_rx) {
        control &= ~RS_UART_CTRL_RX_ENABLE;
        command |= RS_UART_FIFO_RX_FLUSH;
    }
    RS_UART_CTRL = control;
    while (((RS_UART_STATUS & (RS_UART_STATUS_TX_BUSY | RS_UART_STATUS_RX_BUSY)) != 0U) &&
           (timeout != 0U)) {
        timeout--;
    }
    if ((RS_UART_STATUS & (RS_UART_STATUS_TX_BUSY | RS_UART_STATUS_RX_BUSY)) != 0U) {
        return RS_ETIMEOUT;
    }
    RS_UART_FIFO_CTRL = command;
    RS_UART_CTRL = old_control;
    return RS_OK;
}

rs_status_t rs_uart_get_status(rs_uart_status_t *status) {
    uint32_t levels;

    if (status == NULL) {
        return RS_EINVAL;
    }
    levels = RS_UART_FIFO_LEVEL;
    status->flags = RS_UART_STATUS;
    status->tx_level = levels & UINT32_C(0x7F);
    status->rx_level = (levels >> 16U) & UINT32_C(0x7F);
    status->errors = RS_UART_ERROR_STATUS;
    status->interrupt_state = RS_UART_INTR_STATE;
    return RS_OK;
}

rs_status_t rs_uart_irq_enable(uint32_t mask) {
    if ((mask & ~RS_UART_INTR_ALL) != 0U) {
        return RS_EINVAL;
    }
    RS_UART_INTR_ENABLE = mask;
    return RS_OK;
}

rs_status_t rs_uart_irq_ack(uint32_t mask) {
    if ((mask == 0U) || ((mask & ~RS_UART_INTR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    RS_UART_INTR_STATE = mask;
    return RS_OK;
}

rs_status_t rs_uart_irq_test(uint32_t mask) {
    if ((mask == 0U) || ((mask & ~RS_UART_INTR_ALL) != 0U)) {
        return RS_EINVAL;
    }
    RS_UART_INTR_TEST = mask;
    return RS_OK;
}

rs_status_t rs_uart_write_dma(const uint32_t *words, size_t count, rs_timeout_t timeout) {
    size_t index;
    rs_status_t status;

    if ((words == NULL) || (count == 0U) || (count > UINT32_MAX)) {
        return RS_EINVAL;
    }
    for (index = 0U; index < count; index++) {
        if ((words[index] & UINT32_C(0xFFFFFF00)) != 0U) {
            return RS_EINVAL;
        }
    }
    RS_UART_DMA_CTRL = RS_UART_DMA_TX_ENABLE;
    status = rs_dma_config(RS_DMA_MODE_UART_TX, (uintptr_t)words, 1U,
                           RS_SOC_APB4_UART0_BASE + UINT32_C(0x10), 0U, (uint32_t)count);
    if (status == RS_OK) {
        status = rs_dma_start();
    }
    if (status == RS_OK) {
        status = rs_dma_wait(timeout);
    }
    RS_UART_DMA_CTRL = 0U;
    return status;
}

rs_status_t rs_uart_read_dma(uint32_t *words, size_t count, rs_timeout_t timeout) {
    rs_status_t status;

    if ((words == NULL) || (count == 0U) || (count > UINT32_MAX)) {
        return RS_EINVAL;
    }
    RS_UART_DMA_CTRL = RS_UART_DMA_RX_ENABLE;
    status = rs_dma_config(RS_DMA_MODE_UART_RX, RS_SOC_APB4_UART0_BASE + UINT32_C(0x14), 0U,
                           (uintptr_t)words, 1U, (uint32_t)count);
    if (status == RS_OK) {
        status = rs_dma_start();
    }
    if (status == RS_OK) {
        status = rs_dma_wait(timeout);
    }
    RS_UART_DMA_CTRL = 0U;
    return status;
}

void putch(char ch) {
    const uint8_t value = (uint8_t)ch;
    (void)rs_uart_write(&value, 1U, RS_TIMEOUT_DEFAULT);
}
